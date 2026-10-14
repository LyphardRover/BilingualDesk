// File: BilingualDeskTests/Support/MockVocabularyRepository.swift
// Targets: Tests
import Foundation
@testable import BilingualDesk

@MainActor
final class MockVocabularyRepository: VocabularyRepository {
    // MARK: 可设置
    var storedCards: [VocabularyCard] = []
    /// 非 nil 时每个方法都抛它。
    var errorToThrow: RepositoryError?
    /// 这些段 id 视为已被删除：insertCard 抛 paragraphNotFound（Core Data 实现同样如此）。
    var missingParagraphIDs: Set<UUID> = []

    // MARK: 可检查
    private(set) var insertedDrafts: [VocabularyCardDraft] = []
    private(set) var deletedCardIDs: [UUID] = []

    init() {}

    func cards(matching searchText: String, needsChineseOnly: Bool) async throws -> [VocabularyCard] {
        try throwIfNeeded()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return storedCards
            .filter { card in
                let matchesText = query.isEmpty
                    || card.selectedText.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                let matchesFilter = !needsChineseOnly || card.needsChinese
                return matchesText && matchesFilter
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func card(id: UUID) async throws -> VocabularyCard? {
        try throwIfNeeded()
        return storedCards.first { $0.id == id }
    }

    func card(paragraphID: UUID, location: Int, length: Int) async throws -> VocabularyCard? {
        try throwIfNeeded()
        return storedCards.first {
            $0.sourceParagraphID == paragraphID && $0.selectionLocation == location && $0.selectionLength == length
        }
    }

    func insertCard(_ draft: VocabularyCardDraft, at date: Date) async throws -> VocabularyCard {
        try throwIfNeeded()
        if missingParagraphIDs.contains(draft.sourceParagraphID) {
            throw RepositoryError.paragraphNotFound
        }
        let card = VocabularyCard(
            id: UUID(),
            selectedText: draft.selectedText,
            selectionLocation: draft.selectionLocation,
            selectionLength: draft.selectionLength,
            contextText: draft.contextText,
            contextTranslation: draft.contextTranslation,
            machineHint: nil,
            hintStatus: .pending,
            userMeaningOverride: nil,
            createdAt: date,
            updatedAt: date,
            sourceBookID: draft.sourceBookID,
            sourceBookTitle: draft.sourceBookTitle,
            sourceParagraphOrder: draft.sourceParagraphOrder,
            sourceParagraphID: draft.sourceParagraphID
        )
        storedCards.append(card)
        insertedDrafts.append(draft)
        return card
    }

    func saveMachineHint(cardID: UUID, hint: String, at date: Date) async throws -> VocabularyCard? {
        try throwIfNeeded()
        guard let index = cardIndex(cardID) else { return nil }
        let old = storedCards[index]
        storedCards[index] = Self.copy(of: old, machineHint: hint, hintStatus: .ready, userMeaningOverride: old.userMeaningOverride, updatedAt: date)
        return storedCards[index]
    }

    func markMachineHintFailed(cardID: UUID, at date: Date) async throws -> VocabularyCard? {
        try throwIfNeeded()
        guard let index = cardIndex(cardID) else { return nil }
        let old = storedCards[index]
        storedCards[index] = Self.copy(of: old, machineHint: old.machineHint, hintStatus: .failed, userMeaningOverride: old.userMeaningOverride, updatedAt: date)
        return storedCards[index]
    }

    func saveUserMeaning(cardID: UUID, meaning: String?, at date: Date) async throws -> VocabularyCard {
        try throwIfNeeded()
        guard let index = cardIndex(cardID) else {
            throw RepositoryError.cardNotFound
        }
        let old = storedCards[index]
        storedCards[index] = Self.copy(of: old, machineHint: old.machineHint, hintStatus: old.hintStatus, userMeaningOverride: meaning, updatedAt: date)
        return storedCards[index]
    }

    func deleteCard(id: UUID) async throws {
        try throwIfNeeded()
        storedCards.removeAll { $0.id == id }
        deletedCardIDs.append(id)
    }

    func latestCard() async throws -> VocabularyCard? {
        try throwIfNeeded()
        return storedCards.max { $0.createdAt < $1.createdAt }
    }

    func countCardsNeedingChinese() async throws -> Int {
        try throwIfNeeded()
        return storedCards.filter { $0.needsChinese }.count
    }

    // MARK: 私有辅助

    private func throwIfNeeded() throws {
        if let errorToThrow {
            throw errorToThrow
        }
    }

    private func cardIndex(_ id: UUID) -> Int? {
        storedCards.firstIndex { $0.id == id }
    }

    private static func copy(
        of card: VocabularyCard,
        machineHint: String?,
        hintStatus: MachineHintStatus,
        userMeaningOverride: String?,
        updatedAt: Date
    ) -> VocabularyCard {
        VocabularyCard(
            id: card.id,
            selectedText: card.selectedText,
            selectionLocation: card.selectionLocation,
            selectionLength: card.selectionLength,
            contextText: card.contextText,
            contextTranslation: card.contextTranslation,
            machineHint: machineHint,
            hintStatus: hintStatus,
            userMeaningOverride: userMeaningOverride,
            createdAt: card.createdAt,
            updatedAt: updatedAt,
            sourceBookID: card.sourceBookID,
            sourceBookTitle: card.sourceBookTitle,
            sourceParagraphOrder: card.sourceParagraphOrder,
            sourceParagraphID: card.sourceParagraphID
        )
    }
}
