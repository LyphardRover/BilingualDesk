// File: BilingualDesk/Shared/AppGroupContainer.swift
// Targets: App, Share, Widget
import Foundation

/// App Group 文件读写的错误。只在三个 target 内部使用，显示前必须先映射成 E- 文案（02 §14 ER-3）。
enum AppGroupError: Error, Equatable {
    case fileTooLarge
    case fileEmpty
    case writeFailed
    case fileMissing
    case removeFailed
    case snapshotUnreadable
}

/// 共享容器的抽象：App 通过它读写收件箱和快照，测试或 App Group 不可用时可以替换/置空。
protocol SharedContainerProviding: Sendable {
    func addToInbox(copyingFileAt sourceURL: URL, originalFileName: String, receivedAt: Date) throws -> InboxItem
    func inboxItems() throws -> [InboxItem]
    func readInboxFile(_ item: InboxItem) throws -> Data
    func removeInboxItem(_ item: InboxItem) throws
    func writeWidgetSnapshot(_ snapshot: WidgetSnapshot) throws
    func readWidgetSnapshot() throws -> WidgetSnapshot?
}

/// App Group 容器的文件实现（02 §9.9、§10.2、§10.3 AG-1…AG-7）。
struct AppGroupContainer: SharedContainerProviding {
    let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    /// App Group 没配置好时返回 nil（AG-7）；调用方据此降级，不创建替代目录。
    static func make() -> AppGroupContainer? {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedConfiguration.appGroupID
        ) else {
            return nil
        }
        return AppGroupContainer(rootURL: url)
    }

    var inboxURL: URL {
        rootURL.appendingPathComponent(SharedConfiguration.inboxFolderName, isDirectory: true)
    }

    var inboxStagingURL: URL {
        rootURL.appendingPathComponent(SharedConfiguration.inboxStagingFolderName, isDirectory: true)
    }

    var widgetSnapshotURL: URL {
        rootURL.appendingPathComponent(SharedConfiguration.widgetSnapshotFileName, isDirectory: false)
    }

    // MARK: 收件箱

    /// AG-1：检查大小 → 复制到 InboxStaging → 移动到 Inbox → 最后原子写元数据 JSON。
    func addToInbox(copyingFileAt sourceURL: URL, originalFileName: String, receivedAt: Date) throws -> InboxItem {
        let sourceSize = try Self.fileSize(at: sourceURL, errorIfUnreadable: .writeFailed)
        try Self.checkInboxSize(sourceSize)

        let fileManager = FileManager.default
        let id = UUID()
        let stagingFileURL = inboxStagingURL.appendingPathComponent("\(id.uuidString).txt", isDirectory: false)
        let textFileURL = inboxURL.appendingPathComponent("\(id.uuidString).txt", isDirectory: false)
        let metadataURL = inboxURL.appendingPathComponent("\(id.uuidString).json", isDirectory: false)

        do {
            try fileManager.createDirectory(at: inboxURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: inboxStagingURL, withIntermediateDirectories: true)
            try fileManager.copyItem(at: sourceURL, to: stagingFileURL)
        } catch {
            try? fileManager.removeItem(at: stagingFileURL)
            throw AppGroupError.writeFailed
        }

        // 复制后的真实字节数写进元数据；复制过程中文件被改大或清空也能拦住。
        let copiedSize: Int
        do {
            copiedSize = try Self.fileSize(at: stagingFileURL, errorIfUnreadable: .writeFailed)
            try Self.checkInboxSize(copiedSize)
        } catch {
            try? fileManager.removeItem(at: stagingFileURL)
            throw error
        }

        do {
            try fileManager.moveItem(at: stagingFileURL, to: textFileURL)
            let metadata = InboxItemMetadata(
                schemaVersion: SharedConfiguration.inboxSchemaVersion,
                id: id,
                originalFileName: originalFileName,
                receivedAt: receivedAt,
                byteCount: copiedSize
            )
            let data = try SharedJSON.makeEncoder().encode(metadata)
            try data.write(to: metadataURL, options: .atomic)
            return InboxItem(metadata: metadata, textFileURL: textFileURL)
        } catch {
            try? fileManager.removeItem(at: stagingFileURL)
            try? fileManager.removeItem(at: textFileURL)
            try? fileManager.removeItem(at: metadataURL)
            throw AppGroupError.writeFailed
        }
    }

    /// AG-2：只列有效项（能解码、schemaVersion 正确、同名 .txt 存在），按收到时间新到旧。
    func inboxItems() throws -> [InboxItem] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: inboxURL.path) else { return [] }

        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: inboxURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw AppGroupError.fileMissing
        }

        let decoder = SharedJSON.makeDecoder()
        var items: [InboxItem] = []
        for metadataURL in urls where metadataURL.pathExtension.lowercased() == "json" {
            guard
                let data = try? Data(contentsOf: metadataURL),
                let metadata = try? decoder.decode(InboxItemMetadata.self, from: data),
                metadata.schemaVersion == SharedConfiguration.inboxSchemaVersion
            else {
                continue
            }
            let textFileURL = metadataURL.deletingPathExtension().appendingPathExtension("txt")
            guard fileManager.fileExists(atPath: textFileURL.path) else { continue }
            items.append(InboxItem(metadata: metadata, textFileURL: textFileURL))
        }
        return items.sorted { $0.metadata.receivedAt > $1.metadata.receivedAt }
    }

    /// AG-3：.txt 不存在或读失败 → fileMissing；超过 10,000,000 字节 → fileTooLarge。
    func readInboxFile(_ item: InboxItem) throws -> Data {
        guard FileManager.default.fileExists(atPath: item.textFileURL.path) else {
            throw AppGroupError.fileMissing
        }
        let size = try Self.fileSize(at: item.textFileURL, errorIfUnreadable: .fileMissing)
        guard size <= SharedConfiguration.maximumTXTBytes else {
            throw AppGroupError.fileTooLarge
        }
        let data: Data
        do {
            data = try Data(contentsOf: item.textFileURL)
        } catch {
            throw AppGroupError.fileMissing
        }
        guard data.count <= SharedConfiguration.maximumTXTBytes else {
            throw AppGroupError.fileTooLarge
        }
        return data
    }

    /// AG-4：先删 .json（这一项立刻从列表消失），再删 .txt；文件本就不存在不算错。
    func removeInboxItem(_ item: InboxItem) throws {
        let metadataURL = inboxURL.appendingPathComponent("\(item.id.uuidString).json", isDirectory: false)
        for url in [metadataURL, item.textFileURL] {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                throw AppGroupError.removeFailed
            }
        }
    }

    // MARK: Widget 快照

    /// AG-5：编码后原子写 WidgetSnapshot.json，Widget 只会读到完整的旧版或新版。
    func writeWidgetSnapshot(_ snapshot: WidgetSnapshot) throws {
        do {
            let data = try SharedJSON.makeEncoder().encode(snapshot)
            try data.write(to: widgetSnapshotURL, options: .atomic)
        } catch {
            throw AppGroupError.writeFailed
        }
    }

    /// AG-6：文件不存在 → nil；读不出、解码失败或 schemaVersion 不对 → snapshotUnreadable。
    func readWidgetSnapshot() throws -> WidgetSnapshot? {
        guard FileManager.default.fileExists(atPath: widgetSnapshotURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: widgetSnapshotURL)
            let snapshot = try SharedJSON.makeDecoder().decode(WidgetSnapshot.self, from: data)
            guard snapshot.schemaVersion == SharedConfiguration.widgetSnapshotSchemaVersion else {
                throw AppGroupError.snapshotUnreadable
            }
            return snapshot
        } catch {
            throw AppGroupError.snapshotUnreadable
        }
    }

    // MARK: 辅助

    private static func fileSize(at url: URL, errorIfUnreadable: AppGroupError) throws -> Int {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard let size = values.fileSize else { throw errorIfUnreadable }
            return size
        } catch {
            throw errorIfUnreadable
        }
    }

    private static func checkInboxSize(_ size: Int) throws {
        if size > SharedConfiguration.maximumTXTBytes {
            throw AppGroupError.fileTooLarge
        }
        if size == 0 {
            throw AppGroupError.fileEmpty
        }
    }
}
