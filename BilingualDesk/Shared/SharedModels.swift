// File: BilingualDesk/Shared/SharedModels.swift
// Targets: App, Share, Widget
import Foundation

/// App、Share、Widget 共用的 JSON 编解码设置（02 §9.9）。
enum SharedJSON {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// 收件箱元数据：Inbox/<UUID>.json（02 §10.4）。
struct InboxItemMetadata: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let id: UUID
    let originalFileName: String
    let receivedAt: Date
    let byteCount: Int
}

/// 一个待导入文件：元数据 + 同名 .txt 的位置。
struct InboxItem: Identifiable, Equatable, Sendable {
    let metadata: InboxItemMetadata
    let textFileURL: URL

    var id: UUID { metadata.id }
}

/// Widget 左半区：继续阅读的书（02 §11.1）。
struct WidgetBookSummary: Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let progressPercent: Int
}

/// Widget 右半区：最新词卡；meaning 已按 VocabularyMeaning.displayText 渲染好。
struct WidgetCardSummary: Codable, Equatable, Sendable {
    let id: UUID
    let word: String
    let meaning: String
}

/// WidgetSnapshot.json 的完整内容（02 §11.1）。
struct WidgetSnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let generatedAt: Date
    let book: WidgetBookSummary?
    let latestCard: WidgetCardSummary?
    let cardsNeedingChineseCount: Int
}
