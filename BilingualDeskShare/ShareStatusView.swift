// File: BilingualDeskShare/ShareStatusView.swift
// Targets: Share
import SwiftUI
import Combine

/// Share 扩展的三种界面状态（01 §4.9）。
enum ShareStatus: Equatable {
    case saving
    case saved
    case failed(String)
}

/// ShareViewController 写入状态，ShareStatusView 观察它（02 §9.11 F48）。
@MainActor
final class ShareStatusModel: ObservableObject {
    @Published var status: ShareStatus

    init() {
        status = .saving
    }
}

/// 居中卡片：标题 “BilingualDesk” + 状态文字 + 一个按钮。
struct ShareStatusView: View {
    @ObservedObject var model: ShareStatusModel
    let onCancel: () -> Void
    let onDone: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(AppText.T.appName)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            statusContent
        }
        .padding(24)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.default, value: model.status)
    }

    @ViewBuilder
    private var statusContent: some View {
        switch model.status {
        case .saving:
            ProgressView()
            Text(AppText.T.shareSaving)
                .multilineTextAlignment(.center)
            actionButton(AppText.T.commonCancel, isProminent: false, action: onCancel)
        case .saved:
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(AppText.T.shareSaved)
                .multilineTextAlignment(.center)
            actionButton(AppText.T.commonDone, isProminent: true, action: onDone)
        case .failed(let message):
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .multilineTextAlignment(.center)
            actionButton(AppText.T.commonClose, isProminent: false, action: onClose)
        }
    }

    @ViewBuilder
    private func actionButton(_ title: String, isProminent: Bool, action: @escaping () -> Void) -> some View {
        if isProminent {
            Button(action: action) {
                Text(title).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button(action: action) {
                Text(title).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
    }
}
