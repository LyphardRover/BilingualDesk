// File: BilingualDesk/Sharing/WidgetSnapshotPublisher.swift
// Targets: App
import Foundation
import WidgetKit

/// 生成并原子写 Widget 快照，然后请求刷新 Widget（02 §9.10、§11）。
/// 只由发布时机表 P1–P8 中的调用方触发；永不抛错。
@MainActor
final class WidgetSnapshotPublisher: WidgetSnapshotPublishing {
    private let books: any BookRepository
    private let vocabulary: any VocabularyRepository
    private let container: (any SharedContainerProviding)?
    private let now: () -> Date
    private let reloadTimelines: @MainActor () -> Void

    private var isPublishing = false
    private var needsAnotherPass = false

    init(books: any BookRepository, vocabulary: any VocabularyRepository, container: (any SharedContainerProviding)?,
         now: @escaping () -> Date = Date.init,
         reloadTimelines: @escaping @MainActor () -> Void = { WidgetCenter.shared.reloadAllTimelines() }) {
        self.books = books
        self.vocabulary = vocabulary
        self.container = container
        self.now = now
        self.reloadTimelines = reloadTimelines
    }

    func publish() async {
        guard let container else { return }
        if isPublishing {
            // 合并重入：本轮结束后再生成一次，保证最后写入的是最新数据。
            needsAnotherPass = true
            return
        }
        isPublishing = true
        defer { isPublishing = false }

        repeat {
            needsAnotherPass = false
            do {
                let snapshot = try await makeSnapshot()
                try container.writeWidgetSnapshot(snapshot)
                reloadTimelines()
            } catch {
                #if DEBUG
                print("WidgetSnapshotPublisher: snapshot not published: \(error)")
                #endif
            }
        } while needsAnotherPass
    }

    /// 02 §11.1 的字段来源：最近的书、最新词卡、待补中文数量。
    func makeSnapshot() async throws -> WidgetSnapshot {
        let library = try await books.books(matching: "")
        let bookSummary = library.first.map { book in
            WidgetBookSummary(
                id: book.id,
                title: String(book.title.prefix(ImportLimits.maximumTitleLength)),
                progressPercent: book.progressPercent
            )
        }

        let latestCard = try await vocabulary.latestCard()
        let cardSummary = latestCard.map { card in
            WidgetCardSummary(id: card.id, word: card.selectedText, meaning: card.meaning.displayText)
        }

        let needsChineseCount = try await vocabulary.countCardsNeedingChinese()

        return WidgetSnapshot(
            schemaVersion: SharedConfiguration.widgetSnapshotSchemaVersion,
            generatedAt: now(),
            book: bookSummary,
            latestCard: cardSummary,
            cardsNeedingChineseCount: needsChineseCount
        )
    }
}
