// File: BilingualDeskTests/Integration/CoreDataIntegrationTests.swift
// Targets: Tests
import Foundation
import XCTest
@testable import BilingualDesk

/// 集成测试（I01–I03）：内存 Core Data + 真实仓库，不用 Mock。
/// 本文件不 import CoreData（02 L5），只通过 BookRepository / VocabularyRepository 观察结果。
final class CoreDataIntegrationTests: XCTestCase {

    // I01 · 02 §6 insertCard、§4.4「待补中文」谓词
    @MainActor
    func test_coreData_savedCardKeepsDraftSnapshot_andAppearsInNeedsChineseFilter() async throws {
        let store = try await makeStoreWithSampleBook()
        let maybeParagraph = try await store.books.paragraph(bookID: store.record.id, order: 1)
        let paragraph = try XCTUnwrap(maybeParagraph)
        XCTAssertEqual(paragraph.text, TXTSamples.curiousParagraph)
        // 书名和译文故意与数据库里的不同：仓库必须原样保存 draft，不能重读书名或段落缓存
        let draft = curiousDraft(bookID: store.record.id, paragraph: paragraph)

        let inserted = try await store.vocabulary.insertCard(draft, at: Fixtures.fixedDate)
        let maybeStored = try await store.vocabulary.card(id: inserted.id)
        let stored = try XCTUnwrap(maybeStored)

        XCTAssertEqual(stored, inserted)
        XCTAssertEqual(stored.selectedText, draft.selectedText)
        XCTAssertEqual(stored.selectionLocation, 25)
        XCTAssertEqual(stored.selectionLength, 7)
        XCTAssertEqual(stored.contextText, draft.contextText)
        XCTAssertEqual(stored.contextTranslation, "快照译文")
        XCTAssertEqual(stored.sourceBookTitle, "快照书名")
        XCTAssertEqual(stored.sourceBookID, store.record.id)
        XCTAssertEqual(stored.sourceParagraphID, paragraph.id)
        XCTAssertEqual(stored.sourceParagraphOrder, 1)
        XCTAssertTrue(stored.isSourceAvailable)
        XCTAssertEqual(stored.hintStatus, .pending)
        XCTAssertNil(stored.machineHint)
        XCTAssertNil(stored.userMeaningOverride)
        XCTAssertEqual(stored.createdAt, Fixtures.fixedDate)
        XCTAssertEqual(stored.updatedAt, Fixtures.fixedDate)

        // 1. 新卡（pending、没有个人理解）：在「待补中文」里；搜索忽略大小写
        var needsChinese = try await store.vocabulary.cards(matching: "CURIOUS", needsChineseOnly: true)
        XCTAssertEqual(needsChinese.map(\.id), [inserted.id])
        var count = try await store.vocabulary.countCardsNeedingChinese()
        XCTAssertEqual(count, 1)

        // 2. 已留空（""）：不再待补中文，但仍在单词本里
        _ = try await store.vocabulary.saveUserMeaning(cardID: inserted.id, meaning: "", at: Fixtures.fixedDate)
        needsChinese = try await store.vocabulary.cards(matching: "", needsChineseOnly: true)
        XCTAssertTrue(needsChinese.isEmpty)
        count = try await store.vocabulary.countCardsNeedingChinese()
        XCTAssertEqual(count, 0)
        let all = try await store.vocabulary.cards(matching: "", needsChineseOnly: false)
        XCTAssertEqual(all.map(\.id), [inserted.id])

        // 3. 清除个人理解 + 提示失败：回到待补中文
        _ = try await store.vocabulary.saveUserMeaning(cardID: inserted.id, meaning: nil, at: Fixtures.fixedDate)
        let failed = try await store.vocabulary.markMachineHintFailed(cardID: inserted.id, at: Fixtures.fixedDate)
        XCTAssertEqual(failed?.hintStatus, .failed)
        needsChinese = try await store.vocabulary.cards(matching: "", needsChineseOnly: true)
        XCTAssertEqual(needsChinese.map(\.id), [inserted.id])

        // 4. 机器提示已生成：不再待补中文，含义显示机器提示
        let ready = try await store.vocabulary.saveMachineHint(cardID: inserted.id, hint: "好奇的", at: Fixtures.fixedDate)
        XCTAssertEqual(ready?.meaning, .machine("好奇的"))
        needsChinese = try await store.vocabulary.cards(matching: "", needsChineseOnly: true)
        XCTAssertTrue(needsChinese.isEmpty)
        count = try await store.vocabulary.countCardsNeedingChinese()
        XCTAssertEqual(count, 0)
    }

    // I02 · 02 §4.3 删除规则（Book→paragraphs Cascade，→cards Nullify）
    @MainActor
    func test_coreData_removingBook_deletesParagraphs_butKeepsCardsWithSnapshot() async throws {
        let store = try await makeStoreWithSampleBook()
        let maybeParagraph = try await store.books.paragraph(bookID: store.record.id, order: 1)
        let paragraph = try XCTUnwrap(maybeParagraph)
        let card = try await store.vocabulary.insertCard(curiousDraft(bookID: store.record.id, paragraph: paragraph), at: Fixtures.fixedDate)

        // ReadingParagraph.book 是必填关系：如果 Book→paragraphs 不是 Cascade，留下的段会让 save() 校验失败，deleteBook 会抛错
        try await store.books.deleteBook(id: store.record.id)

        let deletedBook = try await store.books.book(id: store.record.id)
        XCTAssertNil(deletedBook)
        let byHash = try await store.books.book(contentHash: store.record.contentHash)
        XCTAssertNil(byHash)
        let paragraphs = try await store.books.paragraphs(bookID: store.record.id)
        XCTAssertTrue(paragraphs.isEmpty)
        let oldParagraph = try await store.books.paragraph(bookID: store.record.id, order: 1)
        XCTAssertNil(oldParagraph)

        // 词卡保留，关系置空，快照字段原样。
        // 这张卡由 insertCard 在主 context 里创建、已加载；deleteBook 返回前已把删除合并进主 context（02 §6），所以这里立即读到关系为 nil
        let maybeKept = try await store.vocabulary.card(id: card.id)
        let kept = try XCTUnwrap(maybeKept)
        XCTAssertNil(kept.sourceParagraphID, "段已删除，关系置空")
        XCTAssertFalse(kept.isSourceAvailable, "详情页据此显示 T-CARD-SOURCE-GONE（“The book was removed from your Library; …”）")
        XCTAssertEqual(kept.sourceBookID, store.record.id, "来源书 ID 快照保留")
        XCTAssertEqual(kept.sourceBookTitle, "快照书名")
        XCTAssertEqual(kept.sourceParagraphOrder, 1)
        XCTAssertEqual(kept.contextText, card.contextText)
        XCTAssertEqual(kept.contextTranslation, "快照译文")
        let latest = try await store.vocabulary.latestCard()
        XCTAssertEqual(latest?.id, card.id)

        // 书已删除，同一 contentHash 的 Book 不再存在（模型没有唯一约束，查重靠 insertBook 先查询，02 §4.1）：同一个 TXT 可以重新导入成一本新书；旧词卡不会被自动接回新段
        let reimported = try await store.books.insertBook(try Self.sampleRecord())
        XCTAssertEqual(reimported.paragraphCount, 8)
        let afterReimport = try await store.vocabulary.card(id: card.id)
        XCTAssertNil(afterReimport?.sourceParagraphID)
    }

    // I03 · 02 §6 saveMachineHint / markMachineHintFailed · BR-HINT-5：机器提示不改个人理解
    @MainActor
    func test_coreData_machineHintDoesNotEraseExistingPersonalMeaning() async throws {
        let store = try await makeStoreWithSampleBook()
        let maybeParagraph = try await store.books.paragraph(bookID: store.record.id, order: 1)
        let paragraph = try XCTUnwrap(maybeParagraph)
        let card = try await store.vocabulary.insertCard(curiousDraft(bookID: store.record.id, paragraph: paragraph), at: Fixtures.fixedDate)
        _ = try await store.vocabulary.saveUserMeaning(cardID: card.id, meaning: "充满好奇心的", at: Fixtures.fixedDate)

        // 提示失败：只改提示状态，个人理解保留
        let failed = try await store.vocabulary.markMachineHintFailed(cardID: card.id, at: Fixtures.fixedDate)
        XCTAssertEqual(failed?.hintStatus, .failed)
        XCTAssertEqual(failed?.userMeaningOverride, "充满好奇心的")

        // 提示生成：写入提示，个人理解仍保留，单词本继续显示个人理解
        let ready = try await store.vocabulary.saveMachineHint(cardID: card.id, hint: "好奇的", at: Fixtures.fixedDate)
        XCTAssertEqual(ready?.machineHint, "好奇的")
        XCTAssertEqual(ready?.hintStatus, .ready)
        XCTAssertEqual(ready?.userMeaningOverride, "充满好奇心的")
        XCTAssertEqual(ready?.meaning, .personal("充满好奇心的"))

        // 从数据库重新读出，确认已经保存
        let reloaded = try await store.vocabulary.card(id: card.id)
        XCTAssertEqual(reloaded?.userMeaningOverride, "充满好奇心的")
        XCTAssertEqual(reloaded?.machineHint, "好奇的")
        let count = try await store.vocabulary.countCardsNeedingChinese()
        XCTAssertEqual(count, 0)

        // 词卡删除后，迟到的提示返回 nil，不报错（BR-HINT-1）
        try await store.vocabulary.deleteCard(id: card.id)
        let late = try await store.vocabulary.saveMachineHint(cardID: card.id, hint: "好奇的", at: Fixtures.fixedDate)
        XCTAssertNil(late)
    }

    // MARK: 辅助

    private struct Store {
        let stack: CoreDataStack
        let books: CoreDataBookRepository
        let vocabulary: CoreDataVocabularyRepository
        let record: NewBookRecord
    }

    /// 每个测试一个全新的内存库，并导入固定样本（8 段）。
    @MainActor
    private func makeStoreWithSampleBook() async throws -> Store {
        let stack = try await CoreDataStack.load(inMemory: true)
        let books = CoreDataBookRepository(stack: stack)
        let vocabulary = CoreDataVocabularyRepository(stack: stack)
        let record = try Self.sampleRecord()
        let book = try await books.insertBook(record)
        XCTAssertEqual(book.paragraphCount, 8)
        return Store(stack: stack, books: books, vocabulary: vocabulary, record: record)
    }

    private static func sampleRecord() throws -> NewBookRecord {
        let parsed = try FoundationTXTParser().parse(TXTSamples.utf8, splitRule: .blankLine)
        return NewBookRecord(
            id: UUID(),
            title: "My English Story",
            importedAt: Fixtures.fixedDate,
            contentHash: parsed.contentHash,
            encodingName: parsed.encodingName,
            splitRule: parsed.splitRule,
            paragraphs: parsed.paragraphs
        )
    }

    private func curiousDraft(bookID: UUID, paragraph: ReadingParagraph) -> VocabularyCardDraft {
        VocabularyCardDraft(
            selectedText: "curious",
            selectionLocation: TXTSamples.curiousRange.location,
            selectionLength: TXTSamples.curiousRange.length,
            contextText: "A curious student kept reading.",
            contextTranslation: "快照译文",
            sourceBookID: bookID,
            sourceBookTitle: "快照书名",
            sourceParagraphID: paragraph.id,
            sourceParagraphOrder: paragraph.order
        )
    }
}
