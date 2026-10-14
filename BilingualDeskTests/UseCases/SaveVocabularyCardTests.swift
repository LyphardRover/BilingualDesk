// File: BilingualDeskTests/UseCases/SaveVocabularyCardTests.swift
// Targets: Tests
import Foundation
import XCTest
@testable import BilingualDesk

/// U10–U12：SaveVocabularyCard（BR-SAVE）。只用 Mock 仓库。
final class SaveVocabularyCardTests: XCTestCase {

    private static let cachedTranslation = "咖啡馆很早就开门了。一位好奇的学生一直在读书。🙂"

    // U10 · BR-SAVE-5/6/7/9 · happy
    @MainActor
    func test_collectingWord_savesSentenceContextAndParagraphTranslation() async throws {
        let library = makeLibrary()
        let vocabulary = MockVocabularyRepository()
        let widget = MockWidgetSnapshotPublisher()
        let save = SaveVocabularyCard(books: library.books, vocabulary: vocabulary, widget: widget, now: { Fixtures.fixedDate })

        let result = try await save.execute(selection(in: library.paragraph, location: 25, length: 7))

        XCTAssertTrue(result.wasCreated)
        let card = result.card
        XCTAssertEqual(card.selectedText, "curious")
        XCTAssertEqual(card.selectionLocation, 25)
        XCTAssertEqual(card.selectionLength, 7)
        // 语境 = 选区所在的句子，不是整段
        XCTAssertTrue(card.contextText.hasPrefix("A curious student kept reading."), "实际语境：\(card.contextText)")
        XCTAssertFalse(card.contextText.contains("café"), "前一句不应进入语境")
        XCTAssertEqual(card.contextText, SaveVocabularyCard.contextSentence(in: library.paragraph.text, location: 25, length: 7))
        // 收藏时该段已缓存的整段译文
        XCTAssertEqual(card.contextTranslation, Self.cachedTranslation)
        // 来源快照
        XCTAssertEqual(card.sourceBookID, library.book.id)
        XCTAssertEqual(card.sourceBookTitle, "My English Story")
        XCTAssertEqual(card.sourceParagraphID, library.paragraph.id)
        XCTAssertEqual(card.sourceParagraphOrder, 1)
        // 新卡：机器提示待生成，没有个人理解
        XCTAssertEqual(card.hintStatus, .pending)
        XCTAssertNil(card.machineHint)
        XCTAssertNil(card.userMeaningOverride)
        XCTAssertEqual(card.createdAt, Fixtures.fixedDate)
        XCTAssertEqual(vocabulary.insertedDrafts.count, 1)
        XCTAssertEqual(widget.publishCount, 1, "新增词卡后发布一次（P4）")
    }

    // U11 · BR-SAVE-3/4 · 领域规则
    @MainActor
    func test_collectingSameSelectionTwice_returnsExistingCardWithoutDuplicate() async throws {
        let library = makeLibrary()
        let vocabulary = MockVocabularyRepository()
        let widget = MockWidgetSnapshotPublisher()
        let save = SaveVocabularyCard(books: library.books, vocabulary: vocabulary, widget: widget, now: { Fixtures.fixedDate })

        let first = try await save.execute(selection(in: library.paragraph, location: 25, length: 7))
        // 第二次多选了前面的空格：" curious"，去空白后仍是 {25, 7}
        let secondSelection = selection(in: library.paragraph, location: 24, length: 8)
        XCTAssertEqual(secondSelection.selectedText, " curious")
        let second = try await save.execute(secondSelection)

        XCTAssertTrue(first.wasCreated)
        XCTAssertFalse(second.wasCreated, "同一段同一范围只保存一张词卡")
        XCTAssertEqual(second.card.id, first.card.id, "返回已有词卡，阅读页据此显示 “Already saved · View Word Card”")
        XCTAssertEqual(vocabulary.insertedDrafts.count, 1)
        XCTAssertEqual(vocabulary.storedCards.count, 1)
        XCTAssertEqual(widget.publishCount, 1, "重复收藏不发布")
    }

    // U12 · BR-SAVE-3 · 边界（201 拒绝、200 允许）
    @MainActor
    func test_collectingSelectionLongerThan200Characters_isRejected() async throws {
        let book = Fixtures.book()
        let longParagraph = Fixtures.paragraph(bookID: book.id, order: 0, text: String(repeating: "x", count: 250))
        let books = MockBookRepository()
        books.storedBooks = [book]
        books.storedParagraphs = [book.id: [longParagraph]]
        let vocabulary = MockVocabularyRepository()
        let widget = MockWidgetSnapshotPublisher()
        let save = SaveVocabularyCard(books: books, vocabulary: vocabulary, widget: widget, now: { Fixtures.fixedDate })

        do {
            _ = try await save.execute(selection(in: longParagraph, location: 0, length: 201))
            XCTFail("201 个字符的选区应被拒绝")
        } catch let error as SaveVocabularyCardError {
            XCTAssertEqual(error, .selectionTooLong)
            XCTAssertEqual(error.message, AppText.E.saveSelectionTooLong)
        }
        XCTAssertTrue(vocabulary.insertedDrafts.isEmpty)
        XCTAssertEqual(widget.publishCount, 0)

        let accepted = try await save.execute(selection(in: longParagraph, location: 0, length: 200))
        XCTAssertTrue(accepted.wasCreated)
        XCTAssertEqual(accepted.card.selectedText.count, 200)
        XCTAssertEqual(widget.publishCount, 1)
    }

    // U21 · BR-SAVE-1/2/3 · 领域错误
    @MainActor
    func test_collectingFromRemovedParagraph_reportsSourceGone_andInvalidSelectionsAreRejected() async throws {
        let library = makeLibrary()
        let vocabulary = MockVocabularyRepository()
        let widget = MockWidgetSnapshotPublisher()
        let save = SaveVocabularyCard(books: library.books, vocabulary: vocabulary, widget: widget, now: { Fixtures.fixedDate })
        let curious = selection(in: library.paragraph, location: 25, length: 7)

        // 1. 收藏时原段已经不在数据库里（书刚被移出书库）
        let paragraphs = library.books.storedParagraphs
        library.books.storedParagraphs = [:]
        do {
            _ = try await save.execute(curious)
            XCTFail("原段不存在时应报原文已移出")
        } catch let error as SaveVocabularyCardError {
            XCTAssertEqual(error, .sourceGone)
            XCTAssertEqual(error.message, AppText.E.saveSourceGone)
        }
        library.books.storedParagraphs = paragraphs

        // 2. 写入词卡的瞬间段被删除（仓库报 paragraphNotFound）：同样是原文已移出
        vocabulary.missingParagraphIDs = [library.paragraph.id]
        do {
            _ = try await save.execute(curious)
            XCTFail("写入时段被删除应报原文已移出")
        } catch let error as SaveVocabularyCardError {
            XCTAssertEqual(error, .sourceGone)
        }
        vocabulary.missingParagraphIDs = []

        // 3. 只选中了空格：拒绝
        let blank = selection(in: library.paragraph, location: 24, length: 1)
        XCTAssertEqual(blank.selectedText, " ")
        do {
            _ = try await save.execute(blank)
            XCTFail("只有空白的选区应被拒绝")
        } catch let error as SaveVocabularyCardError {
            XCTAssertEqual(error, .emptySelection)
            XCTAssertEqual(error.message, AppText.E.saveEmptySelection)
        }

        // 4. 选区文字与原文对不上（原文已变化）：拒绝
        let mismatched = ParagraphSelection(
            bookID: library.book.id,
            paragraphID: library.paragraph.id,
            paragraphOrder: library.paragraph.order,
            location: 25,
            length: 7,
            selectedText: "furious"
        )
        do {
            _ = try await save.execute(mismatched)
            XCTFail("与原文对不上的选区应被拒绝")
        } catch let error as SaveVocabularyCardError {
            XCTAssertEqual(error, .selectionMismatch)
            XCTAssertEqual(error.message, AppText.E.saveSelectionMismatch)
        }

        XCTAssertTrue(vocabulary.insertedDrafts.isEmpty, "以上情况都不写库")
        XCTAssertEqual(widget.publishCount, 0, "以上情况都不发布")
    }

    // MARK: 辅助

    /// 一本书 + 两段：order 0 是标题，order 1 是 curious 所在段（带有效译文缓存）。
    @MainActor
    private func makeLibrary() -> (books: MockBookRepository, book: Book, paragraph: ReadingParagraph) {
        let book = Fixtures.book()
        let heading = Fixtures.paragraph(bookID: book.id, order: 0, text: "Prologue")
        let paragraph = Fixtures.paragraph(
            bookID: book.id,
            order: 1,
            text: TXTSamples.curiousParagraph,
            translatedText: Self.cachedTranslation
        )
        let books = MockBookRepository()
        books.storedBooks = [book]
        books.storedParagraphs = [book.id: [heading, paragraph]]
        return (books, book, paragraph)
    }

    /// 模拟阅读页交给 Use Case 的原始选区（未去空白）。
    private func selection(in paragraph: ReadingParagraph, location: Int, length: Int) -> ParagraphSelection {
        let text = (paragraph.text as NSString).substring(with: NSRange(location: location, length: length))
        return ParagraphSelection(
            bookID: paragraph.bookID,
            paragraphID: paragraph.id,
            paragraphOrder: paragraph.order,
            location: location,
            length: length,
            selectedText: text
        )
    }
}
