// File: BilingualDesk/Features/Vocabulary/CardDetailView.swift
// Targets: App
import SwiftUI

/// 词卡详情页面（页面六）。隐藏系统返回按钮（同时禁止边缘右滑返回），用自定义 “Back” 拦截未保存内容。
struct CardDetailView: View {
    @StateObject private var viewModel: CardDetailViewModel
    @ObservedObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    init(cardID: UUID, dependencies: AppDependencies) {
        self._viewModel = StateObject(wrappedValue: CardDetailViewModel(cardID: cardID, dependencies: dependencies))
        self._router = ObservedObject(wrappedValue: dependencies.router)
    }

    var body: some View {
        content
            .navigationTitle(AppText.T.cardTitle)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if viewModel.requestLeave() { leavePage() }
                    } label: {
                        Label(AppText.T.cardBack, systemImage: "chevron.backward")
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
            .task { await viewModel.load() }
            // 同步「有未保存内容」标记。不在 onDisappear 里清标记：切换标签也会触发 onDisappear。
            .onChange(of: viewModel.hasUnsavedChanges, initial: true) { _, hasUnsaved in
                if router.hasUnsavedCardDraft != hasUnsaved {
                    router.hasUnsavedCardDraft = hasUnsaved
                }
            }
            .confirmationDialog(
                AppText.T.cardLeaveConfirmTitle,
                isPresented: presentationBinding(\.isLeaveConfirmationPresented),
                titleVisibility: .visible
            ) {
                Button(AppText.T.cardLeaveSave) {
                    Task {
                        if await viewModel.saveMeaning() { leavePage() }
                    }
                }
                Button(AppText.T.cardLeaveDiscard, role: .destructive) {
                    leavePage()
                }
                Button(AppText.T.cardLeaveKeepEditing, role: .cancel) {}
            }
            .confirmationDialog(
                AppText.T.vocabDeleteConfirmTitle,
                isPresented: presentationBinding(\.isDeleteConfirmationPresented),
                titleVisibility: .visible
            ) {
                Button(AppText.T.commonDelete, role: .destructive) {
                    Task {
                        if await viewModel.deleteCard() { leavePage() }
                    }
                }
                Button(AppText.T.commonCancel, role: .cancel) {}
            } message: {
                Text(AppText.T.vocabDeleteConfirmMessage)
            }
            .alert(viewModel.alertMessage ?? "", isPresented: alertBinding) {
                Button(AppText.T.commonOk, role: .cancel) {}
            }
    }

    /// 真正离开本页：先清未保存标记（路由随后处理挂起的深链），再出栈。
    /// 有挂起的深链时不播出栈动画：路由紧接着会再改一次导航栈，出栈动画中途改栈会停在一张空白页上。
    private func leavePage() {
        let hasPendingLink = router.pendingDeepLink != nil
        router.hasUnsavedCardDraft = false
        if hasPendingLink {
            withTransaction(\.disablesAnimations, true) { router.vocabularyPath = [] }
        } else {
            dismiss()
        }
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            ProgressView(AppText.T.cardLoading)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .alert(AppText.E.cardGone, isPresented: cardGoneBinding) {
                    Button(AppText.T.commonOk, role: .cancel) { leavePage() }
                }
        case .failed(let message):
            Text(message)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            if let card = viewModel.card {
                cardForm(card)
                    .alert(AppText.E.cardGone, isPresented: cardGoneBinding) {
                        Button(AppText.T.commonOk, role: .cancel) { leavePage() }
                    }
            }
        }
    }

    private func cardForm(_ card: VocabularyCard) -> some View {
        Form {
            wordSection(card)
            hintSection(card)
            meaningSection
            Section {
                Text(card.contextText)
                    .textSelection(.enabled)
            } header: {
                Text(AppText.T.cardSectionContext)
            }
            Section {
                Text(card.contextTranslation ?? AppText.T.cardNoContextTranslation)
                    .foregroundStyle(card.contextTranslation == nil ? .secondary : .primary)
            } header: {
                Text(AppText.T.cardSectionContextTranslation)
            }
            sourceSection(card)
            Section {
                Button(role: .destructive) {
                    viewModel.isDeleteConfirmationPresented = true
                } label: {
                    Text(AppText.T.cardDelete)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
        // “My Meaning” 是多行输入框，回车只换行：滚动时收起键盘，否则下面的语境、来源和删除都被键盘挡住。
        .scrollDismissesKeyboard(.immediately)
    }

    private func wordSection(_ card: VocabularyCard) -> some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(card.selectedText)
                    .font(.title2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(AppText.T.cardPronounce) { viewModel.pronounce() }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
            }
        }
    }

    private func hintSection(_ card: VocabularyCard) -> some View {
        Section {
            if viewModel.isGeneratingHint || card.hintStatus == .pending {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(AppText.T.cardHintPending)
                        .foregroundStyle(.secondary)
                }
            } else if card.hintStatus == .ready, let hint = card.machineHint, !hint.isEmpty {
                Text(hint)
                    .textSelection(.enabled)
            } else {
                Text(AppText.T.cardHintFailed)
                    .foregroundStyle(.secondary)
                Button(AppText.T.cardRegenerate) {
                    Task { await viewModel.regenerateHint() }
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
            }
            if let error = viewModel.hintErrorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text(AppText.T.cardSectionHint)
        }
    }

    private var meaningSection: some View {
        Section {
            TextEditor(text: $viewModel.meaningDraft)
                .frame(minHeight: 120)
                .overlay(alignment: .topLeading) {
                    if viewModel.meaningDraft.isEmpty {
                        Text(AppText.T.cardMeaningPlaceholder)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityLabel(AppText.T.cardSectionMeaning)
            HStack(alignment: .firstTextBaseline) {
                if let note = viewModel.meaningNote {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(AppText.T.cardMeaningCount(count: viewModel.meaningCharacterCount))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(viewModel.isMeaningTooLong ? Color.red : Color.secondary)
            }
            HStack(spacing: 12) {
                Button(AppText.T.cardSaveMeaning) {
                    Task { _ = await viewModel.saveMeaning() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isSaving)
                Button(AppText.T.cardUseMachineHint) {
                    Task { await viewModel.useMachineHint() }
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canUseMachineHint || viewModel.isSaving)
            }
            .controlSize(.large)
            if viewModel.showsSavedConfirmation {
                Text(AppText.T.cardMeaningSaved)
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
        } header: {
            Text(AppText.T.cardSectionMeaning)
        }
    }

    private func sourceSection(_ card: VocabularyCard) -> some View {
        Section {
            Text(AppText.T.cardSource(title: card.sourceBookTitle, order: card.sourceParagraphOrder + 1))
            Button(AppText.T.cardBackToSource) { viewModel.returnToSource() }
                .disabled(!card.isSourceAvailable)
                .frame(minHeight: 44)
            if !card.isSourceAvailable {
                Text(AppText.T.cardSourceGone)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(AppText.T.cardSectionSource)
        }
    }

    // MARK: - 绑定

    /// 弹窗的显示绑定只在值真的改变时写回 ViewModel。SwiftUI 每次收起弹窗后都会再写一次 false
    /// （此时值已经是 false），而 @Published 值相同也会发通知；平时无害，但从弹窗按钮离开本页时
    /// 这次写入落在视图更新中途，直接绑定 `$viewModel.xxx` 会触发「Publishing changes from within view updates」。
    private func presentationBinding(_ keyPath: ReferenceWritableKeyPath<CardDetailViewModel, Bool>) -> Binding<Bool> {
        Binding(
            get: { viewModel[keyPath: keyPath] },
            set: { isPresented in
                if viewModel[keyPath: keyPath] != isPresented { viewModel[keyPath: keyPath] = isPresented }
            }
        )
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.alertMessage != nil },
            set: { isPresented in
                if !isPresented && viewModel.alertMessage != nil { viewModel.alertMessage = nil }
            }
        )
    }

    private var cardGoneBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isCardGone },
            set: { _ in }   // 只读：“OK” 按钮负责返回单词本
        )
    }
}
