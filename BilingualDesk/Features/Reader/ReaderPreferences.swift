// File: BilingualDesk/Features/Reader/ReaderPreferences.swift
// Targets: App
import SwiftUI
import Combine

/// 阅读主题：System / Light / Dark（跟随系统 / 日间 / 夜间，01 §4.5）。
enum ReadingTheme: String, CaseIterable, Identifiable, Sendable {
    case system
    case day
    case night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return AppText.T.settingsThemeSystem
        case .day: return AppText.T.settingsThemeDay
        case .night: return AppText.T.settingsThemeNight
        }
    }

    /// nil = System（跟随系统）。
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .day: return .light
        case .night: return .dark
        }
    }
}

/// 全 App 共用的阅读偏好，存在 App 私有的 UserDefaults（不进 Core Data，也不进 App Group）。
@MainActor
final class ReaderPreferences: ObservableObject {
    static let minimumEnglishFontSize: Double = 16
    static let maximumEnglishFontSize: Double = 28
    static let defaultEnglishFontSize: Double = 19
    static let chineseFontOffset: Double = 3
    static let minimumChineseFontSize: Double = 14

    private enum Key {
        static let englishFontSize = "reader.englishFontSize"
        static let theme = "reader.theme"
        static let speechRate = "reader.speechRate"
    }

    private let defaults: UserDefaults

    @Published var englishFontSize: Double {
        didSet {
            let clamped = Self.clampedEnglishFontSize(englishFontSize)
            if clamped != englishFontSize {
                englishFontSize = clamped
            }
            defaults.set(clamped, forKey: Key.englishFontSize)
        }
    }

    @Published var theme: ReadingTheme {
        didSet { defaults.set(theme.rawValue, forKey: Key.theme) }
    }

    @Published var speechRate: SpeechRate {
        didSet { defaults.set(speechRate.rawValue, forKey: Key.speechRate) }
    }

    /// 中文字号 = 英文 − 3，最低 14。
    var chineseFontSize: Double {
        max(Self.minimumChineseFontSize, englishFontSize - Self.chineseFontOffset)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.object(forKey: Key.englishFontSize) as? Double {
            englishFontSize = Self.clampedEnglishFontSize(stored)
        } else {
            englishFontSize = Self.defaultEnglishFontSize
        }
        theme = ReadingTheme(rawValue: defaults.string(forKey: Key.theme) ?? "") ?? .system
        speechRate = SpeechRate(rawValue: defaults.string(forKey: Key.speechRate) ?? "") ?? .normal
    }

    private static func clampedEnglishFontSize(_ value: Double) -> Double {
        guard value.isFinite else { return defaultEnglishFontSize }
        return min(max(value.rounded(), minimumEnglishFontSize), maximumEnglishFontSize)
    }
}
