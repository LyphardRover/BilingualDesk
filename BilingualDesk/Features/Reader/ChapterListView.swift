// File: BilingualDesk/Features/Reader/ChapterListView.swift
// Targets: App
import SwiftUI

/// 目录 sheet（页面四）。章节列表已由 ReaderViewModel 按 RD-2 补好 “Full Text” / “Beginning”，这里只负责显示和回调。
struct ChapterListView: View {
    private let chapters: [ReadingChapter]
    private let onSelect: (ReadingChapter) -> Void
    @Environment(\.dismiss) private var dismiss

    init(chapters: [ReadingChapter], onSelect: @escaping (ReadingChapter) -> Void) {
        self.chapters = chapters
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            List(chapters) { chapter in
                Button {
                    onSelect(chapter)
                } label: {
                    Text(chapter.title)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
            }
            .navigationTitle(AppText.T.tocTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppText.T.commonDone) { dismiss() }
                }
            }
        }
    }
}
