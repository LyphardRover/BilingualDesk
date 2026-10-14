// File: BilingualDeskTests/Support/MockSpeechPlayer.swift
// Targets: Tests
import Foundation
import Combine
@testable import BilingualDesk

@MainActor
final class MockSpeechPlayer: SpeechPlaying {
    // MARK: 可设置
    var state: SpeechState = .idle {
        didSet { stateSubject.send(state) }
    }
    var errorToThrow: SpeechError?

    // MARK: 可检查
    private(set) var stopCallCount = 0
    private(set) var pronouncedTexts: [String] = []
    private(set) var startedBookIDs: [UUID] = []
    private(set) var rateChanges: [SpeechRate] = []

    private let stateSubject = CurrentValueSubject<SpeechState, Never>(.idle)

    init() {}

    var statePublisher: AnyPublisher<SpeechState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    func pronounce(_ text: String, rate: SpeechRate) throws {
        if let errorToThrow {
            throw errorToThrow
        }
        pronouncedTexts.append(text)
        state = .pronouncing
    }

    func startReading(bookID: UUID, paragraphs: [SpeechParagraph], rate: SpeechRate) throws {
        if let errorToThrow {
            throw errorToThrow
        }
        startedBookIDs.append(bookID)
        state = .reading(bookID: bookID, paragraphOrder: paragraphs.first?.order ?? 0)
    }

    func setRate(_ rate: SpeechRate) {
        rateChanges.append(rate)
    }

    func pause() {
        if case let .reading(bookID, paragraphOrder) = state {
            state = .paused(bookID: bookID, paragraphOrder: paragraphOrder)
        }
    }

    func resume() {
        if case let .paused(bookID, paragraphOrder) = state {
            state = .reading(bookID: bookID, paragraphOrder: paragraphOrder)
        }
    }

    func stop() {
        stopCallCount += 1
        state = .idle
    }
}
