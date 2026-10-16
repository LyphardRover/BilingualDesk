// File: BilingualDeskWidget/WidgetViews.swift
// Targets: Widget
import SwiftUI
import WidgetKit

/// Widget 根视图：按尺寸与快照内容选择布局（02 §11.2；01 §4.10）。
struct ReadingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ReadingWidgetEntry

    var body: some View {
        content
            .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch entry.content {
        case .needsSetup:
            WidgetMessageView(message: AppText.E.widgetNeedsSetup)
        case .snapshot(let snapshot):
            if family == .systemMedium {
                mediumLayout(snapshot)
            } else {
                smallLayout(snapshot)
            }
        }
    }

    @ViewBuilder
    private func smallLayout(_ snapshot: WidgetSnapshot) -> some View {
        if let book = snapshot.book {
            ContinueReadingSection(book: book)
                .widgetURL(DeepLink.book(book.id).url)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(AppText.T.a11yWidgetOpenBook(title: book.title))
        } else {
            ContinueReadingSection(book: nil)
        }
    }

    private func mediumLayout(_ snapshot: WidgetSnapshot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            bookArea(snapshot.book)
            Divider()
            cardArea(snapshot.latestCard, needsChineseCount: snapshot.cardsNeedingChineseCount)
        }
    }

    @ViewBuilder
    private func bookArea(_ book: WidgetBookSummary?) -> some View {
        if let book {
            Link(destination: DeepLink.book(book.id).url) {
                ContinueReadingSection(book: book)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(AppText.T.a11yWidgetOpenBook(title: book.title))
        } else {
            ContinueReadingSection(book: nil)
        }
    }

    @ViewBuilder
    private func cardArea(_ card: WidgetCardSummary?, needsChineseCount: Int) -> some View {
        if let card {
            Link(destination: DeepLink.card(card.id).url) {
                LatestCardSection(card: card, needsChineseCount: needsChineseCount)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(AppText.T.a11yWidgetOpenCard(word: card.word))
        } else {
            LatestCardSection(card: nil, needsChineseCount: needsChineseCount)
        }
    }
}

/// small 全部 / medium 左半区：继续阅读。book 为 nil 时是空书库状态。
struct ContinueReadingSection: View {
    let book: WidgetBookSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let book {
                Text(AppText.T.widgetContinueReading)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(book.title)
                    .font(.headline)
                    .lineLimit(3)
                Spacer(minLength: 0)
                Text(AppText.T.widgetProgress(percent: book.progressPercent))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(min(max(book.progressPercent, 0), 100)), total: 100)
                    .progressViewStyle(.linear)
            } else {
                Image(systemName: "books.vertical")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(AppText.T.widgetEmpty)
                    .font(.subheadline)
                    .lineLimit(4)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// medium 右半区：最新词卡或 “No Word Cards Yet”。
struct LatestCardSection: View {
    let card: WidgetCardSummary?
    let needsChineseCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let card {
                Text(AppText.T.widgetLatestCard)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(card.word)
                    .font(.headline)
                    .lineLimit(2)
                Text(card.meaning)
                    .font(.subheadline)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Text(AppText.T.widgetNeedsChinese(count: needsChineseCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(AppText.T.widgetNoCard)
                    .font(.headline)
                Text(AppText.T.widgetNoCardHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 未就绪状态：两种尺寸都只显示一句话（E-WIDGET-NEEDS-SETUP）。
struct WidgetMessageView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "book.closed")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .lineLimit(4)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
