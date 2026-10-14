// File: BilingualDesk/Domain/UseCases/EditVocabularyCard.swift
// Targets: App
import Foundation

enum EditVocabularyCardError: UserFacingError, Equatable {
    case meaningTooLong
    case cardNotFound
    case saveFailed
    case deleteFailed

    var message: String {
        switch self {
        case .meaningTooLong: return AppText.E.cardMeaningTooLong
        case .cardNotFound: return AppText.E.cardGone
        case .saveFailed: return AppText.E.cardSaveFailed
        case .deleteFailed: return AppText.E.cardDeleteFailed
        }
    }
}

/// 词卡详情里的三个写操作：“Save Meaning”、“Use Machine Hint”、“Delete Word Card”（BR-EDIT-1…6）。
@MainActor
struct EditVocabularyCard {
    let vocabulary: any VocabularyRepository
    let widget: any WidgetSnapshotPublishing
    let now: () -> Date

    init(vocabulary: any VocabularyRepository, widget: any WidgetSnapshotPublishing, now: @escaping () -> Date = Date.init) {
        self.vocabulary = vocabulary
        self.widget = widget
        self.now = now
    }

    /// BR-EDIT-1/2：去首尾空白后 ≤ 500 个字符；空字符串合法，保存为 ""（= 已留空），不转成 nil。
    func saveMeaning(_ text: String, cardID: UUID) async throws -> VocabularyCard {
        let meaning = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard meaning.count <= VocabularyLimits.maximumMeaningLength else {
            throw EditVocabularyCardError.meaningTooLong
        }
        let card = try await writeMeaning(meaning, cardID: cardID)
        await widget.publish()   // BR-EDIT-6 / P5
        return card
    }

    /// BR-EDIT-3：清除个人理解（nil），单词本改为显示机器提示。
    func useMachineHint(cardID: UUID) async throws -> VocabularyCard {
        let card = try await writeMeaning(nil, cardID: cardID)
        await widget.publish()   // BR-EDIT-6 / P5
        return card
    }

    /// BR-EDIT-5：词卡本来就不存在视为成功；其他仓库错误 → deleteFailed。
    func deleteCard(cardID: UUID) async throws {
        do {
            try await vocabulary.deleteCard(id: cardID)
        } catch RepositoryError.cardNotFound {
            // 仓库按合同对不存在的卡不抛错；万一抛了，也按「已删除」处理。
        } catch {
            throw EditVocabularyCardError.deleteFailed
        }
        await widget.publish()   // BR-EDIT-6 / P5
    }

    // MARK: - 私有

    /// BR-EDIT-4：updatedAt = now()；cardNotFound → cardNotFound，其他 → saveFailed。
    private func writeMeaning(_ meaning: String?, cardID: UUID) async throws -> VocabularyCard {
        do {
            return try await vocabulary.saveUserMeaning(cardID: cardID, meaning: meaning, at: now())
        } catch RepositoryError.cardNotFound {
            throw EditVocabularyCardError.cardNotFound
        } catch {
            throw EditVocabularyCardError.saveFailed
        }
    }
}
