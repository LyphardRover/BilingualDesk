// File: BilingualDesk/Features/Inbox/InboxView.swift
// Targets: App
import SwiftUI

/// Pending Imports sheet（待导入文件，01 §4.8；02 §9.10 F47）。自带 NavigationStack，在栈内推入导入预览。
struct InboxView: View {
    @ObservedObject private var monitor: ShareInboxMonitor
    @ObservedObject private var router: AppRouter
    private let dependencies: AppDependencies

    @State private var candidate: ImportCandidate?
    @State private var loadingItemID: UUID?
    @State private var itemPendingDeletion: InboxItem?
    @State private var alertMessage: String?

    init(monitor: ShareInboxMonitor, dependencies: AppDependencies) {
        _monitor = ObservedObject(wrappedValue: monitor)
        _router = ObservedObject(wrappedValue: dependencies.router)
        self.dependencies = dependencies
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(AppText.T.inboxTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(AppText.T.commonDone) {
                            router.isInboxPresented = false
                        }
                    }
                }
                .navigationDestination(item: $candidate) { candidate in
                    ImportPreviewView(
                        candidate: candidate,
                        importBook: dependencies.makeImportTXTBook(),
                        onFinish: { result in
                            finishImport(result, for: candidate)
                        }
                    )
                    .navigationBarBackButtonHidden(true)
                }
                .confirmationDialog(
                    AppText.T.inboxDeleteConfirmTitle,
                    isPresented: deletionDialogBinding,
                    titleVisibility: .visible,
                    presenting: itemPendingDeletion
                ) { item in
                    Button(AppText.T.commonDelete, role: .destructive) {
                        delete(item)
                    }
                    Button(AppText.T.commonCancel, role: .cancel) {}
                } message: { _ in
                    Text(AppText.T.inboxDeleteConfirmMessage)
                }
                .alert(alertMessage ?? "", isPresented: alertBinding) {
                    Button(AppText.T.commonOk, role: .cancel) {}
                }
        }
        .onAppear {
            monitor.refresh()
        }
    }

    // MARK: 列表

    @ViewBuilder
    private var content: some View {
        if monitor.items.isEmpty && monitor.scanErrorMessage == nil {
            ContentUnavailableView(
                AppText.T.inboxEmptyTitle,
                systemImage: "tray",
                description: Text(AppText.T.inboxEmptyMessage)
            )
        } else {
            List {
                if let scanError = monitor.scanErrorMessage {
                    Section {
                        Text(scanError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                if !monitor.items.isEmpty {
                    Section {
                        ForEach(monitor.items) { item in
                            row(for: item)
                        }
                    } footer: {
                        Text(AppText.T.inboxFootnote)
                    }
                }
            }
            .refreshable {
                monitor.refresh()
            }
        }
    }

    private func row(for item: InboxItem) -> some View {
        Button {
            open(item)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.metadata.originalFileName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(AppText.T.inboxRowDetail(
                        dateTime: AppText.monthDayTime(item.metadata.receivedAt),
                        size: AppText.fileSize(item.metadata.byteCount)
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if loadingItemID == item.id {
                    ProgressView()
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .disabled(loadingItemID != nil)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                itemPendingDeletion = item
            } label: {
                Text(AppText.T.commonDelete)
            }
        }
    }

    // MARK: 动作

    private func open(_ item: InboxItem) {
        guard loadingItemID == nil else { return }
        loadingItemID = item.id
        Task {
            defer { loadingItemID = nil }
            do {
                candidate = try await monitor.makeCandidate(for: item)
            } catch let error as UserFacingError {
                alertMessage = error.message
            } catch {
                alertMessage = AppText.E.inboxFileUnreadable
            }
        }
    }

    private func finishImport(_ result: ImportPreviewResult, for candidate: ImportCandidate) {
        switch result {
        case .imported(let book), .duplicateOpenExisting(let book):
            removeImportedItem(of: candidate)
            self.candidate = nil
            router.isInboxPresented = false
            router.openBook(book.id, startOrder: nil)
        case .duplicateBackToLibrary:
            removeImportedItem(of: candidate)
            self.candidate = nil
            router.isInboxPresented = false
        case .cancelled:
            // 退回列表，文件保留（01 §4.2）。
            self.candidate = nil
        }
    }

    /// 导入成功或确认重复后，这个待导入文件自动移除（01 §2.2 F2）。sheet 正在关闭，错误交给全局 Alert。
    private func removeImportedItem(of candidate: ImportCandidate) {
        guard case let .shareInbox(itemID) = candidate.origin else { return }
        do {
            try monitor.remove(itemID: itemID)
        } catch let error as UserFacingError {
            router.showAlert(error.message)
        } catch {
            router.showAlert(AppText.E.inboxDeleteFailed)
        }
    }

    private func delete(_ item: InboxItem) {
        do {
            try monitor.remove(itemID: item.id)
        } catch let error as UserFacingError {
            alertMessage = error.message
        } catch {
            alertMessage = AppText.E.inboxDeleteFailed
        }
    }

    // MARK: 绑定

    private var deletionDialogBinding: Binding<Bool> {
        Binding(
            get: { itemPendingDeletion != nil },
            set: { isPresented in
                if !isPresented && itemPendingDeletion != nil { itemPendingDeletion = nil }
            }
        )
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { alertMessage != nil },
            set: { isPresented in
                if !isPresented && alertMessage != nil { alertMessage = nil }
            }
        )
    }
}
