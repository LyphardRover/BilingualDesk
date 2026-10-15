// File: BilingualDesk/Features/Vocabulary/VocabularyListViewModel.swift
// Targets: App
import Foundation
import Combine

/// 单词本页面（页面五）的状态：列表、英文搜索、“Needs Chinese Only”、删除词卡。
@MainActor
final class VocabularyListViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    enum EmptyState: Equatable {
        case noCards
        case noResults
    }

    @Published private(set) var cards: [VocabularyCard] = []
    @Published private(set) var phase: Phase = .loading
    @Published var searchText: String = ""
    @Published var needsChineseOnly: Bool = false
    @Published var cardPendingDeletion: VocabularyCard?
    @Published var alertMessage: String?

    private let vocabulary: any VocabularyRepository
    private let editCard: EditVocabularyCard
    private var searchTask: Task<Void, Never>?
    private var loadGeneration = 0

    init(vocabulary: any VocabularyRepository, editCard: EditVocabularyCard) {
        self.vocabulary = vocabulary
        self.editCard = editCard
    }

    /// 空且无搜索无筛选 → “No Word Cards Yet”；空且有搜索或筛选 → “No Matching Word Cards”。
    var emptyState: EmptyState? {
        guard phase == .loaded, cards.isEmpty else { return nil }
        let hasCondition = !trimmedSearchText.isEmpty || needsChineseOnly
        return hasCondition ? .noResults : .noCards
    }

    /// 只读查询直接调 Repository（L2）；「待补中文」谓词在 Persistence 里（02 §4.4）。
    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        do {
            let result = try await vocabulary.cards(matching: trimmedSearchText, needsChineseOnly: needsChineseOnly)
            guard generation == loadGeneration else { return }
            cards = result
            phase = .loaded
        } catch {
            guard generation == loadGeneration else { return }
            cards = []
            phase = .failed(AppText.E.vocabLoadFailed)
        }
    }

    /// 300 ms 防抖。
    func searchTextChanged() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.load()
        }
    }

    /// 开关变化立即查询。
    func needsChineseOnlyChanged() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            await self?.load()
        }
    }

    /// 确认删除。失败时保留该行并提示 E-CARD-DELETE-FAILED。
    func confirmDeletion() async {
        guard let card = cardPendingDeletion else { return }
        cardPendingDeletion = nil
        do {
            try await editCard.deleteCard(cardID: card.id)
            await load()
        } catch is CancellationError {
            // 不提示
        } catch let error as UserFacingError {
            alertMessage = error.message
        } catch {
            alertMessage = AppText.E.cardDeleteFailed
        }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
