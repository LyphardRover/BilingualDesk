// File: BilingualDeskTests/UseCases/ImportTXTBookTests.swift
// Targets: Tests
import Foundation
import XCTest
@testable import BilingualDesk

/// U01–U04：ImportTXTBook（BR-IMPORT）。只用 Mock 仓库；解析用真实 FoundationTXTParser（纯值）或文件内的解析器桩。
final class ImportTXTBookTests: XCTestCase {

    // U01 · BR-IMPORT-12/13/14 · happy
    @MainActor
    func test_importingNewTXT_savesBookWithAllParagraphs_andPublishesWidget() async throws {
        let books = MockBookRepository()
        let widget = MockWidgetSnapshotPublisher()
        let importBook = makeImportTXTBook(books: books, widget: widget)
        let candidate = ImportCandidate(fileName: "BilingualDeskSample.TXT", data: TXTSamples.utf8, origin: .filePicker)

        let preview = try await importBook.preview(candidate, splitRule: .blankLine)
        XCTAssertEqual(preview.defaultTitle, "BilingualDeskSample", "默认书名应去掉 .txt（不分大小写）")
        XCTAssertEqual(preview.parsed.paragraphs.count, 8)
        XCTAssertEqual(preview.previewParagraphs.count, 5, "预览只给前 5 段")

        let outcome = try await importBook.execute(preview, title: "  My English Story \n")

        guard case let .imported(book) = outcome else {
            return XCTFail("新 TXT 应该入库，实际结果：\(outcome)")
        }
        XCTAssertEqual(book.title, "My English Story", "书名应去掉首尾空白")
        XCTAssertEqual(book.paragraphCount, 8)
        XCTAssertEqual(book.readingParagraphOrder, 0)
        XCTAssertNil(book.lastOpenedAt)
        XCTAssertEqual(books.insertedRecords.count, 1)
        let record = try XCTUnwrap(books.insertedRecords.first)
        XCTAssertEqual(record.importedAt, Fixtures.fixedDate)
        XCTAssertEqual(record.paragraphs.map(\.order), Array(0..<8), "段序号从 0 连续编号")
        XCTAssertEqual(record.paragraphs[1].text, TXTSamples.curiousParagraph, "入库保存完整段落")
        let storedParagraphs = try await books.paragraphs(bookID: book.id)
        XCTAssertEqual(storedParagraphs.count, 8)
        XCTAssertEqual(widget.publishCount, 1, "导入成功后发布一次 Widget 快照（P2）")
    }

    // U02 · BR-IMPORT-9/13 · 领域错误路径
    @MainActor
    func test_importingSameTXTTwice_returnsBookAlreadyInLibrary_withoutSecondInsert() async throws {
        let books = MockBookRepository()
        let widget = MockWidgetSnapshotPublisher()
        let importBook = makeImportTXTBook(books: books, widget: widget)

        let firstCandidate = ImportCandidate(fileName: "BilingualDeskSample.txt", data: TXTSamples.utf8, origin: .filePicker)
        let firstPreview = try await importBook.preview(firstCandidate, splitRule: .blankLine)
        XCTAssertEqual(firstPreview.parsed.contentHash, TextFingerprint.sha256Hex(TXTSamples.utf8), "contentHash 是原始字节的 SHA-256")
        let first = try await importBook.execute(firstPreview, title: "My English Story")

        // 同样的字节，换文件名、换来源、换分段规则、换书名：仍是同一本书
        let secondCandidate = ImportCandidate(fileName: "Copy of story.txt", data: TXTSamples.utf8, origin: .shareInbox(itemID: UUID()))
        let secondPreview = try await importBook.preview(secondCandidate, splitRule: .eachLine)
        let second = try await importBook.execute(secondPreview, title: "Another Title")

        XCTAssertEqual(second, .alreadyInLibrary(first.book))
        XCTAssertEqual(books.insertedRecords.count, 1, "重复的 TXT 不再写库")
        XCTAssertEqual(books.storedBooks.count, 1)
        XCTAssertEqual(widget.publishCount, 1, "重复导入不发布")
    }

    // U03 · BR-IMPORT-1 · 边界（10,000,001 字节拒绝，10,000,000 字节允许）
    @MainActor
    func test_previewingFileLargerThan10MB_isRejectedAsTooLarge() async throws {
        let books = MockBookRepository()
        let widget = MockWidgetSnapshotPublisher()

        // 解析器桩总是报「不是纯文本」：如果先解析再查大小，这里会收到 notPlainText 而不是 fileTooLarge
        let rejecting = makeImportTXTBook(books: books, widget: widget, parser: AlwaysNotPlainTextParser())
        let tooLarge = ImportCandidate(fileName: "huge.txt", data: Data(count: 10_000_001), origin: .filePicker)
        do {
            _ = try await rejecting.preview(tooLarge, splitRule: .blankLine)
            XCTFail("10,000,001 字节的 TXT 应被拒绝")
        } catch let error as ImportTXTBookError {
            XCTAssertEqual(error, .fileTooLarge)
            XCTAssertEqual(error.message, AppText.E.importTooLarge)
        }

        // 恰好 10,000,000 字节：允许，交给解析器
        let accepting = makeImportTXTBook(books: books, widget: widget, parser: FixedResultParser(result: Self.oneParagraphBook))
        let atLimit = ImportCandidate(fileName: "limit.txt", data: Data(count: 10_000_000), origin: .filePicker)
        let preview = try await accepting.preview(atLimit, splitRule: .blankLine)
        XCTAssertEqual(preview.candidate.data.count, 10_000_000)
        XCTAssertEqual(preview.parsed, Self.oneParagraphBook)
        XCTAssertTrue(books.insertedRecords.isEmpty, "预览不写库")
        XCTAssertEqual(widget.publishCount, 0)
    }

    // U04 · BR-IMPORT-10 · 边界（按 Character 计数：121 拒绝、120 允许）
    @MainActor
    func test_bookTitleOf121Characters_isRejected_and120CharactersIsAccepted() async throws {
        // 119 个汉字 + 1 个由 4 个标量组成的 emoji = 120 个 Character（UTF-16 长度是 126）
        let exactly120 = String(repeating: "书", count: 119) + "\u{1F469}\u{1F3FD}\u{200D}\u{1F4BB}"
        XCTAssertEqual(exactly120.count, 120)
        let exactly121 = exactly120 + "a"

        XCTAssertEqual(try ImportTXTBook.validatedTitle("  \(exactly120)\n"), exactly120, "去首尾空白后 120 个字符合法")
        XCTAssertThrowsError(try ImportTXTBook.validatedTitle(exactly121)) { error in
            XCTAssertEqual(error as? ImportTXTBookError, .titleTooLong)
        }
        XCTAssertThrowsError(try ImportTXTBook.validatedTitle(" \n\t ")) { error in
            XCTAssertEqual(error as? ImportTXTBookError, .titleEmpty)
        }

        // execute 用同一条规则：121 个字符不写库、不发布
        let books = MockBookRepository()
        let widget = MockWidgetSnapshotPublisher()
        let importBook = makeImportTXTBook(books: books, widget: widget)
        let candidate = ImportCandidate(fileName: "BilingualDeskSample.txt", data: TXTSamples.utf8, origin: .filePicker)
        let preview = try await importBook.preview(candidate, splitRule: .blankLine)
        do {
            _ = try await importBook.execute(preview, title: exactly121)
            XCTFail("121 个字符的书名应被拒绝")
        } catch let error as ImportTXTBookError {
            XCTAssertEqual(error, .titleTooLong)
            XCTAssertEqual(error.message, AppText.E.importTitleTooLong)
        }
        XCTAssertTrue(books.insertedRecords.isEmpty)
        XCTAssertEqual(widget.publishCount, 0)

        let outcome = try await importBook.execute(preview, title: exactly120)
        XCTAssertEqual(outcome.book.title, exactly120)

        // 默认书名：截到前 120 个字符；去掉 .txt 后为空时用 “Untitled TXT”（T-IMPORT-DEFAULT-TITLE）
        let longFileName = String(repeating: "a", count: 130) + ".txt"
        XCTAssertEqual(ImportTXTBook.defaultTitle(forFileName: longFileName), String(repeating: "a", count: 120))
        XCTAssertEqual(ImportTXTBook.defaultTitle(forFileName: " .txt"), AppText.T.importDefaultTitle)
    }

    // MARK: 辅助

    @MainActor
    private func makeImportTXTBook(
        books: MockBookRepository,
        widget: MockWidgetSnapshotPublisher,
        parser: any TXTParsing = FoundationTXTParser()
    ) -> ImportTXTBook {
        ImportTXTBook(books: books, parser: parser, widget: widget, now: { Fixtures.fixedDate })
    }

    private static let oneParagraphBook = ParsedBook(
        contentHash: "fixed-hash",
        encodingName: "UTF-8",
        splitRule: .blankLine,
        paragraphs: [
            ParsedParagraph(
                order: 0,
                text: "Hello.",
                sourceHash: TextFingerprint.sha256Hex("Hello."),
                chapterIndex: 0,
                chapterTitle: nil,
                isChapterHeading: false
            )
        ]
    )
}

/// 解析器桩：总是抛 notPlainText。
private struct AlwaysNotPlainTextParser: TXTParsing {
    func parse(_ data: Data, splitRule: ParagraphSplitRule) throws -> ParsedBook {
        throw TXTParseError.notPlainText
    }
}

/// 解析器桩：不看字节，直接返回固定结果。
private struct FixedResultParser: TXTParsing {
    let result: ParsedBook

    func parse(_ data: Data, splitRule: ParagraphSplitRule) throws -> ParsedBook {
        result
    }
}
