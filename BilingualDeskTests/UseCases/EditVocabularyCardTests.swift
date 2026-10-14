// File: BilingualDeskTests/UseCases/EditVocabularyCardTests.swift
// Targets: Tests
import Foundation
import XCTest
@testable import BilingualDesk

/// U14：EditVocabularyCard（BR-EDIT）。只用 Mock 仓库。
final class EditVocabularyCardTests: XCTestCase {

    // U14 · BR-EDIT-1/2 · 边界
    @MainActor
    func test_personalMeaningLongerThan500Characters_isRejected_andEmptyMeaningIsSavedAsLeftBlank() async throws {
        let original = Fixtures.card(hintStatus: .failed)
        let vocabulary = MockVocabularyRepository()
        vocabulary.storedCards = [original]
        let widget = MockWidgetSnapshotPublisher()
        let edit = EditVocabularyCard(vocabulary: vocabulary, widget: widget, now: { Fixtures.fixedDate })

        // 501 个字符：拒绝，不写库、不发布
        do {
            _ = try await edit.saveMeaning(String(repeating: "好", count: 501), cardID: original.id)
            XCTFail("501 个字符的理解应被拒绝")
        } catch let error as EditVocabularyCardError {
            XCTAssertEqual(error, .meaningTooLong)
            XCTAssertEqual(error.message, AppText.E.cardMeaningTooLong)
        }
        XCTAssertNil(vocabulary.storedCards.first?.userMeaningOverride)
        XCTAssertEqual(widget.publishCount, 0)

        // 500 个字符（去首尾空白后）：允许
        let exactly500 = String(repeating: "好", count: 500)
        let saved500 = try await edit.saveMeaning("  \(exactly500)\n", cardID: original.id)
        XCTAssertEqual(saved500.userMeaningOverride, exactly500)
        XCTAssertEqual(widget.publishCount, 1)

        // 只有空白：保存为 ""（已留空），不是 nil
        let leftBlank = try await edit.saveMeaning("  \n ", cardID: original.id)
        XCTAssertEqual(leftBlank.userMeaningOverride, "")
        XCTAssertEqual(leftBlank.meaning, .leftBlank)
        XCTAssertEqual(leftBlank.meaning.displayText, AppText.T.meaningLeftBlank)
        XCTAssertFalse(leftBlank.needsChinese, "已留空的词卡不再算「待补中文」")
        XCTAssertEqual(widget.publishCount, 2)

        // 使用机器提示：清除个人理解（nil），提示失败的卡重新回到「待补中文」
        let cleared = try await edit.useMachineHint(cardID: original.id)
        XCTAssertNil(cleared.userMeaningOverride)
        XCTAssertTrue(cleared.needsChinese)
        XCTAssertEqual(widget.publishCount, 3)
    }

    // U20 · BR-EDIT-5/6 · happy + 领域错误
    @MainActor
    func test_deletingWordCard_removesItAndPublishes_andFailedDeleteKeepsCard() async throws {
        let original = Fixtures.card()
        let vocabulary = MockVocabularyRepository()
        vocabulary.storedCards = [original]
        let widget = MockWidgetSnapshotPublisher()
        let edit = EditVocabularyCard(vocabulary: vocabulary, widget: widget, now: { Fixtures.fixedDate })

        // 删除词卡：从单词本移除，发布一次
        try await edit.deleteCard(cardID: original.id)
        XCTAssertEqual(vocabulary.deletedCardIDs, [original.id])
        let gone = try await vocabulary.card(id: original.id)
        XCTAssertNil(gone)
        XCTAssertEqual(widget.publishCount, 1)

        // 词卡已删除后再保存理解：报「词卡已删除」，不发布
        do {
            _ = try await edit.saveMeaning("好奇的", cardID: original.id)
            XCTFail("已删除的词卡不能再保存理解")
        } catch let error as EditVocabularyCardError {
            XCTAssertEqual(error, .cardNotFound)
            XCTAssertEqual(error.message, AppText.E.cardGone)
        }
        XCTAssertEqual(widget.publishCount, 1)

        // 数据库写入失败：报「删除失败」，词卡仍在，不发布
        let another = Fixtures.card(selectedText: "student")
        vocabulary.storedCards = [another]
        vocabulary.errorToThrow = .storageFailed("disk full")
        do {
            try await edit.deleteCard(cardID: another.id)
            XCTFail("数据库写入失败时应报删除失败")
        } catch let error as EditVocabularyCardError {
            XCTAssertEqual(error, .deleteFailed)
            XCTAssertEqual(error.message, AppText.E.cardDeleteFailed)
        }
        XCTAssertEqual(vocabulary.storedCards.map(\.id), [another.id])
        XCTAssertEqual(widget.publishCount, 1)
    }
}
