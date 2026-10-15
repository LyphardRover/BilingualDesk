// File: BilingualDesk/Features/Reader/ReaderSettingsView.swift
// Targets: App
import SwiftUI

/// 阅读设置 sheet：显示模式（按书，存数据库）+ 字号、主题、语速（全 App，存 UserDefaults）。
struct ReaderSettingsView: View {
    @ObservedObject private var preferences: ReaderPreferences
    @State private var mode: BilingualMode
    private let onBilingualModeChange: (BilingualMode) -> Void
    @Environment(\.dismiss) private var dismiss

    init(preferences: ReaderPreferences, bilingualMode: BilingualMode, onBilingualModeChange: @escaping (BilingualMode) -> Void) {
        self._preferences = ObservedObject(wrappedValue: preferences)
        self._mode = State(initialValue: bilingualMode)
        self.onBilingualModeChange = onBilingualModeChange
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(AppText.T.settingsMode, selection: $mode) {
                        ForEach(BilingualMode.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text(AppText.T.settingsMode)
                } footer: {
                    Text(AppText.T.settingsModeFootnote)
                }

                Section {
                    Text(AppText.T.settingsFontValue(
                        en: Int(preferences.englishFontSize.rounded()),
                        zh: Int(preferences.chineseFontSize.rounded())
                    ))
                    Slider(
                        value: $preferences.englishFontSize,
                        in: ReaderPreferences.minimumEnglishFontSize...ReaderPreferences.maximumEnglishFontSize,
                        step: 1
                    ) {
                        Text(AppText.T.settingsFont)
                    }
                } header: {
                    Text(AppText.T.settingsFont)
                }

                Section {
                    Picker(AppText.T.settingsTheme, selection: $preferences.theme) {
                        ForEach(ReadingTheme.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text(AppText.T.settingsTheme)
                }

                Section {
                    Picker(AppText.T.settingsRate, selection: $preferences.speechRate) {
                        ForEach(SpeechRate.allCases) { rate in
                            Text(rate.title).tag(rate)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text(AppText.T.settingsRate)
                }
            }
            .navigationTitle(AppText.T.settingsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppText.T.commonDone) { dismiss() }
                }
            }
            .onChange(of: mode) { _, newMode in
                onBilingualModeChange(newMode)
            }
        }
    }
}
