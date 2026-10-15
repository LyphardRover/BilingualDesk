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
            // 正在朗读的段：除了浅蓝背景，还给出无障碍值 “Reading aloud”（01 §7 第 4 条）。
            .accessibilityValue(isBeingReadAloud ? AppText.T.a11yReadingNow : "")

            // 章节标题行永不翻译；“English Only” 模式下中文行不存在。
            if mode == .bilingual && !paragraph.isChapterHeading {
                translationLine
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowBackground(isBeingReadAloud ? Color.accentColor.opacity(0.15) : Color.clear)
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
