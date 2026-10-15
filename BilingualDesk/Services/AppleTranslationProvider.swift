// File: BilingualDesk/Services/AppleTranslationProvider.swift
// Targets: App
import Foundation
// TranslationSession 在 SDK 里没有标 Sendable；本文件只在同一个任务里顺序使用它。
// @preconcurrency 让 complete 并发检查 / Swift 6 不再对它报 sending 警告（07 §5.4）。
@preconcurrency import Translation
import NaturalLanguage

/// 设备端英译中（02 §9.8 SV-1、SV-2；§13 C6）。
/// 全 App 只有一个实例（AppContainer 创建），段落翻译和机器提示共用它的 FIFO 门。
@MainActor
final class AppleTranslationProvider: TranslationProviding {
    static let maximumChunkUTF16Length: Int = 2000

    private static let sourceLanguage = Locale.Language(identifier: "en")
    private static let targetLanguage = Locale.Language(identifier: "zh-Hans")

    /// FIFO 门的状态：有请求在翻译时，后来的请求按到达顺序排队。
    private var isTranslating = false
    private var waitingRequests: [CheckedContinuation<Void, Never>] = []

    init() {}

    // MARK: TranslationProviding

    func availability() async -> TranslationAvailability {
        #if targetEnvironment(simulator)
        return .simulatorUnsupported
        #else
        let status = await LanguageAvailability().status(from: Self.sourceLanguage, to: Self.targetLanguage)
        switch status {
        case .installed:
            return .ready
        case .supported:
            return .needsDownload
        case .unsupported:
            return .unsupportedLanguagePair
        @unknown default:
            return .unsupportedLanguagePair
        }
        #endif
    }

    func translateEnglishToChinese(_ text: String) async throws -> String {
        #if targetEnvironment(simulator)
        throw TranslationProviderError.simulatorUnsupported
        #else
        await enterGate()
        defer { leaveGate() }
        try Task.checkCancellation()

        let chunks = Self.chunks(of: text)
        guard !chunks.isEmpty else { return "" }

        // 每次调用新建一个会话，用完丢弃（C6）。
        let session = TranslationSession(installedSource: Self.sourceLanguage, target: Self.targetLanguage)
        return try await withTaskCancellationHandler {
            var translatedChunks: [String] = []
            for chunk in chunks {
                try Task.checkCancellation()
                do {
                    let response = try await session.translate(chunk)
                    translatedChunks.append(response.targetText)
                } catch {
                    if error is CancellationError || Task.isCancelled {
                        throw CancellationError()
                    }
                    // 任一块失败：重新查语言状态，区分「没下载」和「这次没成功」（SV-2）。
                    if await availability() == .needsDownload {
                        throw TranslationProviderError.notInstalled
                    }
                    throw TranslationProviderError.failed
                }
            }
            try Task.checkCancellation()
            return translatedChunks.joined()
        } onCancel: {
            Task { @MainActor in session.cancel() }
        }
        #endif
    }

    // MARK: FIFO 门

    private func enterGate() async {
        if !isTranslating {
            isTranslating = true
            return
        }
        await withCheckedContinuation { continuation in
            waitingRequests.append(continuation)
        }
    }

    private func leaveGate() {
        if waitingRequests.isEmpty {
            isTranslating = false
        } else {
            // 直接把「正在翻译」交给排在最前面的请求，isTranslating 保持 true。
            waitingRequests.removeFirst().resume()
        }
    }

    // MARK: 长段切块

    /// 按句子切块，每块 UTF-16 长度 ≤ 2000；所有块按顺序拼起来等于原文。
    private static func chunks(of text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        guard text.utf16.count > maximumChunkUTF16Length else { return [text] }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.setLanguage(.english)

        var sentences: [String] = []
        var cursor = text.startIndex
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            // 从上一句末尾切到本句末尾，句间空白跟着前一句，不会丢字。
            if cursor < range.upperBound {
                sentences.append(String(text[cursor..<range.upperBound]))
                cursor = range.upperBound
            }
            return true
        }
        if cursor < text.endIndex {
            sentences.append(String(text[cursor...]))
        }

        var result: [String] = []
        var buffer = ""
        for sentence in sentences {
            for piece in piecesNotLongerThanLimit(sentence) {
                if !buffer.isEmpty, buffer.utf16.count + piece.utf16.count > maximumChunkUTF16Length {
                    result.append(buffer)
                    buffer = ""
                }
                buffer += piece
            }
        }
        if !buffer.isEmpty {
            result.append(buffer)
        }
        return result
    }

    /// 单句超长时按 Character 切开（不会把 emoji 或组合字符切坏）。
    private static func piecesNotLongerThanLimit(_ sentence: String) -> [String] {
        guard sentence.utf16.count > maximumChunkUTF16Length else { return [sentence] }
        var pieces: [String] = []
        var buffer = ""
        for character in sentence {
            let characterLength = String(character).utf16.count
            if !buffer.isEmpty, buffer.utf16.count + characterLength > maximumChunkUTF16Length {
                pieces.append(buffer)
                buffer = ""
            }
            buffer.append(character)
        }
        if !buffer.isEmpty {
            pieces.append(buffer)
        }
        return pieces
    }
}
