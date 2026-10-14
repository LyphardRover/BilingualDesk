// File: BilingualDeskTests/UseCases/GenerateVocabularyHintTests.swift
// Targets: Tests
import Foundation
import XCTest
@testable import BilingualDesk

/// U13：GenerateVocabularyHint（BR-HINT）。只用 Mock 仓库与 Mock 翻译。
final class GenerateVocabularyHintTests: XCTestCase {

    // U13 · BR-HINT-3/5 · 领域规则
    @MainActor
    func test_lateMachineHint_isStoredButDoesNotOverwritePersonalMeaning() async throws {
        let original = Fixtures.card(hintStatus: .pending)
        let vocabulary = MockVocabularyRepository()
        vocabulary.storedCards = [original]
        let translator = MockTranslationProvider()
        translator.resultToReturn = .success("  好奇的 \n")
        translator.beforeReturning = {
            // 翻译还没返回时，读者在词卡详情里保存了自己的理解
            _ = try? await vocabulary.saveUserMeaning(cardID: original.id, meaning: "充满好奇心的", at: Fixtures.fixedDate)
        }
        let widget = MockWidgetSnapshotPublisher()
        let generate = GenerateVocabularyHint(vocabulary: vocabulary, translator: translator, widget: widget, now: { Fixtures.fixedDate })

        let returned = try await generate.execute(cardID: original.id)

        let card = try XCTUnwrap(returned)
        XCTAssertEqual(translator.translatedTexts, ["curious"], "机器提示 = 翻译所选文字")
        XCTAssertEqual(card.machineHint, "好奇的", "提示去掉首尾空白后保存")
        XCTAssertEqual(card.hintStatus, .ready)
        XCTAssertEqual(card.userMeaningOverride, "充满好奇心的", "迟到的提示不覆盖个人理解")
        XCTAssertEqual(card.meaning, .personal("充满好奇心的"), "单词本仍显示个人理解")
        XCTAssertFalse(card.needsChinese)

        let stored = try await vocabulary.card(id: original.id)
        XCTAssertEqual(stored?.userMeaningOverride, "充满好奇心的")
        XCTAssertEqual(stored?.machineHint, "好奇的")
        XCTAssertEqual(widget.publishCount, 1, "提示写入后发布一次（P6）")
    }

    // U19 · BR-HINT-1/2/4 · 领域错误
    @MainActor
    func test_failedMachineHint_marksCardFailed_andCardDeletedDuringTranslationIsDiscarded() async throws {
        let original = Fixtures.card(hintStatus: .pending)
        let vocabulary = MockVocabularyRepository()
        vocabulary.storedCards = [original]
        let translator = MockTranslationProvider()
        let widget = MockWidgetSnapshotPublisher()
        let generate = GenerateVocabularyHint(vocabulary: vocabulary, translator: translator, widget: widget, now: { Fixtures.fixedDate })

        // 1. 英中语言还没下载：不发起翻译；词卡记为提示失败并发布一次，报「需准备语言」
        translator.availabilityToReturn = .needsDownload
        do {
            _ = try await generate.execute(cardID: original.id)
            XCTFail("没下载语言时应报需准备语言")
        } catch let error as GenerateVocabularyHintError {
            XCTAssertEqual(error, .languageNotPrepared)
            XCTAssertEqual(error.message, AppText.E.hintNeedsLanguage)
        }
        XCTAssertTrue(translator.translatedTexts.isEmpty, "可用性不满足时不发起翻译")
        var stored = try await vocabulary.card(id: original.id)
        XCTAssertEqual(stored?.hintStatus, .failed)
        XCTAssertEqual(stored?.needsChinese, true, "提示失败、没有个人理解：仍在「待补中文」里")
        XCTAssertEqual(widget.publishCount, 1)

        // 2. 翻译只返回空白：按翻译失败处理，不保存空提示
        translator.availabilityToReturn = .ready
        translator.resultToReturn = .success("  \n")
        do {
            _ = try await generate.execute(cardID: original.id)
            XCTFail("空白译文应按翻译失败处理")
        } catch let error as GenerateVocabularyHintError {
            XCTAssertEqual(error, .translationFailed)
            XCTAssertEqual(error.message, AppText.E.hintFailed)
        }
        stored = try await vocabulary.card(id: original.id)
        XCTAssertNil(stored?.machineHint)
        XCTAssertEqual(stored?.hintStatus, .failed)
        XCTAssertEqual(widget.publishCount, 2)

        // 3. 翻译还没返回时读者删除了这张词卡：结果丢弃，返回 nil，不报错、不发布
        translator.resultToReturn = .failure(.failed)
        translator.beforeReturning = {
            _ = try? await vocabulary.deleteCard(id: original.id)
        }
        let discarded = try await generate.execute(cardID: original.id)
        XCTAssertNil(discarded)
        XCTAssertTrue(vocabulary.storedCards.isEmpty)
        XCTAssertEqual(widget.publishCount, 2, "词卡已删除时不发布")
    }
}
