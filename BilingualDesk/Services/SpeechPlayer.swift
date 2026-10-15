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
    private var generation = 0
    private var queuedUtterances: [ObjectIdentifier: QueuedUtterance] = [:]
    private var remainingParagraphs: [SpeechParagraph] = []
    private var readingBookID: UUID?
    private var readingVoice: AVSpeechSynthesisVoice?
    private var rate: SpeechRate = .normal
    /// 暂停时上一段恰好读完：继续时直接读下一段。
    private var advanceWhenResumed = false

    override init() {
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
        speak(word, voice: voice, rate: rate, isPronunciation: true)
    }

    func startReading(bookID: UUID, paragraphs: [SpeechParagraph], rate: SpeechRate) throws {
        haltSpeech()
        let readable = paragraphs.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !readable.isEmpty else { return }
        let voice = try prepareToSpeak()
        self.rate = rate
        readingBookID = bookID
        readingVoice = voice
        remainingParagraphs = readable
        speakNextParagraph()
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

    /// 选声音并激活音频会话；任何一步失败都把会话还回去再抛错。
    private func prepareToSpeak() throws -> AVSpeechSynthesisVoice {
        do {
            let voice = try Self.englishVoice()
            try activateAudioSession()
            return voice
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

    /// SV-5：每次开始说话前设置 .playback + .spokenAudio 并激活。
    private func activateAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
        } catch {
            throw SpeechError.audioSessionUnavailable
        }
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
