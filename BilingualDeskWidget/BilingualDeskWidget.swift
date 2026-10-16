// File: BilingualDeskWidget/BilingualDeskWidget.swift
// Targets: Widget
import WidgetKit
import SwiftUI

/// Widget 条目内容：读到的快照，或 “Open BilingualDesk once to finish setup”。
enum ReadingWidgetContent: Equatable {
    case snapshot(WidgetSnapshot)
    case needsSetup                                               // E-WIDGET-NEEDS-SETUP
}

struct ReadingWidgetEntry: TimelineEntry {
    let date: Date
    let content: ReadingWidgetContent
}

/// 只读 App Group 里的 WidgetSnapshot.json（02 §9.11、§11；§13 C9）。
struct ReadingWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReadingWidgetEntry {
        Self.sampleEntry
    }

    func getSnapshot(in context: Context, completion: @escaping (ReadingWidgetEntry) -> Void) {
        completion(context.isPreview ? Self.sampleEntry : Self.loadEntry(now: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReadingWidgetEntry>) -> Void) {
        // 只有一个条目、不自行安排下一次刷新：内容变化由主 App 发布快照后 reloadAllTimelines() 驱动。
        completion(Timeline(entries: [Self.loadEntry(now: Date())], policy: .never))
    }

    static func loadEntry(now: Date) -> ReadingWidgetEntry {
        guard
            let container = AppGroupContainer.make(),
            let snapshot = try? container.readWidgetSnapshot()
        else {
            return ReadingWidgetEntry(date: now, content: .needsSetup)
        }
        return ReadingWidgetEntry(date: now, content: .snapshot(snapshot))
    }

    /// 小组件库预览与占位用的示例（01 §4.10）；真实时间线不使用。
    static var sampleEntry: ReadingWidgetEntry {
        let snapshot = WidgetSnapshot(
            schemaVersion: SharedConfiguration.widgetSnapshotSchemaVersion,
            generatedAt: Date(),
            book: WidgetBookSummary(id: UUID(), title: AppText.T.widgetSampleTitle, progressPercent: 37),
            latestCard: WidgetCardSummary(
                id: UUID(),
                word: AppText.T.widgetSampleWord,
                meaning: AppText.T.widgetSampleMeaning
            ),
            cardsNeedingChineseCount: 2
        )
        return ReadingWidgetEntry(date: Date(), content: .snapshot(snapshot))
    }
}

/// “BilingualDesk” 小组件：small + medium，不可配置（02 §9.11）。
struct BilingualDeskReadingWidget: Widget {
    let kind: String = SharedConfiguration.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ReadingWidgetProvider()) { entry in
            ReadingWidgetView(entry: entry)
        }
        .configurationDisplayName(AppText.T.appName)
        .description(AppText.T.widgetDescription)
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct BilingualDeskWidgetBundle: WidgetBundle {
    var body: some Widget {
        BilingualDeskReadingWidget()
    }
}
