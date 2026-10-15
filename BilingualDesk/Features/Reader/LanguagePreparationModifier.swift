// File: BilingualDesk/Features/Reader/LanguagePreparationModifier.swift
// Targets: App
import SwiftUI
// TranslationSession 没有标 Sendable；@preconcurrency 让 complete 并发检查不对下面的 session 报 sending 警告（07 §5.4）。
@preconcurrency import Translation

/// 唯一的 `.translationTask` 宿主（C6）：读者点 “Prepare English–Chinese Translation” 后，由系统弹出语言下载确认。
/// 这里拿到的 session 只用来调用 prepareTranslation()，不保存、不传出；真正的翻译在 06 的 AppleTranslationProvider。
struct LanguagePreparationModifier: ViewModifier {
    @Binding var isRequested: Bool
    let onFinished: @MainActor (Bool) -> Void
    @State private var configuration: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        content
            .onChange(of: isRequested, initial: true) { _, requested in
                guard requested else { return }
                if configuration == nil {
                    // Locale.Language 必须用 identifier 构造，不能直接写字符串字面量。
                    configuration = TranslationSession.Configuration(
                        source: Locale.Language(identifier: "en"),
                        target: Locale.Language(identifier: "zh-Hans")
                    )
                } else {
                    // 已有配置时 invalidate() 让 translationTask 再执行一次。
                    configuration?.invalidate()
                }
            }
            .translationTask(configuration) { session in
                let success: Bool
                do {
                    try await session.prepareTranslation()
                    success = true
                } catch {
                    // 读者取消下载、没有联网，都算失败（E-TR-PREPARE-FAILED）。
                    success = false
                }
                await MainActor.run {
                    isRequested = false
                    onFinished(success)
                }
            }
    }
}

extension View {
    func englishChineseLanguagePreparation(isRequested: Binding<Bool>, onFinished: @escaping @MainActor (Bool) -> Void) -> some View {
        modifier(LanguagePreparationModifier(isRequested: isRequested, onFinished: onFinished))
    }
}
