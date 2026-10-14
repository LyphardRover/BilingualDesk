// File: BilingualDesk/Domain/UseCases/TranslateParagraph.swift
// Targets: App
import Foundation

enum TranslateParagraphError: UserFacingError, Equatable {
    case languageNotPrepared
    case simulatorUnsupported
    case languagePairUnsupported
    case translationFailed

    var message: String {
        switch self {
        case .languageNotPrepared: return AppText.E.trNeedsLanguage
        case .simulatorUnsupported: return AppText.E.trSimulator
        case .languagePairUnsupported: return AppText.E.trUnsupported
        case .translationFailed: return AppText.E.trFailed
        }
    }
}

/// 把一段英文翻成简体中文并按段缓存（BR-TR-1…6）。
/// 章节标题段不会走到这里：由 ParagraphTranslationCoordinator 保证不请求（BR-TR-6）。
@MainActor
struct TranslateParagraph {
    let books: any BookRepository
    let translator: any TranslationProviding

    init(books: any BookRepository, translator: any TranslationProviding) {
        self.books = books
        self.translator = translator
    }

    func execute(_ paragraph: ReadingParagraph) async throws -> String {
        // BR-TR-1：有效缓存直接返回，不调用 translator。
        if let cached = paragraph.validTranslation {
            return cached
        }

        // BR-TR-2：先查可用性。
        switch await translator.availability() {
        case .ready:
            break
        case .needsDownload:
            throw TranslateParagraphError.languageNotPrepared
        case .simulatorUnsupported:
            throw TranslateParagraphError.simulatorUnsupported
        case .unsupportedLanguagePair:
            throw TranslateParagraphError.languagePairUnsupported
        }

        // BR-TR-3/4：en → zh-Hans（由方法名固定），错误逐个映射，取消原样抛出。
        let raw: String
        do {
            raw = try await translator.translateEnglishToChinese(paragraph.text)
        } catch let error as TranslationProviderError {
            throw Self.translateError(for: error)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw TranslateParagraphError.translationFailed
        }

        let translation = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translation.isEmpty else {
            throw TranslateParagraphError.translationFailed
        }

        // BR-TR-5：写缓存失败（含段已删除）不影响本次显示。
        try? await books.saveTranslation(paragraphID: paragraph.id, text: translation, sourceHash: paragraph.sourceHash)
        return translation
    }

    private static func translateError(for error: TranslationProviderError) -> TranslateParagraphError {
        switch error {
        case .notInstalled: return .languageNotPrepared
        case .simulatorUnsupported: return .simulatorUnsupported
        case .unsupportedLanguagePair: return .languagePairUnsupported
        case .failed: return .translationFailed
        }
    }
}
