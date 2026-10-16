// File: BilingualDesk/App/BilingualDeskApp.swift
// Targets: App
import SwiftUI

/// App 入口（02 §9.12 F54）。单元测试宿主里跳过真实启动。
@main
struct BilingualDeskApp: App {
    @StateObject private var container = AppContainer()

    /// XCTest 启动宿主 App 时会设置这个环境变量。
    static let isRunningUnitTests: Bool =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    var body: some Scene {
        WindowGroup {
            if Self.isRunningUnitTests {
                Color.clear
            } else {
                RootView(container: container)
            }
        }
    }
}
