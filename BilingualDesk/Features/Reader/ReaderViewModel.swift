// File: BilingualDesk/Features/Reader/ReaderViewModel.swift
// Targets: App
import Foundation
import Combine
import UIKit

/// 阅读页顶部的收藏提示条。
struct ReaderBanner: Identifiable, Equatable {
    enum Kind: Equatable {
        case collected                                // T-READER-COLLECTED，2 秒
        case alreadyCollected(cardID: UUID)           // T-READER-ALREADY-COLLECTED，3 秒，可点
    }

    let id: UUID
    let kind: Kind

    var message: String {
        switch kind {
        case .collected: return AppText.T.readerCollected
        case .alreadyCollected: return AppText.T.readerAlreadyCollected
        }
    }

    fileprivate var displaySeconds: Int {
        switch kind {
        case .collected: return 2
        case .alreadyCollected: return 3
        }
    }
}

/// “Define” 且系统词典有该词时，用它弹出 DictionarySheet。
struct DictionaryLookup: Identifiable, Equatable {
    let id: UUID
    let term: String
}

/// 双语阅读页（页面三）的状态与动作（02 §9.5、§9.6 RD-1…RD-8）。
@MainActor
final class ReaderViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let bookID: UUID
    let translations: ParagraphTranslationCoordinator
    @Published private(set) var phase: Phase = .loading
    @Published private(set) var book: Book?
    @Published private(set) var paragraphs: [ReadingParagraph] = []
    @Published private(set) var chapters: [ReadingChapter] = []
    @Published private(set) var speechState: SpeechState
    @Published private(set) var isBookGone: Bool = false
    @Published var scrollTargetOrder: Int?
    @Published var banner: ReaderBanner?
    @Published var alertMessage: String?
    @Published var dictionaryLookup: DictionaryLookup?
    @Published var isLanguagePreparationRequested: Bool = false

    private let startOrder: Int?
    private let dependencies: AppDependencies
    private let recordPosition: RecordReadingPosition
    private let saveVocabularyCard: SaveVocabularyCard
    private var isLoadStarted = false
    /// 打开时的定位段：还没有任何段出现在屏幕上时，它就是「当前段」。
    private var openedAtOrder = 0
    /// 当前可见段的序号集合（RD-3）。List 会渲染导航栏下面被挡住的行，所以这里也包含它们（用于预取翻译）。
    private var visibleOrders: Set<Int> = []
    /// 整段被导航栏或顶部提示条挡住的段；「屏幕最上方的段」要排除它们。
    /// 记的是每行最后一次报告的状态，离开屏幕时不移除：onGeometryChange 只在值变化时回调，
    /// 一行在被挡住时离开、又在被挡住时回来（例如切换标签再回来），不会再报一次 true。
    /// 不在屏幕上的行不影响结果，因为计算时只从 visibleOrders 里减。
    private var coveredOrders: Set<Int> = []
    /// 最近一次「稳定」的可见最小段：在下一轮主线程循环才更新，
    /// 这样离开页面时一连串 onDisappear 把集合清空，也不会把位置记错。
    private var settledTopOrder: Int?
    private var isSettleScheduled = false
    private var bannerTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(bookID: UUID, startOrder: Int?, dependencies: AppDependencies) {
        self.bookID = bookID
        self.startOrder = startOrder
        self.dependencies = dependencies
        self.recordPosition = dependencies.makeRecordReadingPosition()
        self.saveVocabularyCard = dependencies.makeSaveVocabularyCard()
        self.translations = ParagraphTranslationCoordinator(translateParagraph: dependencies.makeTranslateParagraph())
        self.speechState = dependencies.speech.state

        // 段状态变化时让阅读页重新绘制。
        translations.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        // 朗读状态：先收到当前值，之后每次变化一次（SpeechPlaying 合同）。
        dependencies.speech.statePublisher
            .sink { [weak self] state in self?.speechStateChanged(state) }
            .store(in: &cancellables)
    }

    /// 屏幕最上方的段：没被挡住的可见段里序号最小的；没有时用最近一次稳定值，再没有就用打开时的定位段。
    var currentParagraphOrder: Int {
        topUncoveredOrder ?? settledTopOrder ?? openedAtOrder
    }

    private var topUncoveredOrder: Int? {
        visibleOrders.subtracting(coveredOrders).min()
    }

    // MARK: - 打开与可见段

    /// RD-1：只执行一次。切换标签回来时 .task 会再次触发，此时直接返回，不重读、不重新定位。
    func load() async {
        guard phase == .loading, !isLoadStarted else { return }
        isLoadStarted = true
        do {
            guard let loadedBook = try await dependencies.books.book(id: bookID) else {
                isBookGone = true
                return
            }
            let loadedParagraphs = try await dependencies.books.paragraphs(bookID: bookID)
            let foundChapters: [ReadingChapter]
            do {
                foundChapters = try await dependencies.books.chapters(bookID: bookID)
            } catch {
                foundChapters = []   // RD-2：目录读取失败同样只给 “Full Text”
            }
            book = loadedBook
            paragraphs = loadedParagraphs
            chapters = Self.tableOfContents(from: foundChapters)
            translations.seed(loadedParagraphs)
            try? await recordPosition.bookOpened(bookID: bookID)
            let target = Self.clamp(startOrder ?? loadedBook.readingParagraphOrder, count: loadedParagraphs.count)
            openedAtOrder = target
            phase = .loaded
            scrollTargetOrder = target
        } catch is CancellationError {
            isLoadStarted = false   // 页面在读取途中消失：下次出现时再读
        } catch {
            phase = .failed(AppText.E.readerLoadFailed)
        }
    }

    /// 阅读页出现：登记为当前阅读页，并恢复可见段的翻译。
    func appear() {
        dependencies.activeReader = self
        requestVisibleTranslations()
    }

    func paragraphAppeared(_ paragraph: ReadingParagraph) {
        visibleOrders.insert(paragraph.order)
        scheduleSettle()
        if isBilingual && !paragraph.isChapterHeading {
            translations.request(paragraph)
        }
    }

    func paragraphDisappeared(_ paragraph: ReadingParagraph) {
        visibleOrders.remove(paragraph.order)
        scheduleSettle()
        translations.withdraw(paragraph)
    }

    /// 段被导航栏或顶部提示条整段挡住 / 重新露出。
    func paragraphCoverageChanged(_ paragraph: ReadingParagraph, isCovered: Bool) {
        if isCovered {
            coveredOrders.insert(paragraph.order)
        } else {
            coveredOrders.remove(paragraph.order)
        }
        scheduleSettle()
    }

    // MARK: - 选词

    /// RD-5：查词 / 收藏 / 发音。
    func handleSelection(_ action: SelectionAction, _ selection: ParagraphSelection) {
        switch action {
        case .lookUp:
            let term = selection.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { return }
            if UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: term) {
                dictionaryLookup = DictionaryLookup(id: UUID(), term: term)
            } else {
                alertMessage = AppText.T.readerDictNone(term: term)
            }
        case .collect:
            Task { [weak self] in await self?.collect(selection) }
        case .pronounce:
            let text = selection.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            do {
                // SpeechPlaying.pronounce 会先停止正在进行的连续朗读。
                try dependencies.speech.pronounce(text, rate: dependencies.preferences.speechRate)
            } catch let error as UserFacingError {
                alertMessage = error.message
            } catch {
                alertMessage = AppText.E.speechAudioUnavailable
            }
        }
    }

    // MARK: - 翻译

    func retryTranslation(_ paragraph: ReadingParagraph) {
        translations.retry(paragraph)
    }

    /// “Prepare English–Chinese Translation”：交给 LanguagePreparationModifier 弹出系统下载确认。
    func requestLanguagePreparation() {
        isLanguagePreparationRequested = true
    }

    func languagePreparationFinished(success: Bool) {
        if success {
            translations.languagePrepared()
            requestVisibleTranslations()
        } else {
            alertMessage = AppText.E.trPrepareFailed
        }
    }

    // MARK: - 显示模式与目录

    /// RD-7：先在内存中切换，再保存；保存失败时界面仍按新模式显示。
    func setBilingualMode(_ mode: BilingualMode) async {
        guard let current = book, current.bilingualMode != mode else { return }
        book = Book(
            id: current.id,
            title: current.title,
            importedAt: current.importedAt,
            lastOpenedAt: current.lastOpenedAt,
            contentHash: current.contentHash,
            paragraphCount: current.paragraphCount,
            readingParagraphOrder: current.readingParagraphOrder,
            bilingualMode: mode,
            splitRule: current.splitRule,
            encodingName: current.encodingName
        )
        switch mode {
        case .englishOnly:
            translations.cancelAll()
        case .bilingual:
            requestVisibleTranslations()
        }
        do {
            _ = try await dependencies.books.saveBilingualMode(bookID: bookID, mode: mode)
        } catch {
            alertMessage = AppText.E.readerModeSaveFailed
        }
    }

    /// 目录：滚到章节标题段，不保存位置。
    func jump(to chapter: ReadingChapter) {
        scrollTargetOrder = Self.clamp(chapter.startOrder, count: paragraphs.count)
    }

    // MARK: - 朗读（RD-6）

    func startReadingAloud() {
        let start = currentParagraphOrder
        guard paragraphs.indices.contains(start) else { return }
        let items = paragraphs[start...].map { SpeechParagraph(order: $0.order, text: $0.text) }
        do {
            try dependencies.speech.startReading(bookID: bookID, paragraphs: items, rate: dependencies.preferences.speechRate)
        } catch let error as UserFacingError {
            alertMessage = error.message
        } catch {
            alertMessage = AppText.E.speechAudioUnavailable
        }
    }

    func pauseReadingAloud() {
        dependencies.speech.pause()
    }

    func resumeReadingAloud() {
        dependencies.speech.resume()
    }

    func stopReadingAloud() {
        dependencies.speech.stop()
    }

    /// 阅读设置里改了语速：朗读中从下一段起生效。
    func speechRateChanged(_ rate: SpeechRate) {
        dependencies.speech.setRate(rate)
    }

    /// 点 “Already saved · View Word Card” → 切到单词本并打开那张词卡。
    func openBannerCard() {
        guard case let .alreadyCollected(cardID)? = banner?.kind else { return }
        banner = nil
        bannerTask?.cancel()
        dependencies.router.openCard(cardID)
    }

    // MARK: - 离开、后台、回到前台（RD-8）

    func leave() async {
        stopSpeechIfNeeded()
        translations.cancelAll()
        if dependencies.activeReader === self {
            dependencies.activeReader = nil
        }
        await savePosition()
        // onDisappear 在返回动画结束后才触发，书库那时可能已经读过一次旧进度：保存完再通知它刷新。
        dependencies.router.readingPositionSaved()
    }

    func enterBackground() async {
        stopSpeechIfNeeded()
        translations.cancelAll()
        await savePosition()
    }

    func becomeActive() {
        requestVisibleTranslations()
    }

    // MARK: - 私有

    private var isBilingual: Bool {
        book?.bilingualMode == .bilingual
    }

    /// 离开时要保存的段：优先用「稳定」值。离开页面时各行的 onDisappear 可能先于本页触发，
    /// 那时可见集合已被部分清空，直接取最小值会把位置记到后面的段。
    private var positionToSave: Int {
        settledTopOrder ?? currentParagraphOrder
    }

    private func collect(_ selection: ParagraphSelection) async {
        do {
            let result = try await saveVocabularyCard.execute(selection)
            if result.wasCreated {
                showBanner(.collected)
                dependencies.hints.requestHint(for: result.card.id)
            } else {
                showBanner(.alreadyCollected(cardID: result.card.id))
            }
        } catch is CancellationError {
            // 不提示
        } catch let error as UserFacingError {
            alertMessage = error.message
        } catch {
            alertMessage = AppText.E.saveFailed
        }
    }

    private func showBanner(_ kind: ReaderBanner.Kind) {
        let newBanner = ReaderBanner(id: UUID(), kind: kind)
        banner = newBanner
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(newBanner.displaySeconds))
            guard !Task.isCancelled, let self, self.banner?.id == newBanner.id else { return }
            self.banner = nil
        }
    }

    private func speechStateChanged(_ state: SpeechState) {
        speechState = state
        if case let .reading(readingBookID, order) = state, readingBookID == bookID {
            scrollTargetOrder = order   // 自动滚到正在朗读的段
        }
    }

    /// 只停本书的连续朗读或单词发音；别的书的状态不碰。
    private func stopSpeechIfNeeded() {
        let state = dependencies.speech.state
        if state.bookID == bookID || state == .pronouncing {
            dependencies.speech.stop()
        }
    }

    private func savePosition() async {
        guard phase == .loaded, !isBookGone else { return }
        do {
            try await recordPosition.execute(bookID: bookID, paragraphOrder: positionToSave)
        } catch is CancellationError {
            // 不提示
        } catch let error as UserFacingError {
            dependencies.router.showAlert(error.message)
        } catch {
            dependencies.router.showAlert(AppText.E.positionSaveFailed)
        }
    }

    private func requestVisibleTranslations() {
        guard phase == .loaded, isBilingual else { return }
        for order in visibleOrders.sorted() where paragraphs.indices.contains(order) {
            let paragraph = paragraphs[order]
            if !paragraph.isChapterHeading {
                translations.request(paragraph)
            }
        }
    }

    private func scheduleSettle() {
        guard !isSettleScheduled else { return }
        isSettleScheduled = true
        Task { [weak self] in
            guard let self else { return }
            self.isSettleScheduled = false
            if let top = self.topUncoveredOrder {
                self.settledTopOrder = top
            }
        }
    }

    /// RD-2：没有章节 → 只有 “Full Text”；第一个章节不在第 1 段 → 前面加 “Beginning”。
    private static func tableOfContents(from found: [ReadingChapter]) -> [ReadingChapter] {
        guard let first = found.first else {
            return [ReadingChapter(title: AppText.T.tocWholeBook, startOrder: 0)]
        }
        if first.startOrder > 0 {
            return [ReadingChapter(title: AppText.T.tocBeginning, startOrder: 0)] + found
        }
        return found
    }

    private static func clamp(_ order: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(order, 0), count - 1)
    }
}
