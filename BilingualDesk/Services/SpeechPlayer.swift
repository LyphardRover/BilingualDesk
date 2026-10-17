// File: BilingualDesk/Services/SpeechPlayer.swift
// Targets: App
import Foundation
import AVFoundation
import Combine

/// 单词发音与前台连续朗读（02 §9.8 SV-3…SV-6；§13 C7、C11）。
/// 全 App 唯一的 AVSpeechSynthesizer 持有者，由 AppContainer 强引用，App 存活期间不释放。
@MainActor
final class SpeechPlayer: NSObject, SpeechPlaying, AVSpeechSynthesizerDelegate {
    private(set) var state: SpeechState = .idle {
        didSet {
            if state != oldValue {
                stateSubject.send(state)
            }
        }
    }

    /// 订阅时先收到当前值，之后每次变化收到一次（02 §7）。
    var statePublisher: AnyPublisher<SpeechState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    private struct QueuedUtterance {
        let utterance: AVSpeechUtterance          // 强引用，保证回调处理完之前 ObjectIdentifier 不被复用
        let generation: Int
        let isPronunciation: Bool
    }

    private let stateSubject = CurrentValueSubject<SpeechState, Never>(.idle)
    private let synthesizer = AVSpeechSynthesizer()
    /// 音频会话的设置、激活、释放会阻塞调用线程（主线程上调用会被系统报 Hang Risk），
    /// 全部放到这条串行队列按调用顺序执行，后排的操作总是覆盖先排的（SV-5）。
    private let sessionQueue = DispatchQueue(label: "com.William.BilingualDesk.audioSession", qos: .userInitiated)
    /// 已排队激活、还没排队释放；没激活过就不释放（例如没朗读时进入后台）。
    private var isSessionRequested = false
    /// 激活在会话队列上异步完成，失败时已无法抛给调用方，改由这里报告（AppContainer 接到全局 Alert）。
    private let reportError: @MainActor (SpeechError) -> Void
    private var generation = 0
    private var queuedUtterances: [ObjectIdentifier: QueuedUtterance] = [:]
    private var remainingParagraphs: [SpeechParagraph] = []
    private var readingBookID: UUID?
    private var readingVoice: AVSpeechSynthesisVoice?
    private var rate: SpeechRate = .normal
    /// 暂停时上一段恰好读完：继续时直接读下一段。
    private var advanceWhenResumed = false

    init(reportError: @escaping @MainActor (SpeechError) -> Void) {
        self.reportError = reportError
        super.init()
        synthesizer.delegate = self
    }

    // MARK: SpeechPlaying

    func pronounce(_ text: String, rate: SpeechRate) throws {
        haltSpeech()
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        let voice = try prepareToSpeak()
        state = .pronouncing
        let requestGeneration = generation
        Task { @MainActor in
            guard await self.activateAudioSession(for: requestGeneration) else { return }
            self.speak(word, voice: voice, rate: rate, isPronunciation: true)
        }
    }

    func startReading(bookID: UUID, paragraphs: [SpeechParagraph], rate: SpeechRate) throws {
        haltSpeech()
        let readable = paragraphs.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard let first = readable.first else { return }
        let voice = try prepareToSpeak()
        self.rate = rate
        readingBookID = bookID
        readingVoice = voice
        remainingParagraphs = readable
        // 先进入「朗读中」：会话激活期间离开页面、进入后台、移出书库都能看到状态并 stop()。
        state = .reading(bookID: bookID, paragraphOrder: first.order)
        let requestGeneration = generation
        Task { @MainActor in
            guard await self.activateAudioSession(for: requestGeneration) else { return }
            if case .paused = self.state {
                self.advanceWhenResumed = true      // 激活期间被暂停：继续时再读
            } else {
                self.speakNextParagraph()
            }
        }
    }

    func setRate(_ rate: SpeechRate) {
        // 正在读的这一段不变，下一段起生效（01 §4.3）。
        self.rate = rate
    }

    func pause() {
        guard case let .reading(bookID, order) = state else { return }
        _ = synthesizer.pauseSpeaking(at: .word)
        state = .paused(bookID: bookID, paragraphOrder: order)
    }

    func resume() {
        guard case let .paused(bookID, order) = state else { return }
        state = .reading(bookID: bookID, paragraphOrder: order)
        if advanceWhenResumed {
            advanceWhenResumed = false
            speakNextParagraph()
        } else {
            _ = synthesizer.continueSpeaking()
        }
    }

    func stop() {
        haltSpeech()
        deactivateAudioSession()
    }

    // MARK: AVSpeechSynthesizerDelegate（系统线程调用，只取 ID 回主 actor）

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        // 状态在 speak 之前已经设置好，开始回调不需要再改。
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor in
            self.utteranceEnded(utteranceID, finishedNormally: true)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor in
            self.utteranceEnded(utteranceID, finishedNormally: false)
        }
    }

    // MARK: 内部流程

    private func utteranceEnded(_ utteranceID: ObjectIdentifier, finishedNormally: Bool) {
        guard let queued = queuedUtterances.removeValue(forKey: utteranceID) else { return }
        // 旧代次（已被 stop / pronounce / 新的 startReading 取代）的回调一律忽略（SV-6）。
        guard queued.generation == generation, finishedNormally else { return }
        if queued.isPronunciation {
            state = .idle
            deactivateAudioSession()
            return
        }
        if case .paused = state {
            advanceWhenResumed = true
            return
        }
        speakNextParagraph()
    }

    private func speakNextParagraph() {
        guard let bookID = readingBookID, let voice = readingVoice, !remainingParagraphs.isEmpty else {
            // 读完最后一段：回到「未朗读」并释放音频会话。
            stop()
            return
        }
        let paragraph = remainingParagraphs.removeFirst()
        state = .reading(bookID: bookID, paragraphOrder: paragraph.order)
        speak(paragraph.text, voice: voice, rate: rate, isPronunciation: false)
    }

    private func speak(_ text: String, voice: AVSpeechSynthesisVoice, rate: SpeechRate, isPronunciation: Bool) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = rate.utteranceRate
        queuedUtterances[ObjectIdentifier(utterance)] = QueuedUtterance(
            utterance: utterance,
            generation: generation,
            isPronunciation: isPronunciation
        )
        synthesizer.speak(utterance)
    }

    /// 停掉一切朗读并进入新代次；不释放音频会话（紧接着可能马上要说话）。
    private func haltSpeech() {
        generation += 1
        remainingParagraphs = []
        readingBookID = nil
        readingVoice = nil
        advanceWhenResumed = false
        _ = synthesizer.stopSpeaking(at: .immediate)
        state = .idle
    }

    /// 选声音；失败时把音频会话还回去再抛错。激活在真正开始说话前异步完成。
    private func prepareToSpeak() throws -> AVSpeechSynthesisVoice {
        do {
            return try Self.englishVoice()
        } catch {
            deactivateAudioSession()
            throw error
        }
    }

    /// SV-4：优先 en-US，否则任何 en 开头的声音；都没有 → noEnglishVoice。
    private static func englishVoice() throws -> AVSpeechSynthesisVoice {
        if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            return voice
        }
        if let voice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.language.hasPrefix("en") }) {
            return voice
        }
        throw SpeechError.noEnglishVoice
    }

    /// SV-5：每次开始说话前在会话队列上设置 .playback + .spokenAudio 并激活，主 actor 只挂起等结果。
    /// 返回 true = 已激活且这次请求仍是当前代次；等待期间被 stop / pronounce / 新的 startReading 取代返回 false（SV-6）。
    private func activateAudioSession(for requestGeneration: Int) async -> Bool {
        // Task 开始前已被取代：不再激活，免得留下没人释放的会话。
        guard requestGeneration == generation else { return false }
        isSessionRequested = true
        let queue = sessionQueue
        let isActive = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            queue.async {
                let session = AVAudioSession.sharedInstance()
                do {
                    try session.setCategory(.playback, mode: .spokenAudio)
                    try session.setActive(true)
                    continuation.resume(returning: true)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
        guard requestGeneration == generation else { return false }
        guard isActive else {
            haltSpeech()
            deactivateAudioSession()
            reportError(.audioSessionUnavailable)
            return false
        }
        return true
    }

    /// 排在之前的激活之后释放；没请求过激活就什么也不做。
    private func deactivateAudioSession() {
        guard isSessionRequested else { return }
        isSessionRequested = false
        sessionQueue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
