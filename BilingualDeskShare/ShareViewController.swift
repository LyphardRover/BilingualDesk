// File: BilingualDeskShare/ShareViewController.swift
// Targets: Share
import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Share 扩展失败的原因（02 §9.11、§14）。
enum ShareFailure: Error, Equatable {
    case noFile                // E-SHARE-NO-FILE
    case loadFailed            // E-SHARE-LOAD-FAILED
    case appGroupUnavailable   // E-SHARE-APPGROUP
    case tooLarge              // E-SHARE-TOO-LARGE
    case emptyFile             // E-SHARE-EMPTY-FILE
    case writeFailed           // E-SHARE-WRITE-FAILED

    var message: String {
        switch self {
        case .noFile:
            return AppText.E.shareNoFile
        case .loadFailed:
            return AppText.E.shareLoadFailed
        case .appGroupUnavailable:
            return AppText.E.shareAppgroup
        case .tooLarge:
            return AppText.E.shareTooLarge
        case .emptyFile:
            return AppText.E.shareEmptyFile
        case .writeFailed:
            return AppText.E.shareWriteFailed
        }
    }
}

/// Share 扩展入口：取纯文本文件 → 写进 App Group 收件箱 → complete / cancel（02 §9.11 F49；§13 C8）。
final class ShareViewController: UIViewController {
    private lazy var statusModel = ShareStatusModel()
    private var loadProgress: Progress?
    private var hasFinishedRequest = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        embedStatusView()
        saveSharedFileToInbox()
    }

    // MARK: 界面

    private func embedStatusView() {
        let statusView = ShareStatusView(
            model: statusModel,
            onCancel: { [weak self] in self?.cancelRequest() },
            onDone: { [weak self] in self?.completeRequest() },
            onClose: { [weak self] in self?.cancelRequest() }
        )
        let hostingController = UIHostingController(rootView: statusView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hostingController)
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
    }

    // MARK: 保存

    private func saveSharedFileToInbox() {
        guard let container = AppGroupContainer.make() else {
            showFailure(.appGroupUnavailable)
            return
        }

        let extensionItems = (extensionContext?.inputItems ?? []).compactMap { $0 as? NSExtensionItem }
        let attachments = extensionItems.flatMap { $0.attachments ?? [] }
        let plainTextProviders = attachments.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
        }
        guard plainTextProviders.count == 1, let provider = plainTextProviders.first else {
            showFailure(.noFile)
            return
        }

        // 「文件」App 共享时 suggestedName 常为 nil，文件名要等拿到临时文件后再定（见 inboxFileName）。
        let suggestedName = provider.suggestedName
        let isFile = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        loadProgress = Self.copyPlainTextFile(from: provider, into: container, suggestedName: suggestedName, isFile: isFile) { [weak self] result in
            Task { @MainActor in
                self?.showResult(result)
            }
        }
    }

    /// 在 loadFileRepresentation 的完成回调里同步复制（临时文件在回调返回后就会被删除）。
    /// nonisolated：回调运行在系统后台线程，不属于主 actor。
    private nonisolated static func copyPlainTextFile(
        from provider: NSItemProvider,
        into container: AppGroupContainer,
        suggestedName: String?,
        isFile: Bool,
        completion: @escaping @Sendable (Result<InboxItem, ShareFailure>) -> Void
    ) -> Progress {
        provider.loadFileRepresentation(forTypeIdentifier: UTType.plainText.identifier) { url, error in
            guard let url, error == nil else {
                completion(.failure(.loadFailed))
                return
            }
            do {
                let item = try container.addToInbox(
                    copyingFileAt: url,
                    originalFileName: inboxFileName(suggestedName: suggestedName, fileURL: isFile ? url : nil),
                    receivedAt: Date()
                )
                completion(.success(item))
            } catch AppGroupError.fileTooLarge {
                completion(.failure(.tooLarge))
            } catch AppGroupError.fileEmpty {
                completion(.failure(.emptyFile))
            } catch {
                completion(.failure(.writeFailed))
            }
        }
    }

    /// 待导入文件名：suggestedName → 共享的是文件时用临时副本的文件名（系统保留原文件名）
    /// → 都没有（例如从备忘录共享的文字）时用 T-SHARE-DEFAULT-FILE-NAME（01 §4.9）。
    private nonisolated static func inboxFileName(suggestedName: String?, fileURL: URL?) -> String {
        let suggested = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !suggested.isEmpty { return suggested }
        let fromFile = fileURL?.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return fromFile.isEmpty ? AppText.T.shareDefaultFileName : fromFile
    }

    private func showResult(_ result: Result<InboxItem, ShareFailure>) {
        guard !hasFinishedRequest else { return }
        switch result {
        case .success:
            statusModel.status = .saved
        case .failure(let failure):
            showFailure(failure)
        }
    }

    private func showFailure(_ failure: ShareFailure) {
        guard !hasFinishedRequest else { return }
        statusModel.status = .failed(failure.message)
    }

    // MARK: 结束请求（每个请求只结束一次）

    private func completeRequest() {
        guard !hasFinishedRequest else { return }
        hasFinishedRequest = true
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func cancelRequest() {
        guard !hasFinishedRequest else { return }
        hasFinishedRequest = true
        loadProgress?.cancel()
        extensionContext?.cancelRequest(withError: NSError(domain: "BilingualDeskShare", code: NSUserCancelledError))
    }
}
