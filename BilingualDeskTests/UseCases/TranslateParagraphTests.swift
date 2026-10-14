// File: BilingualDeskTests/UseCases/TranslateParagraphTests.swift
// Targets: Tests
import Foundation
import XCTest
@testable import BilingualDesk

/// U15–U16：TranslateParagraph（BR-TR）。只用 Mock 仓库与 Mock 翻译。
final class TranslateParagraphTests: XCTestCase {

    // U15 · BR-TR-1/5 · happy
    @MainActor
    func test_translatingParagraphWithValidCache_doesNotCallTranslator() async throws {
        let bookID = UUID()
        let cached = Fixtures.paragraph(bookID: bookID, order: 1, text: TXTSamples.curiousParagraph, translatedText: "缓存译文")
        let stale = ReadingParagraph(
            id: UUID(),
            bookID: bookID,
            order: 4,
            text: "The rain stopped.",
            sourceHash: TextFingerprint.sha256Hex("The rain stopped."),
            chapterIndex: 2,
            chapterTitle: "Chapter 1",
            isChapterHeading: false,
            translatedText: "旧译文",
            translatedSourceHash: "hash-of-an-older-text"
        )
        XCTAssertNil(stale.validTranslation, "hash 对不上的缓存无效")
        let books = MockBookRepository()
        books.storedParagraphs = [bookID: [cached, stale]]
        let translator = MockTranslationProvider()
        // 故意设成模拟器：如果 Use Case 先查可用性，就会报错而不是返回缓存
        translator.availabilityToReturn = .simulatorUnsupported
        let translate = TranslateParagraph(books: books, translator: translator)

        let fromCache = try await translate.execute(cached)
        XCTAssertEqual(fromCache, "缓存译文")
        XCTAssertTrue(translator.translatedTexts.isEmpty, "有效缓存不调用翻译")
        XCTAssertTrue(books.savedTranslations.isEmpty)

        // 无效缓存：重新翻译并按当前段 hash 写回
        translator.availabilityToReturn = .ready
        translator.resultToReturn = .success("雨停了。")
        let fresh = try await translate.execute(stale)
        XCTAssertEqual(fresh, "雨停了。")
        XCTAssertEqual(translator.translatedTexts, ["The rain stopped."])
        XCTAssertEqual(books.savedTranslations.count, 1)
        XCTAssertEqual(books.savedTranslations.first?.paragraphID, stale.id)
        XCTAssertEqual(books.savedTranslations.first?.sourceHash, stale.sourceHash)
    }

    // U16 · BR-TR-2/4 · 领域错误
    @MainActor
    func test_translatingWithoutDownloadedLanguage_reportsLanguageNotPrepared() async throws {
        let paragraph = Fixtures.paragraph(bookID: UUID(), order: 1, text: TXTSamples.curiousParagraph)
        let books = MockBookRepository()
        books.storedParagraphs = [paragraph.bookID: [paragraph]]
        let translator = MockTranslationProvider()
        translator.availabilityToReturn = .needsDownload
        let translate = TranslateParagraph(books: books, translator: translator)

        do {
            _ = try await translate.execute(paragraph)
            XCTFail("没下载语言时应报需准备语言")
        } catch let error as TranslateParagraphError {
            XCTAssertEqual(error, .languageNotPrepared)
            XCTAssertEqual(error.message, AppText.E.trNeedsLanguage)
        }
        XCTAssertTrue(translator.translatedTexts.isEmpty, "可用性不满足时不发起翻译")

        // 可用性显示已安装，但翻译时系统报「未安装」：同样是需准备语言
        translator.availabilityToReturn = .ready
        translator.resultToReturn = .failure(.notInstalled)
        do {
            _ = try await translate.execute(paragraph)
            XCTFail("翻译报 notInstalled 时应报需准备语言")
        } catch let error as TranslateParagraphError {
            XCTAssertEqual(error, .languageNotPrepared)
        }
        XCTAssertEqual(translator.translatedTexts, [paragraph.text])
        XCTAssertTrue(books.savedTranslations.isEmpty, "失败不写缓存")
    }

    // U22 · BR-TR-2/4 · 领域错误
    @MainActor
    func test_emptyOrFailedTranslation_isReportedAsFailed_andNothingIsCached() async throws {
        let paragraph = Fixtures.paragraph(bookID: UUID(), order: 1, text: TXTSamples.curiousParagraph)
        let books = MockBookRepository()
        books.storedParagraphs = [paragraph.bookID: [paragraph]]
        let translator = MockTranslationProvider()
        let translate = TranslateParagraph(books: books, translator: translator)

        // 1. 翻译只返回空白：算翻译失败
        translator.resultToReturn = .success(" \n ")
        do {
            _ = try await translate.execute(paragraph)
            XCTFail("空白译文应按翻译失败处理")
        } catch let error as TranslateParagraphError {
            XCTAssertEqual(error, .translationFailed)
            XCTAssertEqual(error.message, AppText.E.trFailed)
        }

        // 2. 系统翻译报错：算翻译失败
        translator.resultToReturn = .failure(.failed)
        do {
            _ = try await translate.execute(paragraph)
            XCTFail("系统翻译失败应报翻译失败")
        } catch let error as TranslateParagraphError {
            XCTAssertEqual(error, .translationFailed)
        }

        // 3. 在模拟器上：直接报模拟器不支持系统翻译，不发起翻译
        translator.availabilityToReturn = .simulatorUnsupported
        do {
            _ = try await translate.execute(paragraph)
            XCTFail("模拟器上应报不支持系统翻译")
        } catch let error as TranslateParagraphError {
            XCTAssertEqual(error, .simulatorUnsupported)
            XCTAssertEqual(error.message, AppText.E.trSimulator)
        }

        XCTAssertEqual(translator.translatedTexts.count, 2, "只有前两次真正发起了翻译")
        XCTAssertTrue(books.savedTranslations.isEmpty, "失败时不写缓存")
    }
}
