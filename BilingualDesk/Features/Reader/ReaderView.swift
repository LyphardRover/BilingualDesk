// File: BilingualDesk/Features/Reader/ReaderView.swift
// Targets: App
import SwiftUI

/// 双语阅读页（页面三）：段落列表 + 顶部提示条 + 底部朗读栏 + 目录 / 设置 / 查词三个 sheet。
struct ReaderView: View {
    @StateObject private var viewModel: ReaderViewModel
    @ObservedObject private var preferences: ReaderPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var isChapterListPresented = false
    @State private var isSettingsPresented = false
    /// 正文可见区域的上沿（全局坐标）：导航栏和顶部提示条的下沿。
    @State private var visibleTop: CGFloat = 0

    init(bookID: UUID, startOrder: Int?, dependencies: AppDependencies) {
        self._viewModel = StateObject(wrappedValue: ReaderViewModel(bookID: bookID, startOrder: startOrder, dependencies: dependencies))
        self._preferences = ObservedObject(wrappedValue: dependencies.preferences)
    }

    var body: some View {
        content
            .navigationTitle(viewModel.book?.title ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .top, spacing: 0) { topBars }
            .safeAreaInset(edge: .bottom, spacing: 0) { readAloudBar }
            .task { await viewModel.load() }
            .onAppear { viewModel.appear() }
            .onDisappear { Task { await viewModel.leave() } }
            .onChange(of: preferences.speechRate) { _, rate in
                viewModel.speechRateChanged(rate)
            }
            .englishChineseLanguagePreparation(isRequested: $viewModel.isLanguagePreparationRequested) { success in
                viewModel.languagePreparationFinished(success: success)
            }
            .sheet(isPresented: $isChapterListPresented) {
                ChapterListView(chapters: viewModel.chapters) { chapter in
                    isChapterListPresented = false
                    viewModel.jump(to: chapter)
                }
            }
            .sheet(isPresented: $isSettingsPresented) {
                ReaderSettingsView(
                    preferences: preferences,
                    bilingualMode: viewModel.book?.bilingualMode ?? .bilingual
                ) { mode in
                    Task { await viewModel.setBilingualMode(mode) }
                }
            }
            .sheet(item: $viewModel.dictionaryLookup) { lookup in
                DictionarySheet(term: lookup.term)
            }
            .alert(viewModel.alertMessage ?? "", isPresented: alertBinding) {
                Button(AppText.T.commonOk, role: .cancel) {}
            }
    }

    // MARK: - 正文

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            ProgressView(AppText.T.readerLoading)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .alert(AppText.E.bookGone, isPresented: bookGoneBinding) {
                    // 书已不在：点 “OK” 后返回书库。
                    Button(AppText.T.commonOk, role: .cancel) { dismiss() }
                }
        case .failed(let message):
            Text(message)
                .font(.body)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            paragraphList
        }
    }

    private var paragraphList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(viewModel.paragraphs) { paragraph in
                    row(for: paragraph)
                        .id(paragraph.id)
                        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                        .listRowSeparator(.hidden)
                        .onAppear { viewModel.paragraphAppeared(paragraph) }
                        .onDisappear { viewModel.paragraphDisappeared(paragraph) }
                        .background {
                            // 放在背景里测量：直接挂在行上会挡住 listRowInsets、listRowSeparator、listRowBackground。
                            Color.clear.onGeometryChange(for: Bool.self) { [visibleTop] proxy in
                                // 底边在可见区域上沿之上：整段被导航栏或提示条挡住，不算「屏幕最上方的段」。
                                proxy.frame(in: .global).maxY <= visibleTop + 1
                            } action: { isCovered in
                                viewModel.paragraphCoverageChanged(paragraph, isCovered: isCovered)
                            }
                        }
                }
            }
            .listStyle(.plain)
            // List 的布局区域在导航栏和顶部提示条下面（内容仍可滚到它们后面），所以它的上沿就是可见区域上沿。
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .global).minY
            } action: { top in
                visibleTop = top
            }
            // 去掉 List 默认的最小行高（约 44 pt），否则单行短段会被撑高，段间距不再是 01 §4.3 的 12 pt。
            .environment(\.defaultMinListRowHeight, 1)
            .onChange(of: viewModel.scrollTargetOrder, initial: true) { _, target in
                scroll(proxy, to: target)
            }
        }
    }

    private func row(for paragraph: ReadingParagraph) -> some View {
        ParagraphRow(
            paragraph: paragraph,
            mode: viewModel.book?.bilingualMode ?? .bilingual,
            translationState: viewModel.translations.state(for: paragraph),
            englishFontSize: preferences.englishFontSize,
            chineseFontSize: preferences.chineseFontSize,
            isBeingReadAloud: isBeingReadAloud(paragraph),
            isReadAloudPaused: isReadAloudPaused(paragraph),
            onSelection: { action, selection in
                viewModel.handleSelection(action, selection)
            },
            onRetryTranslation: {
                viewModel.retryTranslation(paragraph)
            },
            onPrepareLanguage: {
                viewModel.requestLanguagePreparation()
            }
        )
    }

    private func isBeingReadAloud(_ paragraph: ReadingParagraph) -> Bool {
        if case let .reading(bookID, order) = viewModel.speechState {
            return bookID == viewModel.bookID && order == paragraph.order
        }
        return false
    }

    /// 朗读暂停在本书这一段（“Paused at paragraph N”）。
    private func isReadAloudPaused(_ paragraph: ReadingParagraph) -> Bool {
        if case let .paused(bookID, order) = viewModel.speechState {
            return bookID == viewModel.bookID && order == paragraph.order
        }
        return false
    }

    /// 段顶对齐屏幕顶部。等一轮主线程，让 List 先拿到新数据再滚动。
    private func scroll(_ proxy: ScrollViewProxy, to target: Int?) {
        guard let target, viewModel.paragraphs.indices.contains(target) else { return }
        let paragraphID = viewModel.paragraphs[target].id
        Task { @MainActor in
            await Task.yield()
            proxy.scrollTo(paragraphID, anchor: .top)
            if viewModel.scrollTargetOrder == target {
                viewModel.scrollTargetOrder = nil   // 清掉，下次跳到同一段时 onChange 仍会触发
            }
        }
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // 书名放在标题区：右上两个文字按钮很宽，放不下时先缩小（最小 0.7 倍）再截断，仍是一行（01 §4.3）。
        // 系统导航标题不随动态字体变大，这里同样限制在默认大小；大字号下长按标题可在放大预览里看完整书名。
        ToolbarItem(placement: .title) {
            if let title = viewModel.book?.title {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .dynamicTypeSize(...DynamicTypeSize.large)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityShowsLargeContentViewer()
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(AppText.T.readerToc) { isChapterListPresented = true }
                .disabled(viewModel.phase != .loaded)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(AppText.T.readerSettings) { isSettingsPresented = true }
                .disabled(viewModel.phase != .loaded)
        }
    }

    // MARK: - 顶部提示条

    @ViewBuilder
    private var topBars: some View {
        VStack(spacing: 8) {
            if let notice = viewModel.translations.unavailableNotice {
                HStack(alignment: .top, spacing: 12) {
                    Text(notice)
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(AppText.T.commonGotIt) {
                        viewModel.translations.dismissUnavailableNotice()
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            if let banner = viewModel.banner {
                bannerView(banner)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .animation(.default, value: viewModel.banner)
    }

    @ViewBuilder
    private func bannerView(_ banner: ReaderBanner) -> some View {
        switch banner.kind {
        case .collected:
            Text(banner.message)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(.regularMaterial, in: Capsule())
        case .alreadyCollected:
            Button {
                viewModel.openBannerCard()
            } label: {
                Text(banner.message)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(.regularMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
    }

    // MARK: - 底部朗读栏

    @ViewBuilder
    private var readAloudBar: some View {
        if viewModel.phase == .loaded {
            HStack(spacing: 12) {
                switch viewModel.speechState {
                case let .reading(bookID, order) where bookID == viewModel.bookID:
                    Text(AppText.T.readerReadingStatus(order: order + 1))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(AppText.T.readerPause) { viewModel.pauseReadingAloud() }
                        .buttonStyle(.bordered)
                    Button(AppText.T.readerStop) { viewModel.stopReadingAloud() }
                        .buttonStyle(.bordered)
                case let .paused(bookID, order) where bookID == viewModel.bookID:
                    Text(AppText.T.readerPausedStatus(order: order + 1))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(AppText.T.readerResume) { viewModel.resumeReadingAloud() }
                        .buttonStyle(.bordered)
                    Button(AppText.T.readerStop) { viewModel.stopReadingAloud() }
                        .buttonStyle(.bordered)
                default:
                    Button(AppText.T.readerReadAloud) { viewModel.startReadingAloud() }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }
            }
            .font(.subheadline)
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    // MARK: - Alert 绑定

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.alertMessage != nil },
            set: { isPresented in
                if !isPresented && viewModel.alertMessage != nil { viewModel.alertMessage = nil }
            }
        )
    }

    private var bookGoneBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isBookGone },
            set: { _ in }   // 只读：“OK” 按钮负责返回书库
        )
    }
}
