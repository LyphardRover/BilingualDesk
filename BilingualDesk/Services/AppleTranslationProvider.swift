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
        switch await Self.languageStatus() {
        case .installed:
            return .ready
        case .supported:
            // 真机实测：语言已经下载时，闲置一阵后的第一次查询也报 .supported，翻译一次之后才变 .installed。
            // 只凭它就拦下，机器提示会记成失败、阅读页会弹出准备按钮。所以照常去翻译：
            // 真没下载时 translate 会抛 TranslationError.notInstalled，再转成 .notInstalled（SV-2）。
            return .ready
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
        let timeout = ChunkTimeout()
        return try await withTaskCancellationHandler {
            var translatedChunks: [String] = []
            for chunk in chunks {
                try Task.checkCancellation()
                timeout.start(cancelling: session, after: Self.chunkTimeout)
                defer { timeout.stop() }
                do {
                    let response = try await session.translate(chunk)
                    translatedChunks.append(response.targetText)
                } catch {
                    if timeout.didFire {
                        // 超时：语言没准备好时交给准备按钮，否则算这次没成功（读者可重试）。
                        if await Self.languageStatus() == .installed {
                            throw TranslationProviderError.failed
                        }
                        throw TranslationProviderError.notInstalled
                    }
                    if error is CancellationError || Task.isCancelled {
                        throw CancellationError()
                    }
                    // 任一块失败：区分「没下载」和「这次没成功」（SV-2）。先看错误本身，再看语言状态。
                    if TranslationError.notInstalled ~= error {
                        throw TranslationProviderError.notInstalled
                    }
                    if await Self.languageStatus() == .supported {
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

    #if !targetEnvironment(simulator)
    /// 单块翻译最长等多久。正常 0.1–1 秒；超过就取消，免得一个不返回的请求堵住整条 FIFO 队列。
    private static let chunkTimeout: Duration = .seconds(20)

    private static func languageStatus() async -> LanguageAvailability.Status {
        await LanguageAvailability().status(from: sourceLanguage, to: targetLanguage)
    }

    /// 到时间还没翻完就取消会话，并记下是超时（与读者离开页面造成的取消区分开）。
    @MainActor
    private final class ChunkTimeout {
        private(set) var didFire = false
        private var task: Task<Void, Never>?

        func start(cancelling session: TranslationSession, after limit: Duration) {
            task?.cancel()
            task = Task { @MainActor [weak self] in
                try? await Task.sleep(for: limit)
                guard !Task.isCancelled, let self else { return }
                self.didFire = true
                session.cancel()
            }
        }

        func stop() {
            task?.cancel()
            task = nil
        }
    }
    #endif

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
