// File: BilingualDesk/Shared/SharedConfiguration.swift
// Targets: App, Share, Widget
import Foundation

/// App、Share、Widget 三个 target 共用的固定常量（02 §10.1）。
/// 只放「三方必须逐字一致」的值；其他数字（书名、选区等上限）放在 Domain/Models.swift。
enum SharedConfiguration {
    /// App Group ID。前缀固定为 com.William（03 §2.1）；若 Xcode 提示已被占用而降级加数字（如 com.William2026），这里同步改；
    /// 必须与三个 entitlements 文件里的 com.apple.security.application-groups 逐字一致。
    static let appGroupID = "group.com.William.BilingualDesk"

    /// Widget 的 kind（F51 的 StaticConfiguration 使用；改了会让已添加的 Widget 失效）。
    static let widgetKind = "BilingualDeskReadingWidget"

    /// 深链 scheme（02 §12），与 App 的 URL Types 一致。
    static let urlScheme = "bilingualdesk"

    /// TXT 上限：10,000,000 字节（恰好 10,000,000 允许，BR-IMPORT-1、AG-1）。
    static let maximumTXTBytes = 10_000_000

    /// App Group 容器内的目录与文件名（02 §10.2）。
    static let inboxFolderName = "Inbox"
    static let inboxStagingFolderName = "InboxStaging"
    static let widgetSnapshotFileName = "WidgetSnapshot.json"

    /// 收件箱元数据与 Widget 快照的格式版本（AG-2、AG-6 只接受 1）。
    static let inboxSchemaVersion = 1
    static let widgetSnapshotSchemaVersion = 1
}
