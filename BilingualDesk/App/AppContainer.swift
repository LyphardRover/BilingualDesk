// File: BilingualDesk/App/AppContainer.swift
// Targets: App
import Foundation
import Combine

/// 组合根：启动、依赖装配、场景阶段、深链启用（02 §9.12 F52）。
@MainActor
final class AppContainer: ObservableObject {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)                                       // E-APP-STORE-FAILED
    }

    @Published private(set) var phase: Phase = .loading
    let router: AppRouter
    let preferences: ReaderPreferences
    let inboxMonitor: ShareInboxMonitor
    private(set) var dependencies: AppDependencies?

    private let sharedContainer: AppGroupContainer?
    private let speechPlayer: SpeechPlayer
    private let translator: AppleTranslationProvider
    private var widgetPublisher: WidgetSnapshotPublisher?
    private var isStarting = false

    /// 只创建不碰 Core Data 的对象（单元测试宿主里被创建也无害）。
    init() {
        let router = AppRouter()
        self.router = router
        preferences = ReaderPreferences()
        sharedContainer = AppGroupContainer.make()
        inboxMonitor = ShareInboxMonitor(container: sharedContainer)
        // 音频会话在后台队列上激活，失败时用全局 Alert 显示 E-SPEECH-AUDIO-UNAVAILABLE（SV-5）。
        speechPlayer = SpeechPlayer(reportError: { error in router.showAlert(error.message) })
        translator = AppleTranslationProvider()
    }

    func start() async {
        guard dependencies == nil, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        phase = .loading

        let stack: CoreDataStack
        do {
            stack = try await CoreDataStack.load(inMemory: false)
        } catch {
            #if DEBUG
            print("AppContainer: store failed to load: \(error)")
            #endif
            phase = .failed(AppText.E.appStoreFailed)
            return
        }

        let books = CoreDataBookRepository(stack: stack)
        let vocabulary = CoreDataVocabularyRepository(stack: stack)
        let publisher = WidgetSnapshotPublisher(books: books, vocabulary: vocabulary, container: sharedContainer)
        let hintRunner = VocabularyHintRunner(
            generateHint: GenerateVocabularyHint(vocabulary: vocabulary, translator: translator, widget: publisher),
            hintFinished: { [router] in router.vocabularyHintFinished() }
        )
        let dependencies = AppDependencies(
            books: books,
            vocabulary: vocabulary,
            parser: FoundationTXTParser(),
            translator: translator,
            speech: speechPlayer,
            widget: publisher,
            hints: hintRunner,
            preferences: preferences,
            router: router
        )
        widgetPublisher = publisher
        self.dependencies = dependencies
        phase = .ready

        // 冷启动时收到的深链在这里才处理（DL-4）。返回 false = 目标已不存在；抛错 = 查询失败。
        router.enableDeepLinks { link in
            switch link {
            case .book(let bookID):
                return try await books.book(id: bookID) != nil
            case .card(let cardID):
                return try await vocabulary.card(id: cardID) != nil
            }
        }
        inboxMonitor.refresh()
        await publisher.publish()                                 // P1：App 启动完成
    }

    func sceneDidBecomeActive() {
        inboxMonitor.refresh()
        dependencies?.activeReader?.becomeActive()
    }

    func sceneDidEnterBackground() async {
        // 阅读页先停朗读、取消翻译、保存位置并发布 Widget（RD-8、P8），再保证朗读器停下（C10）。
        await dependencies?.activeReader?.enterBackground()
        speechPlayer.stop()
    }
}
