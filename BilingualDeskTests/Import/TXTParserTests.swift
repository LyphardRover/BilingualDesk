// File: BilingualDeskTests/Import/TXTParserTests.swift
// Targets: Tests
import Foundation
import XCTest
@testable import BilingualDesk

/// U05–U09：FoundationTXTParser（BR-IMPORT-3/5/7/8/12）。纯值测试，不涉及数据库。
final class TXTParserTests: XCTestCase {

    // U05 · BR-IMPORT-7/8/12 · happy
    @MainActor
    func test_parsingSampleWithBlankLineRule_gives8ParagraphsAnd3Chapters() async throws {
        let parsed = try FoundationTXTParser().parse(TXTSamples.utf8, splitRule: .blankLine)

        XCTAssertEqual(parsed.paragraphs.count, 8)
        XCTAssertEqual(parsed.chapterCount, 3)
        XCTAssertEqual(parsed.encodingName, "UTF-8")
        XCTAssertEqual(parsed.splitRule, .blankLine)
        XCTAssertEqual(parsed.paragraphs.map(\.order), Array(0..<8))

        let headings = parsed.paragraphs.filter(\.isChapterHeading)
        XCTAssertEqual(headings.map(\.text), ["Prologue", "Chapter 1", "Chapter 2"])
        XCTAssertEqual(headings.map(\.order), [0, 3, 6])

        // 连续的非空行用一个空格连成一段
        XCTAssertEqual(parsed.paragraphs[2].text, "She wrote \"curious\" in her notebook. The next line belongs to the same paragraph.")

        // 章节归属：标题段自身取新的 chapterIndex
        XCTAssertEqual(parsed.paragraphs[1].chapterIndex, 1)
        XCTAssertEqual(parsed.paragraphs[1].chapterTitle, "Prologue")
        XCTAssertEqual(parsed.paragraphs[3].chapterIndex, 2)
        XCTAssertEqual(parsed.paragraphs[7].chapterIndex, 3)
        XCTAssertEqual(parsed.paragraphs[7].chapterTitle, "Chapter 2")

        // 两段相同的文字仍是两段，各自的 sourceHash 都是段文字的 SHA-256
        XCTAssertEqual(parsed.paragraphs[4].text, "The rain stopped.")
        XCTAssertEqual(parsed.paragraphs[5].text, "The rain stopped.")
        XCTAssertEqual(parsed.paragraphs[4].sourceHash, TextFingerprint.sha256Hex("The rain stopped."))

        // curious 的 UTF-16 范围（café 的 é 是一个 UTF-16 单元）
        XCTAssertEqual(parsed.paragraphs[1].text, TXTSamples.curiousParagraph)
        XCTAssertEqual((parsed.paragraphs[1].text as NSString).range(of: "curious"), TXTSamples.curiousRange)

        // 同一份字节用 “Each Line”（`.eachLine`）：9 段
        let eachLine = try FoundationTXTParser().parse(TXTSamples.utf8, splitRule: .eachLine)
        XCTAssertEqual(eachLine.paragraphs.count, 9)
        XCTAssertEqual(eachLine.chapterCount, 3)
    }

    // U06 · BR-IMPORT-8 · 边界
    @MainActor
    func test_chapterHeadingRule_acceptsStandaloneTitles_andRejectsSentences() async throws {
        XCTAssertEqual(
            FoundationTXTParser.chapterHeadingPattern,
            #"^(?:(?i:chapter)\s+(?:[0-9]{1,4}|[IVXLCDM]{1,8})(?:\s*[:.\-–—](?:\s*\S.*)?)?|(?i:prologue|epilogue))$"#,
            "章节正则必须与 02 §8.1 逐字一致"
        )

        for heading in TXTSamples.acceptedHeadings {
            let parsed = try parseBetweenTwoLines(heading)
            XCTAssertEqual(parsed.chapterCount, 1, "应识别为章节标题：\(heading)")
            XCTAssertEqual(parsed.paragraphs.count, 3)
            XCTAssertEqual(parsed.paragraphs[1].text, heading)
            XCTAssertTrue(parsed.paragraphs[1].isChapterHeading)
        }
        for sentence in TXTSamples.rejectedHeadings {
            let parsed = try parseBetweenTwoLines(sentence)
            XCTAssertEqual(parsed.chapterCount, 0, "不应识别为章节标题：\(sentence)")
        }

        // 去空白后 ≤ 80 个字符才算标题
        let title80 = "Chapter 3: " + String(repeating: "A", count: 69)
        let title81 = title80 + "A"
        XCTAssertEqual(title80.count, 80)
        XCTAssertEqual(try parseBetweenTwoLines(title80).chapterCount, 1)
        XCTAssertEqual(try parseBetweenTwoLines(title81).chapterCount, 0)
    }

    // U07 · BR-IMPORT-3 · happy
    @MainActor
    func test_parsingUTF16LittleEndianWithBOM_givesSameParagraphsAsUTF8() async throws {
        let fromUTF8 = try FoundationTXTParser().parse(TXTSamples.utf8, splitRule: .blankLine)
        let fromUTF16 = try FoundationTXTParser().parse(TXTSamples.utf16LittleEndianWithBOM, splitRule: .blankLine)

        XCTAssertEqual(fromUTF16.encodingName, "UTF-16 LE (BOM)")
        XCTAssertEqual(fromUTF16.paragraphs, fromUTF8.paragraphs, "解码后的段落、章节与段 hash 完全相同")
        // contentHash 来自原始字节，所以两种编码的同一篇文字是两个不同的文件
        XCTAssertEqual(fromUTF16.contentHash, TextFingerprint.sha256Hex(TXTSamples.utf16LittleEndianWithBOM))
        XCTAssertNotEqual(fromUTF16.contentHash, fromUTF8.contentHash)
    }

    // U08 · BR-IMPORT-3 · 领域错误
    @MainActor
    func test_parsingInvalidUTF8_reportsUnknownEncoding() async throws {
        XCTAssertThrowsError(try FoundationTXTParser().parse(TXTSamples.invalidUTF8, splitRule: .blankLine)) { error in
            XCTAssertEqual(error as? TXTParseError, .unknownEncoding)
        }

        // 无 BOM 的 UTF-16：字节是合法 UTF-8，但解码后含 U+0000，同样是「无法识别编码」
        let utf16WithoutBOM = Data(TXTSamples.utf16LittleEndianWithBOM.dropFirst(2))
        XCTAssertThrowsError(try FoundationTXTParser().parse(utf16WithoutBOM, splitRule: .blankLine)) { error in
            XCTAssertEqual(error as? TXTParseError, .unknownEncoding)
        }

        // 经 ImportTXTBook 后变成面向读者的错误 E-IMPORT-UNKNOWN-ENCODING（“Couldn’t recognize the file’s text encoding. …”）
        let importBook = ImportTXTBook(
            books: MockBookRepository(),
            parser: FoundationTXTParser(),
            widget: MockWidgetSnapshotPublisher(),
            now: { Fixtures.fixedDate }
        )
        let candidate = ImportCandidate(fileName: "broken.txt", data: TXTSamples.invalidUTF8, origin: .filePicker)
        do {
            _ = try await importBook.preview(candidate, splitRule: .blankLine)
            XCTFail("非法 UTF-8 应报无法识别编码")
        } catch let error as ImportTXTBookError {
            XCTAssertEqual(error, .unknownEncoding)
            XCTAssertEqual(error.message, AppText.E.importUnknownEncoding)
        }
    }

    // U09 · BR-IMPORT-5 · 边界
    @MainActor
    func test_textWithEmojiZeroWidthJoiner_isAcceptedAsPlainText() async throws {
        let parsed = try FoundationTXTParser().parse(Data(TXTSamples.emojiWithZeroWidthJoiner.utf8), splitRule: .blankLine)
        XCTAssertEqual(parsed.paragraphs.map(\.text), [TXTSamples.emojiWithZeroWidthJoiner], "ZWJ 是 Cf 类，不算控制字符")

        // 控制字符（Cc，排除 \t \n \r）阈值是 max(2, 标量总数 / 100)：短文本里 2 个允许、3 个拒绝
        let twoControls = "Hello\u{0001}\u{0002} world"
        let threeControls = "Hello\u{0001}\u{0002}\u{0003} world"
        XCTAssertEqual(try FoundationTXTParser().parse(Data(twoControls.utf8), splitRule: .blankLine).paragraphs.count, 1)
        XCTAssertThrowsError(try FoundationTXTParser().parse(Data(threeControls.utf8), splitRule: .blankLine)) { error in
            XCTAssertEqual(error as? TXTParseError, .notPlainText)
        }
    }

    // MARK: 辅助

    /// 把一行放在两段正文之间，用 “Blank Lines”（`.blankLine`）解析。
    private func parseBetweenTwoLines(_ line: String) throws -> ParsedBook {
        let text = "Opening line.\n\n\(line)\n\nClosing line."
        return try FoundationTXTParser().parse(Data(text.utf8), splitRule: .blankLine)
    }
}
