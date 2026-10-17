// File: BilingualDesk/Features/Reader/ParagraphRow.swift
// Targets: App
import SwiftUI

/// 阅读列表的一行：一段可选择的英文 + （双语模式下）段下中文行。
struct ParagraphRow: View {
    let paragraph: ReadingParagraph
    let mode: BilingualMode
    let translationState: ParagraphTranslationState
    let englishFontSize: Double
    let chineseFontSize: Double
    let isBeingReadAloud: Bool
    /// 朗读暂停在这一段：保留浅蓝背景，标出 “Resume” 从哪里接着读。
    let isReadAloudPaused: Bool
    let onSelection: (SelectionAction, ParagraphSelection) -> Void
    let onRetryTranslation: () -> Void
    let onPrepareLanguage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SelectableParagraphText(
                text: paragraph.text,
                fontSize: CGFloat(englishFontSize),
                isHeading: paragraph.isChapterHeading,
                onSelectionAction: { action, range, selectedText in
                    onSelection(action, ParagraphSelection(
                        bookID: paragraph.bookID,
                        paragraphID: paragraph.id,
                        paragraphOrder: paragraph.order,
                        location: range.location,
                        length: range.length,
                        selectedText: selectedText
                    ))
                }
            )
            // 朗读段除了浅蓝背景，还给出无障碍值：正在读 “Reading aloud”，暂停 “Paused at paragraph N”（01 §7 第 4 条）。
            .accessibilityValue(readAloudAccessibilityValue)

            // 章节标题行永不翻译；“English Only” 模式下中文行不存在。
            if mode == .bilingual && !paragraph.isChapterHeading {
                translationLine
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowBackground((isBeingReadAloud || isReadAloudPaused) ? Color.accentColor.opacity(0.15) : Color.clear)
    }

    /// 正在朗读 → “Reading aloud”；暂停在这一段 → 与朗读栏同一句 “Paused at paragraph N”（段号从 1 数）。
    private var readAloudAccessibilityValue: String {
        if isBeingReadAloud { return AppText.T.a11yReadingNow }
        if isReadAloudPaused { return AppText.T.readerPausedStatus(order: paragraph.order + 1) }
        return ""
    }

    @ViewBuilder
    private var translationLine: some View {
        switch translationState {
        case .notRequested, .simulatorUnsupported, .languagePairUnsupported:
            // 不支持时段下不显示，阅读页顶部有提示条。
            EmptyView()
        case .waiting:
            Text(AppText.T.trWaiting)
                .font(.system(size: chineseFontSize))
                .foregroundStyle(.secondary)
        case .translating:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(AppText.T.trTranslating)
                    .font(.system(size: chineseFontSize))
                    .foregroundStyle(.secondary)
            }
        case .translated(let chinese):
            Text(chinese)
                .font(.system(size: chineseFontSize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(AppText.T.a11yTranslation(text: chinese))
        case .failed:
            VStack(alignment: .leading, spacing: 4) {
                Text(AppText.E.trFailed)
                    .font(.footnote)
                    .foregroundStyle(.red)
                Button(AppText.T.commonRetry, action: onRetryTranslation)
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
            }
        case .needsLanguage:
            VStack(alignment: .leading, spacing: 4) {
                Text(AppText.E.trNeedsLanguage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(AppText.T.trPrepare, action: onPrepareLanguage)
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
            }
        }
    }
}
