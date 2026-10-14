// File: BilingualDesk/Domain/UseCases/GenerateVocabularyHint.swift
// Targets: App
import Foundation

enum GenerateVocabularyHintError: UserFacingError, Equatable {
    case languageNotPrepared
    case simulatorUnsupported
    case languagePairUnsupported
    case translationFailed
    case saveFailed

    var message: String {
        switch self {
        case .languageNotPrepared: return AppText.E.hintNeedsLanguage
        case .simulatorUnsupported: return AppText.E.hintSimulator
        case .languagePairUnsupported: return AppText.E.hintUnsupported
        case .translationFailed: return AppText.E.hintFailed
        case .saveFailed: return AppText.E.hintSaveFailed
        }
    }
}

/// 为词卡生成「机器中文提示」= 对 selectedText 做 en → zh-Hans 翻译（BR-HINT-1…6）。
/// 写入只改 machineHint / hintStatus，永不修改读者的「我的理解」（BR-HINT-5）。
@MainActor
struct GenerateVocabularyHint {
    let vocabulary: any VocabularyRepository
    let translator: any TranslationProviding
    let widget: any WidgetSnapshotPublishing
    let now: () -> Date

    init(vocabulary: any VocabularyRepository, translator: any TranslationProviding, widget: any WidgetSnapshotPublishing, now: @escaping () -> Date = Date.init) {
        self.vocabulary = vocabulary
        self.translator = translator
        self.widget = widget
        self.now = now
    }

    /// 返回 nil = 词卡已不存在，结果被丢弃（不报错）。
    func execute(cardID: UUID) async throws -> VocabularyCard? {
        // BR-HINT-1
        let card: VocabularyCard?
        do {
            card = try await vocabulary.card(id: cardID)
        } catch {
            throw GenerateVocabularyHintError.saveFailed
        }
        guard let card else { return nil }

        // BR-HINT-2：可用性 + 翻译；BR-HINT-6：取消时从这里原样抛出，不写任何状态。
        let outcome = try await requestHint(for: card.selectedText)

        switch outcome {
        case .success(let hint):
            // BR-HINT-3：写入成功且词卡还在 → 发布（P6）。
            let saved: VocabularyCard?
            do {
                saved = try await vocabulary.saveMachineHint(cardID: cardID, hint: hint, at: now())
            } catch {
                throw GenerateVocabularyHintError.saveFailed
            }
            if saved != nil {
                await widget.publish()
            }
            return saved

        case .failure(let failure):
            // BR-HINT-4：先记 failed；词卡已被删除（返回 nil）→ 与 BR-HINT-1 一样静默丢弃：返回 nil，不发布、不抛错。
            let marked: VocabularyCard?
            do {
                marked = try await vocabulary.markMachineHintFailed(cardID: cardID, at: now())
            } catch {
                throw GenerateVocabularyHintError.saveFailed
            }
            guard marked != nil else { return nil }
            await widget.publish()
            throw failure
        }
    }

    // MARK: - 私有

    /// 只抛 CancellationError；其余失败都装进 .failure，交给 execute 统一记 failed。
    private func requestHint(for text: String) async throws -> Result<String, GenerateVocabularyHintError> {
        switch await translator.availability() {
        case .ready:
            break
        case .needsDownload:
            return .failure(.languageNotPrepared)
        case .simulatorUnsupported:
            return .failure(.simulatorUnsupported)
        case .unsupportedLanguagePair:
            return .failure(.languagePairUnsupported)
        }

        let raw: String
        do {
            raw = try await translator.translateEnglishToChinese(text)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as TranslationProviderError {
            switch error {
            case .notInstalled: return .failure(.languageNotPrepared)
            case .simulatorUnsupported: return .failure(.simulatorUnsupported)
            case .unsupportedLanguagePair: return .failure(.languagePairUnsupported)
            case .failed: return .failure(.translationFailed)
            }
        } catch {
            return .failure(.translationFailed)
        }

        let hint = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return hint.isEmpty ? .failure(.translationFailed) : .success(hint)
    }
}
