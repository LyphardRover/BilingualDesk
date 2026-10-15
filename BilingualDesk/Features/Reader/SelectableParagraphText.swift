// File: BilingualDesk/Features/Reader/SelectableParagraphText.swift
// Targets: App
import SwiftUI
import UIKit

/// 选词菜单里的三个自定义动作。
enum SelectionAction: Sendable {
    case lookUp
    case collect
    case pronounce
}

/// 只读、可选择的英文段落。用 UITextView 是因为 SwiftUI Text 不能给选区加自定义菜单（02 §9.5）。
struct SelectableParagraphText: UIViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let isHeading: Bool
    /// (动作, 段内 UTF-16 选区, 选中的原始文字)
    let onSelectionAction: (SelectionAction, NSRange, String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        // 明确使用 TextKit 2；之后不要访问 layoutManager，否则会退回 TextKit 1。
        let textView = UITextView(usingTextLayoutManager: true)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.dataDetectorTypes = []
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        // 正文字号由 Reading Settings 控制，不叠加动态字体（01 §7 第 2 条）。
        textView.adjustsFontForContentSizeCategory = false
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.delegate = context.coordinator
        context.coordinator.applyContent(to: textView)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyContentIfNeeded(to: uiView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width.isFinite else { return nil }
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fitting.height))
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SelectableParagraphText
        private var appliedText: String?
        private var appliedFontSize: CGFloat?
        private var appliedIsHeading: Bool?

        init(parent: SelectableParagraphText) {
            self.parent = parent
        }

        /// 系统编辑菜单：最前面是 “Define” “Save Word” “Pronounce”，后面保留系统建议项（Copy 等）。
        func textView(_ textView: UITextView, editMenuForTextInRanges ranges: [NSValue], suggestedActions: [UIMenuElement]) -> UIMenu? {
            let selected = ranges.map(\.rangeValue).filter { $0.location != NSNotFound && $0.length > 0 }
            // 没有选中内容（或多段选区）时返回 nil = 使用系统默认菜单。
            guard selected.count == 1 else { return nil }
            let range = selected[0]
            let fullText = parent.text
            guard let swiftRange = Range(range, in: fullText) else { return nil }
            let selectedText = String(fullText[swiftRange])
            let handler = parent.onSelectionAction

            let lookUp = UIAction(title: AppText.T.readerMenuLookup, image: UIImage(systemName: "character.book.closed")) { _ in
                handler(.lookUp, range, selectedText)
            }
            let collect = UIAction(title: AppText.T.readerMenuCollect, image: UIImage(systemName: "star")) { _ in
                handler(.collect, range, selectedText)
            }
            let pronounce = UIAction(title: AppText.T.readerMenuPronounce, image: UIImage(systemName: "speaker.wave.2")) { _ in
                handler(.pronounce, range, selectedText)
            }
            let custom = UIMenu(title: "", options: .displayInline, children: [lookUp, collect, pronounce])
            return UIMenu(children: [custom] + suggestedActions)
        }

        /// 选区清空后，补上选择期间被推迟的字号变化。
        func textViewDidChangeSelection(_ textView: UITextView) {
            guard textView.selectedRange.length == 0 else { return }
            applyContentIfNeeded(to: textView)
        }

        /// 文本变了（列表复用）→ 必须重设；只是字号/标题样式变了 → 有选区时推迟，避免打断选择。
        func applyContentIfNeeded(to textView: UITextView) {
            if appliedText != parent.text {
                applyContent(to: textView)
                return
            }
            guard appliedFontSize != parent.fontSize || appliedIsHeading != parent.isHeading else { return }
            guard textView.selectedRange.length == 0 else { return }
            applyContent(to: textView)
            textView.invalidateIntrinsicContentSize()
        }

        func applyContent(to textView: UITextView) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: Self.font(size: parent.isHeading ? parent.fontSize + 3 : parent.fontSize, bold: parent.isHeading),
                .foregroundColor: UIColor.label
            ]
            textView.attributedText = NSAttributedString(string: parent.text, attributes: attributes)
            textView.accessibilityTraits = parent.isHeading ? [.header, .staticText] : [.staticText]
            appliedText = parent.text
            appliedFontSize = parent.fontSize
            appliedIsHeading = parent.isHeading
        }

        /// Georgia；设备没有时用系统 serif。章节标题加粗。
        private static func font(size: CGFloat, bold: Bool) -> UIFont {
            if let georgia = UIFont(name: bold ? "Georgia-Bold" : "Georgia", size: size) {
                return georgia
            }
            let system = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
            if let serif = system.fontDescriptor.withDesign(.serif) {
                return UIFont(descriptor: serif, size: size)
            }
            return system
        }
    }
}

/// 系统词典页（“Define” 且系统词典有该词时弹出）。
struct DictionarySheet: UIViewControllerRepresentable {
    let term: String

    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: term)
    }

    func updateUIViewController(_ uiViewController: UIReferenceLibraryViewController, context: Context) {}
}
