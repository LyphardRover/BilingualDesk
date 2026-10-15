// File: BilingualDesk/App/AppDependencies.swift
// Targets: App
import Foundation

/// 收藏后在后台生成机器中文提示（06 的 VocabularyHintRunner 实现它）。
@MainActor
protocol VocabularyHintRequesting: AnyObject {
    /// 同一词卡正在生成时忽略。
    func requestHint(for cardID: UUID)
}

/// 页面依赖包：AppContainer（06）创建全部具体实现后打包成它，通过 init 传给每个页面。
/// 页面只拿协议类型，不知道 Core Data、Translation、AVFoundation 的存在。
@MainActor
final class AppDependencies {
    let books: any BookRepository
    let vocabulary: any VocabularyRepository
    let parser: any TXTParsing
    let translator: any TranslationProviding
    let speech: any SpeechPlaying
    let widget: any WidgetSnapshotPublishing
    let hints: any VocabularyHintRequesting
    let preferences: ReaderPreferences
    let router: AppRouter
    let fileLoader: ImportFileLoader
    /// 当前显示的阅读页；App 进入后台 / 回到前台时由 AppContainer 使用。弱引用，阅读页释放后自动变 nil。
    weak var activeReader: ReaderViewModel?

    init(books: any BookRepository, vocabulary: any VocabularyRepository, parser: any TXTParsing,
         translator: any TranslationProviding, speech: any SpeechPlaying, widget: any WidgetSnapshotPublishing,
         hints: any VocabularyHintRequesting, preferences: ReaderPreferences, router: AppRouter,
         fileLoader: ImportFileLoader = ImportFileLoader()) {
        self.books = books
        self.vocabulary = vocabulary
        self.parser = parser
        self.translator = translator
        self.speech = speech
        self.widget = widget
        self.hints = hints
        self.preferences = preferences
        self.router = router
        self.fileLoader = fileLoader
    }

    // MARK: - Use Case 工厂（Use Case 是轻量 struct，每次用时新建即可）

    func makeImportTXTBook() -> ImportTXTBook {
        ImportTXTBook(books: books, parser: parser, widget: widget)
    }

    func makeTranslateParagraph() -> TranslateParagraph {
        TranslateParagraph(books: books, translator: translator)
    }

    func makeSaveVocabularyCard() -> SaveVocabularyCard {
        SaveVocabularyCard(books: books, vocabulary: vocabulary, widget: widget)
    }

    func makeGenerateVocabularyHint() -> GenerateVocabularyHint {
        GenerateVocabularyHint(vocabulary: vocabulary, translator: translator, widget: widget)
    }

    func makeEditVocabularyCard() -> EditVocabularyCard {
        EditVocabularyCard(vocabulary: vocabulary, widget: widget)
    }

    func makeRecordReadingPosition() -> RecordReadingPosition {
        RecordReadingPosition(books: books, widget: widget)
    }

    func makeRemoveBookKeepingVocabulary() -> RemoveBookKeepingVocabulary {
        RemoveBookKeepingVocabulary(books: books, speech: speech, widget: widget)
    }
}
