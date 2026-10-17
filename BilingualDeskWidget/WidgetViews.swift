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
                WidgetHeadline(text: book.title, lineLimit: 3)
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
                WidgetHeadline(text: card.word, lineLimit: 2)
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

/// 书名、单词的 headline：最宽的词放得下就照常换行（最多 lineLimit 行）；
/// 放不下（例如没有空格的长文件名）就改为一行并缩小，不在词中间断开。
/// 只加 minimumScaleFactor 不够：允许多行时文字会先在词中间断行，根本不会缩小。
struct WidgetHeadline: View {
    let text: String
    let lineLimit: Int

    /// 用系统分词，不按空格切：中文书名会切成一个个词，照常换行；没有空格的英文长文件名仍是一个词。
    private var words: [String] {
        var result: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { word, _, _, _ in
            if let word { result.append(word) }
        }
        return result.isEmpty ? [text] : result
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            // 理想宽度 = 最宽那个词的宽度（逐个量，不按字数猜）：它放得下才用这一种
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(words.indices, id: \.self) { index in
                        Text(words[index]).font(.headline).lineLimit(1).fixedSize()
                    }
                }
                .frame(height: 0)   // 只用来量宽度，不占高度
                .hidden()
                Text(text).font(.headline).lineLimit(lineLimit)
                    .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            Text(text).font(.headline).lineLimit(1).minimumScaleFactor(0.5)
        }
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
