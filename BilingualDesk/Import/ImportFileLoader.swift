// File: BilingualDesk/Import/ImportFileLoader.swift
// Targets: App
import Foundation

/// 把系统文件选择器给的 URL 读成 ImportCandidate（02 §9.3、C4）。
/// 非隔离 async：在主线程以外读取 ≤ 10 MB 的文件。只抛 ImportTXTBookError
///（fileTooLarge / fileEmpty / fileUnreadable），由 LibraryViewModel 显示对应文案。
struct ImportFileLoader: Sendable {
    init() {}

    func loadCandidate(from url: URL) async throws -> ImportCandidate {
        // 选择器给的是安全作用域 URL：start / stop 必须成对调用。
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing { url.stopAccessingSecurityScopedResource() }
        }

        // 先看文件大小，过大的文件不读进内存（BR-IMPORT-1/2 的提前检查）。
        let fileSize: Int?
        do {
            fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        } catch {
            throw ImportTXTBookError.fileUnreadable
        }
        if let fileSize {
            try Self.checkSize(fileSize)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            // 没有权限、还在 iCloud 上没下载完等。
            throw ImportTXTBookError.fileUnreadable
        }
        // 文件在两次检查之间可能变化；以实际读到的字节为准再查一次。
        try Self.checkSize(data.count)

        return ImportCandidate(fileName: url.lastPathComponent, data: data, origin: .filePicker)
    }

    private static func checkSize(_ byteCount: Int) throws {
        if byteCount > ImportLimits.maximumFileBytes {
            throw ImportTXTBookError.fileTooLarge
        }
        if byteCount == 0 {
            throw ImportTXTBookError.fileEmpty
        }
    }
}
