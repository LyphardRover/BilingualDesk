// File: BilingualDesk/App/AppRouter.swift
// Targets: App
import Foundation
import Combine

enum AppTab: Hashable {
    case library
    case vocabulary
}

enum LibraryRoute: Hashable {
    case reader(bookID: UUID, startOrder: Int?)
}

enum VocabularyRoute: Hashable {
    case card(UUID)
}

/// 全 App 唯一的导航状态：当前标签、两个导航栈、书库 sheet、全局 Alert 和待处理的深链（02 §9.1、§12）。
@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedTab: AppTab = .library
    @Published var libraryPath: [LibraryRoute] = []
    @Published var vocabularyPath: [VocabularyRoute] = [] {
        didSet {
            // 单词本栈被清空 = 词卡详情已经不在屏幕上，未保存标记随之失效。
            if vocabularyPath.isEmpty && hasUnsavedCardDraft {
                hasUnsavedCardDraft = false
            }
        }
    }
    @Published var importCandidate: ImportCandidate?
    @Published var isInboxPresented: Bool = false
    @Published var alertMessage: String?
    @Published var hasUnsavedCardDraft: Bool = false {
        didSet {
            // 未保存内容被保存、放弃或离开详情页之后，处理挂起的深链。
            if oldValue && !hasUnsavedCardDraft {
                processPendingDeepLink()
            }
        }
    }
    /// 阅读页离开并保存阅读位置后加 1。返回书库时立即做的那次读取可能早于保存完成，书库据此再读一次进度。
    @Published private(set) var readingPositionRevision = 0
    private(set) var pendingDeepLink: DeepLink?

    private var targetExists: (@MainActor (DeepLink) async throws -> Bool)?
    private var isHandlingDeepLink = false

    init() {}

    /// 切到书库标签并打开阅读页。栈里最多一个阅读页：打开另一本书 = 替换整个栈（01 §5.1）。
    func openBook(_ bookID: UUID, startOrder: Int?) {
        selectedTab = .library
        libraryPath = [.reader(bookID: bookID, startOrder: startOrder)]
    }

    /// 切到单词本标签并打开词卡。有未保存的 “My Meaning” 时不替换栈，停在那张词卡上（01 §4.7）。
    func openCard(_ cardID: UUID) {
        selectedTab = .vocabulary
        guard !hasUnsavedCardDraft else { return }
        vocabularyPath = [.card(cardID)]
    }

    /// 阅读页保存完阅读位置后调用（ReaderViewModel.leave）。
    func readingPositionSaved() {
        readingPositionRevision += 1
    }

    func showAlert(_ message: String) {
        alertMessage = message
    }

    /// 冷启动与运行中的唯一入口（DL-4）。解析失败直接忽略；成功则覆盖挂起的链接并尝试处理。
    func receive(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        pendingDeepLink = link
        processPendingDeepLink()
    }

    /// 数据库就绪后由 AppContainer 调用一次（06），之后挂起的链接才会被处理。
    func enableDeepLinks(targetExists: @escaping @MainActor (DeepLink) async throws -> Bool) {
        self.targetExists = targetExists
        processPendingDeepLink()
    }

    // MARK: - 私有

    private func processPendingDeepLink() {
        guard let targetExists, !isHandlingDeepLink, let link = pendingDeepLink else { return }
        if hasUnsavedCardDraft {
            // 先让读者看到那张未保存的词卡；链接等保存、放弃或离开详情页后再处理。
            selectedTab = .vocabulary
            return
        }
        pendingDeepLink = nil
        isHandlingDeepLink = true
        Task { @MainActor [weak self] in
            let result: Result<Bool, any Error>
            do {
                result = .success(try await targetExists(link))
            } catch {
                result = .failure(error)
            }
            guard let self else { return }
            self.finishHandling(link, result: result)
        }
    }

    private func finishHandling(_ link: DeepLink, result: Result<Bool, any Error>) {
        defer {
            isHandlingDeepLink = false
            // 处理期间又收到新链接时，再检查一次。
            processPendingDeepLink()
        }
        switch result {
        case .failure:
            showAlert(AppText.E.linkLookupFailed)
        case .success(true):
            importCandidate = nil
            isInboxPresented = false
            switch link {
            case .book(let bookID):
                openBook(bookID, startOrder: nil)
            case .card(let cardID):
                openCard(cardID)
            }
        case .success(false):
            switch link {
            case .book:
                selectedTab = .library
                libraryPath = []
                showAlert(AppText.E.bookGone)
            case .card:
                selectedTab = .vocabulary
                vocabularyPath = []
                showAlert(AppText.E.cardGone)
            }
        }
    }
}
