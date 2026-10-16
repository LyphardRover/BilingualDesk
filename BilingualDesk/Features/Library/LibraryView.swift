// File: BilingualDesk/Features/Library/LibraryView.swift
// Targets: App
import SwiftUI
import UniformTypeIdentifiers

/// 书库顶部卡片的三种状态（由 06 的 ShareInboxMonitor.bannerState 提供）。
enum InboxBannerState: Equatable {
    case hidden
    case pending(count: Int)                      // T-LIB-INBOX-CARD + T-LIB-INBOX-VIEW
    case appGroupUnavailable                      // E-APPGROUP-UNAVAILABLE
}

/// 书库页面（页面一）+ 书库导航栈。View 自己不读文件，也不查数据库（L1）。
struct LibraryView: View {
    private let dependencies: AppDependencies
    private let inboxBanner: InboxBannerState
    @ObservedObject private var router: AppRouter
    @StateObject private var viewModel: LibraryViewModel
    @State private var isFileImporterPresented = false
    @State private var isRemovalDialogPresented = false

    init(dependencies: AppDependencies, inboxBanner: InboxBannerState) {
        self.dependencies = dependencies
        self.inboxBanner = inboxBanner
        self._router = ObservedObject(wrappedValue: dependencies.router)
        self._viewModel = StateObject(wrappedValue: LibraryViewModel(
            books: dependencies.books,
            removeBook: dependencies.makeRemoveBookKeepingVocabulary(),
            fileLoader: dependencies.fileLoader,
            router: dependencies.router
        ))
    }

    var body: some View {
        NavigationStack(path: $router.libraryPath) {
            libraryList
                .navigationTitle(AppText.T.libTitle)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(AppText.T.libImport) { isFileImporterPresented = true }
                    }
                }
                .searchable(text: $viewModel.searchText, prompt: AppText.T.libSearchPrompt)
                .onChange(of: viewModel.searchText) {
                    viewModel.searchTextChanged()
                }
                .refreshable { await viewModel.load() }
                .task { await viewModel.load() }   // 每次回到书库（含切换标签回来）都重新读取
                .navigationDestination(for: LibraryRoute.self) { route in
                    switch route {
                    case let .reader(bookID, startOrder):
                        // .id(route)：换一本书或换一个起始段时，一定得到全新的阅读页状态。
                        ReaderView(bookID: bookID, startOrder: startOrder, dependencies: dependencies)
                            .id(route)
                    }
                }
        }
        .onChange(of: router.libraryPath.isEmpty) { _, isAtRoot in
            // 从阅读页返回书库：刷新进度与打开时间。
            if isAtRoot { Task { await viewModel.load() } }
        }
        .onChange(of: router.readingPositionRevision) {
            // 阅读页保存完位置后再读一次（上面那次可能早于保存完成）。
            Task { await viewModel.load() }
        }
        .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: [.plainText]) { result in
            Task { await viewModel.importPickedFile(result) }
        }
        .sheet(item: $router.importCandidate, onDismiss: {
            Task { await viewModel.load() }
        }) { candidate in
            NavigationStack {
                ImportPreviewView(candidate: candidate, importBook: dependencies.makeImportTXTBook()) { result in
                    finishImport(result)
                }
            }
        }
        .confirmationDialog(
            removalTitle,
            isPresented: $isRemovalDialogPresented,
            titleVisibility: .visible
        ) {
            Button(AppText.T.libRemoveButton, role: .destructive) {
                Task { await viewModel.confirmRemoval() }
            }
            Button(AppText.T.commonCancel, role: .cancel) {
                viewModel.bookPendingRemoval = nil
            }
        } message: {
            Text(AppText.T.libRemoveConfirmMessage)
        }
        .alert(viewModel.alertMessage ?? "", isPresented: alertBinding) {
            Button(AppText.T.commonOk, role: .cancel) {}
        }
    }

    // MARK: - 列表

    private var libraryList: some View {
        List {
            inboxSection
            switch viewModel.phase {
            case .loading:
                ProgressView(AppText.T.libLoading)
                    .frame(maxWidth: .infinity, minHeight: 88)
                    .listRowSeparator(.hidden)
            case .failed(let message):
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            case .loaded:
                if viewModel.showsEmptyLibrary {
                    emptyLibrary
                } else if viewModel.showsNoResults {
                    noResults
                } else {
                    ForEach(viewModel.books) { book in
                        bookRow(book)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var inboxSection: some View {
        switch inboxBanner {
        case .hidden:
            EmptyView()
        case .pending(let count):
            Section {
                HStack(spacing: 12) {
                    Text(AppText.T.libInboxCard(count: count))
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(AppText.T.libInboxView) {
                        router.isInboxPresented = true
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                }
            }
        case .appGroupUnavailable:
            Section {
                Text(AppText.E.appgroupUnavailable)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func bookRow(_ book: Book) -> some View {
        NavigationLink(value: LibraryRoute.reader(bookID: book.id, startOrder: nil)) {
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(viewModel.rowSubtitle(for: book))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // 不用 .destructive 角色：确认之前不能让行先消失（01 §4.1）。
            Button {
                viewModel.bookPendingRemoval = book
                isRemovalDialogPresented = true
            } label: {
                Text(AppText.T.libRemoveButton)
            }
            .tint(.red)
        }
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label(AppText.T.libEmptyTitle, systemImage: "books.vertical")
        } description: {
            Text(AppText.T.libEmptyMessage)
        } actions: {
            Button(AppText.T.libEmptyAction) { isFileImporterPresented = true }
                .buttonStyle(.borderedProminent)
        }
        .listRowSeparator(.hidden)
    }

    private var noResults: some View {
        ContentUnavailableView(
            AppText.T.libNoResultsTitle,
            systemImage: "magnifyingglass",
            description: Text(AppText.T.libNoResultsMessage)
        )
        .listRowSeparator(.hidden)
    }

    // MARK: - 导入结果

    private func finishImport(_ result: ImportPreviewResult) {
        router.importCandidate = nil
        switch result {
        case .imported(let book), .duplicateOpenExisting(let book):
            // 新书 readingParagraphOrder = 0，所以就是第 1 段；已有书回到它保存的段。
            router.openBook(book.id, startOrder: nil)
        case .duplicateBackToLibrary, .cancelled:
            break
        }
        Task { await viewModel.load() }
    }

    // MARK: - 绑定

    private var removalTitle: String {
        AppText.T.libRemoveConfirmTitle(title: viewModel.bookPendingRemoval?.title ?? "")
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.alertMessage != nil },
            set: { isPresented in
                if !isPresented && viewModel.alertMessage != nil { viewModel.alertMessage = nil }
            }
        )
    }
}
