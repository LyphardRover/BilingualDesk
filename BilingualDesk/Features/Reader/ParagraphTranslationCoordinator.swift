// File: BilingualDesk/Features/Reader/ParagraphTranslationCoordinator.swift
// Targets: App
import Foundation
import Combine

/// 段下中文行的 8 种状态（01 §4.3 表格）。
enum ParagraphTranslationState: Equatable {
    case notRequested
    case waiting
    case translating
    case translated(String)
    case failed
    case needsLanguage
    case simulatorUnsupported
    case languagePairUnsupported
}

/// 可见段的串行翻译队列（RD-4）：同一时刻只运行一个 TranslateParagraph.execute，先进先出。
@MainActor
final class ParagraphTranslationCoordinator: ObservableObject {
    @Published private(set) var states: [UUID: ParagraphTranslationState] = [:]
    @Published private(set) var unavailableNotice: String?

    private let translateParagraph: TranslateParagraph
    private var queue: [ReadingParagraph] = []
    private var runningTask: Task<Void, Never>?
    private var runningParagraphID: UUID?
    /// 运行代次：cancelAll() 后，旧任务迟到的结果会被丢弃。
    private var generation = 0
    /// 阻断状态：needsLanguage / simulatorUnsupported / languagePairUnsupported 之一。
    private var blockingState: ParagraphTranslationState?
    private var isNoticeDismissed = false

    init(translateParagraph: TranslateParagraph) {
        self.translateParagraph = translateParagraph
    }

    func state(for paragraph: ReadingParagraph) -> ParagraphTranslationState {
        if let state = states[paragraph.id] { return state }
        if let cached = paragraph.validTranslation { return .translated(cached) }
        return .notRequested
    }

    /// 打开书时调用：已有有效缓存的段直接显示译文。
    func seed(_ paragraphs: [ReadingParagraph]) {
        for paragraph in paragraphs {
            if let cached = paragraph.validTranslation {
                states[paragraph.id] = .translated(cached)
            }
        }
    }

    /// 段出现在屏幕上时请求翻译。章节标题段永不翻译（BR-TR-6）。
    func request(_ paragraph: ReadingParagraph) {
        guard !paragraph.isChapterHeading else { return }
        switch state(for: paragraph) {
        case .notRequested:
            break
        case .needsLanguage, .simulatorUnsupported, .languagePairUnsupported:
            // 已被阻断的段保持原状态；阻断解除后 languagePrepared() 会把它们改回 notRequested。
            guard blockingState == nil else { return }
        case .waiting, .translating, .translated, .failed:
            return
        }
        if let blockingState {
            states[paragraph.id] = blockingState
            return
        }
        if let cached = paragraph.validTranslation {
            states[paragraph.id] = .translated(cached)
            return
        }
        states[paragraph.id] = .waiting
        queue.append(paragraph)
        startNextIfIdle()
    }

    /// 段滑出屏幕：只撤回还在「等待」的段。
    func withdraw(_ paragraph: ReadingParagraph) {
        guard states[paragraph.id] == .waiting else { return }
        queue.removeAll { $0.id == paragraph.id }
        states[paragraph.id] = .notRequested
    }

    /// “Retry”：失败的段重新入队。
    func retry(_ paragraph: ReadingParagraph) {
        guard states[paragraph.id] == .failed else { return }
        states[paragraph.id] = .notRequested
        request(paragraph)
    }

    /// 离开阅读页、进入后台、切到 “English Only” 时调用。
    func cancelAll() {
        generation += 1
        runningTask?.cancel()
        runningTask = nil
        if let runningParagraphID {
            states[runningParagraphID] = .notRequested
        }
        runningParagraphID = nil
        for paragraph in queue {
            states[paragraph.id] = .notRequested
        }
        queue.removeAll()
    }

    /// 语言下载成功：清除阻断，所有「需准备语言」的段恢复为未请求。
    func languagePrepared() {
        if blockingState == .needsLanguage {
            blockingState = nil
        }
        for (id, state) in states where state == .needsLanguage {
            states[id] = .notRequested
        }
    }

    /// “Got It”：本实例（本次打开）不再显示提示条。
    func dismissUnavailableNotice() {
        isNoticeDismissed = true
        unavailableNotice = nil
    }

    // MARK: - 私有

    private func startNextIfIdle() {
        guard runningTask == nil, !queue.isEmpty else { return }
        let paragraph = queue.removeFirst()
        states[paragraph.id] = .translating
        runningParagraphID = paragraph.id
        let currentGeneration = generation
        let useCase = translateParagraph
        runningTask = Task { [weak self] in
            let result: Result<String, any Error>
            do {
                result = .success(try await useCase.execute(paragraph))
            } catch {
                result = .failure(error)
            }
            self?.finish(paragraph, result: result, generation: currentGeneration)
        }
    }

    private func finish(_ paragraph: ReadingParagraph, result: Result<String, any Error>, generation finishedGeneration: Int) {
        guard finishedGeneration == generation else { return }
        runningTask = nil
        runningParagraphID = nil
        switch result {
        case .success(let text):
            states[paragraph.id] = .translated(text)
        case .failure(let error):
            switch error {
            case is CancellationError:
                states[paragraph.id] = .notRequested
            case TranslateParagraphError.languageNotPrepared:
                block(with: .needsLanguage, notice: nil, current: paragraph)
            case TranslateParagraphError.simulatorUnsupported:
                block(with: .simulatorUnsupported, notice: AppText.E.trSimulator, current: paragraph)
            case TranslateParagraphError.languagePairUnsupported:
                block(with: .languagePairUnsupported, notice: AppText.E.trUnsupported, current: paragraph)
            default:
                states[paragraph.id] = .failed
            }
        }
        startNextIfIdle()
    }

    /// 设置阻断：当前段、队列中全部段与之后的请求都直接得到这个状态，不再调用 Use Case。
    private func block(with state: ParagraphTranslationState, notice: String?, current paragraph: ReadingParagraph) {
        blockingState = state
        states[paragraph.id] = state
        for waiting in queue {
            states[waiting.id] = state
        }
        queue.removeAll()
        if let notice, !isNoticeDismissed {
            unavailableNotice = notice
        }
    }
}
