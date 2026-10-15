// File: BilingualDesk/Features/Vocabulary/CardDetailViewModel.swift
// Targets: App
import Foundation
import Combine

/// 词卡详情（页面六）的状态：机器提示、我的理解、发音、回到原文、删除、离开拦截。
@MainActor
final class CardDetailViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let cardID: UUID
    @Published private(set) var phase: Phase = .loading
    @Published private(set) var card: VocabularyCard?
    @Published var meaningDraft: String = ""
    @Published private(set) var isSaving: Bool = false
    @Published private(set) var isGeneratingHint: Bool = false
    @Published private(set) var hintErrorMessage: String?
    @Published private(set) var showsSavedConfirmation: Bool = false
    @Published private(set) var isCardGone: Bool = false
    @Published var alertMessage: String?
    @Published var isDeleteConfirmationPresented: Bool = false
    @Published var isLeaveConfirmationPresented: Bool = false

    private let dependencies: AppDependencies
    private let editCard: EditVocabularyCard
    private let generateHint: GenerateVocabularyHint
    private var isLoadStarted = false
    private var savedConfirmationTask: Task<Void, Never>?

    init(cardID: UUID, dependencies: AppDependencies) {
        self.cardID = cardID
        self.dependencies = dependencies
        self.editCard = dependencies.makeEditVocabularyCard()
        self.generateHint = dependencies.makeGenerateVocabularyHint()
    }

    /// 输入框内容与已保存的个人理解不同（从未写过视为空字符串）。
    var hasUnsavedChanges: Bool {
        meaningDraft != (card?.userMeaningOverride ?? "")
    }

    /// 去掉首尾空白后的字符数（与 BR-EDIT-1 的计数口径一致）。
    var meaningCharacterCount: Int {
        meaningDraft.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    var isMeaningTooLong: Bool {
        meaningCharacterCount > VocabularyLimits.maximumMeaningLength
    }

    /// 只有保存过个人理解（含 “Left Blank”）时，“Use Machine Hint” 才可用。
    var canUseMachineHint: Bool {
        card?.userMeaningOverride != nil
    }

    var meaningNote: String? {
        guard let card else { return nil }
        guard let saved = card.userMeaningOverride else { return AppText.T.cardMeaningUnsetNote }
        return saved.isEmpty ? AppText.T.cardMeaningLeftBlankNote : nil
    }

    /// 只读一次：切换标签再回来时保留未保存的输入。提示仍在「生成中」时自动再生成一次。
    func load() async {
        guard !isLoadStarted else { return }
        isLoadStarted = true
        do {
            guard let loaded = try await dependencies.vocabulary.card(id: cardID) else {
                isCardGone = true
                return
            }
            card = loaded
            meaningDraft = loaded.userMeaningOverride ?? ""
            phase = .loaded
            if loaded.hintStatus == .pending {
                await regenerateHint()
            }
        } catch is CancellationError {
            isLoadStarted = false
        } catch {
            phase = .failed(AppText.E.cardLoadFailed)
        }
    }

    /// “Save Meaning”。空内容合法（= Left Blank）；成功后显示 “Meaning saved” 2 秒。
    func saveMeaning() async -> Bool {
        guard card != nil, !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            let updated = try await editCard.saveMeaning(meaningDraft, cardID: cardID)
            card = updated
            meaningDraft = updated.userMeaningOverride ?? ""
            flashSavedConfirmation()
            return true
        } catch EditVocabularyCardError.cardNotFound {
            isCardGone = true
            return false
        } catch is CancellationError {
            return false
        } catch let error as UserFacingError {
            alertMessage = error.message
            return false
        } catch {
            alertMessage = AppText.E.cardSaveFailed
            return false
        }
    }

    /// “Use Machine Hint” = 清除个人理解（BR-EDIT-3）。
    func useMachineHint() async {
        guard card != nil, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let updated = try await editCard.useMachineHint(cardID: cardID)
            card = updated
            meaningDraft = updated.userMeaningOverride ?? ""
        } catch EditVocabularyCardError.cardNotFound {
            isCardGone = true
        } catch is CancellationError {
            // 不提示
        } catch let error as UserFacingError {
            alertMessage = error.message
        } catch {
            alertMessage = AppText.E.cardSaveFailed
        }
    }

    /// “Regenerate”：直接调用 GenerateVocabularyHint（不经 runner）。失败时在提示区显示红字。
    func regenerateHint() async {
        guard card != nil, !isGeneratingHint else { return }
        isGeneratingHint = true
        hintErrorMessage = nil
        defer { isGeneratingHint = false }
        do {
            if let updated = try await generateHint.execute(cardID: cardID) {
                card = updated   // 只更新机器提示；输入框里的草稿不动（BR-HINT-5）
            } else {
                isCardGone = true
            }
        } catch is CancellationError {
            // 不写状态，不提示（BR-HINT-6）
        } catch let error as UserFacingError {
            hintErrorMessage = error.message
            await reloadCardKeepingDraft()
        } catch {
            hintErrorMessage = AppText.E.hintFailed
            await reloadCardKeepingDraft()
        }
    }

    func pronounce() {
        guard let card else { return }
        do {
            try dependencies.speech.pronounce(card.selectedText, rate: dependencies.preferences.speechRate)
        } catch let error as UserFacingError {
            alertMessage = error.message
        } catch {
            alertMessage = AppText.E.speechAudioUnavailable
        }
    }

    /// 删除词卡。成功返回 true，由页面返回单词本。
    func deleteCard() async -> Bool {
        do {
            try await editCard.deleteCard(cardID: cardID)
            return true
        } catch is CancellationError {
            return false
        } catch let error as UserFacingError {
            alertMessage = error.message
            return false
        } catch {
            alertMessage = AppText.E.cardDeleteFailed
            return false
        }
    }

    /// “Go to Source”：切到书库标签并打开来源段。原书已移出时按钮是禁用的。
    func returnToSource() {
        guard let card, card.isSourceAvailable, let bookID = card.sourceBookID else { return }
        dependencies.router.openBook(bookID, startOrder: card.sourceParagraphOrder)
    }

    /// 点 “Back”：没有未保存内容 → true（可以离开）；否则弹出离开确认并返回 false。
    func requestLeave() -> Bool {
        guard hasUnsavedChanges else { return true }
        isLeaveConfirmationPresented = true
        return false
    }

    // MARK: - 私有

    private func flashSavedConfirmation() {
        showsSavedConfirmation = true
        savedConfirmationTask?.cancel()
        savedConfirmationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.showsSavedConfirmation = false
        }
    }

    /// 生成失败后词卡状态已变为 failed：重读一次，让提示区显示 “Regenerate”。
    private func reloadCardKeepingDraft() async {
        guard let latest = try? await dependencies.vocabulary.card(id: cardID) else { return }
        card = latest
    }
}
