// File: BilingualDesk/Sharing/ShareInboxMonitor.swift
// Targets: App
import Foundation
import Combine

/// 收件箱读取与删除的错误（02 §9.10、§14）。
enum ShareInboxError: UserFacingError, Equatable {
    case fileTooLarge          // E-IMPORT-TOO-LARGE
    case fileUnreadable        // E-INBOX-FILE-UNREADABLE
    case deleteFailed          // E-INBOX-DELETE-FAILED

    var message: String {
        switch self {
        case .fileTooLarge:
            return AppText.E.importTooLarge
        case .fileUnreadable:
            return AppText.E.inboxFileUnreadable
        case .deleteFailed:
            return AppText.E.inboxDeleteFailed
        }
    }
}

/// 扫描、读取、删除 Share 扩展放进 App Group 的待导入文件（02 §9.10 F46）。
@MainActor
final class ShareInboxMonitor: ObservableObject {
    @Published private(set) var items: [InboxItem] = []
    @Published private(set) var scanErrorMessage: String?
    let isAvailable: Bool

    private let container: (any SharedContainerProviding)?

    init(container: (any SharedContainerProviding)?) {
        self.container = container
        self.isAvailable = container != nil
    }

    /// 书库顶部卡片三选一（01 §4.1）。
    var bannerState: InboxBannerState {
        guard isAvailable else { return .appGroupUnavailable }
        return items.isEmpty ? .hidden : .pending(count: items.count)
    }

    /// 只在内容真的变了时才写回：@Published 值相同也会通知，书库和单词本会跟着无谓地重绘。
    /// 冷启动时这次重绘和深链改导航栈落在同一帧，SwiftUI 会报 “NavigationRequestObserver tried to update multiple times per frame”。
    func refresh() {
        guard let container else {
            // AG-7：App Group 不可用时是空操作。
            update(items: [], scanErrorMessage: nil)
            return
        }
        do {
            update(items: try container.inboxItems(), scanErrorMessage: nil)
        } catch {
            update(items: items, scanErrorMessage: AppText.E.inboxScanFailed)
        }
    }

    private func update(items newItems: [InboxItem], scanErrorMessage newMessage: String?) {
        if items != newItems { items = newItems }
        if scanErrorMessage != newMessage { scanErrorMessage = newMessage }
    }

    /// 读出文件内容，交给导入预览。读文件在主线程以外进行（C4）。
    func makeCandidate(for item: InboxItem) async throws -> ImportCandidate {
        guard let container else { throw ShareInboxError.fileUnreadable }
        let data: Data
        do {
            data = try await Self.readData(from: container, item: item)
        } catch AppGroupError.fileTooLarge {
            throw ShareInboxError.fileTooLarge
        } catch {
            throw ShareInboxError.fileUnreadable
        }
        return ImportCandidate(
            fileName: item.metadata.originalFileName,
            data: data,
            origin: .shareInbox(itemID: item.id)
        )
    }

    func remove(itemID: UUID) throws {
        guard let container else { return }
        var item = items.first { $0.id == itemID }
        if item == nil {
            // 列表可能过时：重新扫描一次再找；仍然找不到说明它已经不在了。
            refresh()
            item = items.first { $0.id == itemID }
        }
        guard let item else { return }
        do {
            try container.removeInboxItem(item)
        } catch {
            refresh()
            throw ShareInboxError.deleteFailed
        }
        refresh()
    }

    /// nonisolated async：在全局并发执行器上运行，不占主线程（02 §13 C1、C4）。
    private nonisolated static func readData(from container: any SharedContainerProviding, item: InboxItem) async throws -> Data {
        try container.readInboxFile(item)
    }
}
