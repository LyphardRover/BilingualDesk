// File: BilingualDesk/Features/Vocabulary/VocabularyListView.swift
// Targets: App
import SwiftUI

/// 单词本页面（页面五）+ 单词本导航栈。
struct VocabularyListView: View {
    private let dependencies: AppDependencies
    @ObservedObject private var router: AppRouter
    @StateObject private var viewModel: VocabularyListViewModel
    @State private var isDeleteDialogPresented = false

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        self._router = ObservedObject(wrappedValue: dependencies.router)
        self._viewModel = StateObject(wrappedValue: VocabularyListViewModel(
            vocabulary: dependencies.vocabulary,
            editCard: dependencies.makeEditVocabularyCard()
        ))
    }

    var body: some View {
        NavigationStack(path: $router.vocabularyPath) {
            cardList
                .navigationTitle(AppText.T.vocabTitle)
                .searchable(text: $viewModel.searchText, prompt: AppText.T.vocabSearchPrompt)
                .onChange(of: viewModel.searchText) {
                    viewModel.searchTextChanged()
                }
                .onChange(of: viewModel.needsChineseOnly) {
                    viewModel.needsChineseOnlyChanged()
                }
                .refreshable { await viewModel.load() }
                .task { await viewModel.load() }   // 每次出现时重新读取
                .navigationDestination(for: VocabularyRoute.self) { route in
                    switch route {
                    case .card(let cardID):
                        CardDetailView(cardID: cardID, dependencies: dependencies)
                            .id(route)
                    }
                }
        }
        .onChange(of: router.vocabularyPath.isEmpty) { _, isAtRoot in
            // 从词卡详情返回：刷新（我的理解、删除都可能改变列表）。
            if isAtRoot { Task { await viewModel.load() } }
        }
        .confirmationDialog(
            AppText.T.vocabDeleteConfirmTitle,
            isPresented: $isDeleteDialogPresented,
            titleVisibility: .visible
        ) {
            Button(AppText.T.commonDelete, role: .destructive) {
                Task { await viewModel.confirmDeletion() }
            }
            Button(AppText.T.commonCancel, role: .cancel) {
                viewModel.cardPendingDeletion = nil
            }
        } message: {
            Text(AppText.T.vocabDeleteConfirmMessage)
        }
        .alert(viewModel.alertMessage ?? "", isPresented: alertBinding) {
            Button(AppText.T.commonOk, role: .cancel) {}
        }
    }

    // MARK: - 列表

    private var cardList: some View {
        List {
            Section {
                Toggle(AppText.T.vocabNeedsChineseFilter, isOn: $viewModel.needsChineseOnly)
                    .frame(minHeight: 44)
            }
            switch viewModel.phase {
            case .loading:
                ProgressView(AppText.T.vocabLoading)
                    .frame(maxWidth: .infinity, minHeight: 88)
                    .listRowSeparator(.hidden)
            case .failed(let message):
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            case .loaded:
                switch viewModel.emptyState {
                case .noCards:
                    ContentUnavailableView(
                        AppText.T.vocabEmptyTitle,
                        systemImage: "character.book.closed",
                        description: Text(AppText.T.vocabEmptyMessage)
                    )
                    .listRowSeparator(.hidden)
                case .noResults:
                    ContentUnavailableView(
                        AppText.T.vocabNoResultsTitle,
                        systemImage: "magnifyingglass",
                        description: Text(AppText.T.vocabNoResultsMessage)
                    )
                    .listRowSeparator(.hidden)
                case nil:
                    Section {
                        ForEach(viewModel.cards) { card in
                            cardRow(card)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func cardRow(_ card: VocabularyCard) -> some View {
        NavigationLink(value: VocabularyRoute.card(card.id)) {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.selectedText)
                    .font(.headline)
                    .lineLimit(2)
                meaningLine(card.meaning)
                Text(AppText.T.vocabRowSource(title: card.sourceBookTitle))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 4)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // 不用 .destructive 角色：确认之前不能让行先消失。
            Button {
                viewModel.cardPendingDeletion = card
                isDeleteDialogPresented = true
            } label: {
                Text(AppText.T.commonDelete)
            }
            .tint(.red)
        }
    }

    /// 第 2 行含义：机器提示前面加灰色小标签 “Machine Hint”，其余按 VocabularyMeaning.displayText。
    @ViewBuilder
    private func meaningLine(_ meaning: VocabularyMeaning) -> some View {
        switch meaning {
        case .machine(let hint):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(AppText.T.meaningMachineTag)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.fill.tertiary, in: Capsule())
                Text(hint)
                    .font(.subheadline)
                    .lineLimit(2)
            }
        case .personal, .leftBlank:
            Text(meaning.displayText)
                .font(.subheadline)
                .lineLimit(2)
        case .hintPending, .hintFailed:
            Text(meaning.displayText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.alertMessage != nil },
            set: { isPresented in
                if !isPresented { viewModel.alertMessage = nil }
            }
        )
    }
}
