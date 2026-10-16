// File: BilingualDesk/App/RootView.swift
// Targets: App
import SwiftUI

/// 启动 / 失败 / 就绪三态 + 深链入口 + 场景阶段（02 §9.12 F53；01 §4.11）。
struct RootView: View {
    @ObservedObject var container: AppContainer
    @Environment(\.scenePhase) private var scenePhase

    init(container: AppContainer) {
        _container = ObservedObject(wrappedValue: container)
    }

    var body: some View {
        content
            .task {
                await container.start()
            }
            .onOpenURL { url in
                container.router.receive(url)
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    container.sceneDidBecomeActive()
                case .background:
                    Task {
                        await container.sceneDidEnterBackground()
                    }
                default:
                    break
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch container.phase {
        case .loading:
            ProgressView(AppText.T.appLoading)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 20) {
                Text(message)
                    .font(.body)
                    .multilineTextAlignment(.center)
                Button {
                    Task {
                        await container.start()
                    }
                } label: {
                    Text(AppText.T.commonRetry)
                        .frame(minWidth: 120, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            if let dependencies = container.dependencies {
                MainTabsView(dependencies: dependencies, monitor: container.inboxMonitor)
            } else {
                ProgressView(AppText.T.appLoading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// 两个标签 + 待导入 sheet + 全局 Alert + 主题（02 §9.12；01 §4.11、§5.1）。
struct MainTabsView: View {
    private let dependencies: AppDependencies
    @ObservedObject private var router: AppRouter
    @ObservedObject private var monitor: ShareInboxMonitor
    @ObservedObject private var preferences: ReaderPreferences

    init(dependencies: AppDependencies, monitor: ShareInboxMonitor) {
        self.dependencies = dependencies
        _router = ObservedObject(wrappedValue: dependencies.router)
        _monitor = ObservedObject(wrappedValue: monitor)
        _preferences = ObservedObject(wrappedValue: dependencies.preferences)
    }

    var body: some View {
        TabView(selection: $router.selectedTab) {
            Tab(AppText.T.tabLibrary, systemImage: "books.vertical", value: AppTab.library) {
                LibraryView(dependencies: dependencies, inboxBanner: monitor.bannerState)
            }
            Tab(AppText.T.tabVocabulary, systemImage: "character.book.closed", value: AppTab.vocabulary) {
                VocabularyListView(dependencies: dependencies)
            }
        }
        .sheet(isPresented: $router.isInboxPresented, onDismiss: {
            monitor.refresh()
        }) {
            InboxView(monitor: monitor, dependencies: dependencies)
        }
        .alert(router.alertMessage ?? "", isPresented: alertBinding) {
            Button(AppText.T.commonOk, role: .cancel) {}
        }
        .preferredColorScheme(preferences.theme.colorScheme)
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { router.alertMessage != nil },
            set: { isPresented in
                if !isPresented && router.alertMessage != nil { router.alertMessage = nil }
            }
        )
    }
}
