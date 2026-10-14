// File: BilingualDesk/Shared/AppText.swift
// Targets: App, Share, Widget
import Foundation

/// 01 §6 统一文案表的唯一代码入口（209 个 ID：T- 156 个，E- 53 个）。
/// 命名按 02 §15：去掉 T-/E- 前缀，各段按 "-" 切开，第一段全小写，之后每段首字母大写。
/// 无参数文案是 static let，有参数文案是 static func（参数标签取 01 §6「参数」列）。
/// 改文案的顺序：先改 01 §6，再改本文件，最后改引用它的页面与测试（00 §7.2）。
enum AppText {
    /// 界面文字（T-）
    enum T {
        // MARK: 01 §6.1 通用与启动
        static let commonOk = "OK"  // T-COMMON-OK
        static let commonCancel = "Cancel"  // T-COMMON-CANCEL
        static let commonDone = "Done"  // T-COMMON-DONE
        static let commonDelete = "Delete"  // T-COMMON-DELETE
        static let commonRetry = "Retry"  // T-COMMON-RETRY
        static let commonClose = "Close"  // T-COMMON-CLOSE
        static let commonGotIt = "Got It"  // T-COMMON-GOT-IT
        static let appName = "BilingualDesk"  // T-APP-NAME
        static let appLoading = "Opening Library…"  // T-APP-LOADING
        static let tabLibrary = "Library"  // T-TAB-LIBRARY
        static let tabVocabulary = "Vocabulary"  // T-TAB-VOCABULARY
        // MARK: 01 §6.2 书库
        static let libTitle = "Library"  // T-LIB-TITLE
        static let libImport = "Import"  // T-LIB-IMPORT
        static let libSearchPrompt = "Search titles"  // T-LIB-SEARCH-PROMPT
        static let libLoading = "Loading Library…"  // T-LIB-LOADING
        static func libInboxCard(count: Int) -> String { "Pending imports: \(count)" }  // T-LIB-INBOX-CARD
        static let libInboxView = "View"  // T-LIB-INBOX-VIEW
        static let libEmptyTitle = "Add an English TXT to Your Library"  // T-LIB-EMPTY-TITLE
        static let libEmptyMessage = "Tap “Import” at the top right to choose a .txt file, or share a TXT to BilingualDesk from the Files app."  // T-LIB-EMPTY-MESSAGE
        static let libEmptyAction = "Import TXT"  // T-LIB-EMPTY-ACTION
        static let libNoResultsTitle = "No Matching Books"  // T-LIB-NO-RESULTS-TITLE
        static let libNoResultsMessage = "Try another keyword, or clear the search to see all books."  // T-LIB-NO-RESULTS-MESSAGE
        static func libRowUnread(date: String) -> String { "Not started · Imported \(date)" }  // T-LIB-ROW-UNREAD
        static func libRowReading(percent: Int, date: String) -> String { "\(percent)% read · Opened \(date)" }  // T-LIB-ROW-READING
        static let libRemoveButton = "Remove from Library"  // T-LIB-REMOVE-BUTTON
        static func libRemoveConfirmTitle(title: String) -> String { "Remove “\(title)” from Library?" }  // T-LIB-REMOVE-CONFIRM-TITLE
        static let libRemoveConfirmMessage = "The book’s text, Chinese translations and reading position will be deleted. Saved word cards stay, still showing the context they were saved in."  // T-LIB-REMOVE-CONFIRM-MESSAGE
        // MARK: 01 §6.3 导入
        static let importTitle = "Import Preview"  // T-IMPORT-TITLE
        static let importConfirm = "Import"  // T-IMPORT-CONFIRM
        static let importSectionTitle = "Title"  // T-IMPORT-SECTION-TITLE
        static let importTitlePlaceholder = "Enter a title"  // T-IMPORT-TITLE-PLACEHOLDER
        static func importTitleCount(count: Int) -> String { "\(count)/120" }  // T-IMPORT-TITLE-COUNT
        static let importSectionFile = "File"  // T-IMPORT-SECTION-FILE
        static func importFileSummary(fileName: String, size: String) -> String { "\(fileName) · \(size)" }  // T-IMPORT-FILE-SUMMARY
        static func importEncoding(encoding: String) -> String { "Encoding: \(encoding) (auto-detected)" }  // T-IMPORT-ENCODING
        static let importSectionSplit = "Paragraph Splitting"  // T-IMPORT-SECTION-SPLIT
        static let importSplitBlankLine = "Blank Lines"  // T-IMPORT-SPLIT-BLANK-LINE
        static let importSplitEachLine = "Each Line"  // T-IMPORT-SPLIT-EACH-LINE
        static let importSplitHint = "Choose “Blank Lines” if paragraphs are separated by an empty line; choose “Each Line” if every line is its own paragraph."  // T-IMPORT-SPLIT-HINT
        static let importSectionResult = "Detected"  // T-IMPORT-SECTION-RESULT
        static func importResult(paragraphs: Int, chapters: Int) -> String { "Paragraphs: \(paragraphs) · Chapters: \(chapters)" }  // T-IMPORT-RESULT
        static func importResultNoChapters(paragraphs: Int) -> String { "Paragraphs: \(paragraphs) · No chapters found, so Contents will show only “Full Text”" }  // T-IMPORT-RESULT-NO-CHAPTERS
        static let importSectionPreview = "Preview (First 5 Paragraphs)"  // T-IMPORT-SECTION-PREVIEW
        static let importPreviewFootnote = "The preview shows the first 600 characters of the first 5 paragraphs only; the full text is saved on import."  // T-IMPORT-PREVIEW-FOOTNOTE
        static let importPreviewTruncated = "… (preview truncated)"  // T-IMPORT-PREVIEW-TRUNCATED
        static let importParsing = "Reading and splitting…"  // T-IMPORT-PARSING
        static let importSaving = "Saving book…"  // T-IMPORT-SAVING
        static let importDefaultTitle = "Untitled TXT"  // T-IMPORT-DEFAULT-TITLE
        static let importDuplicateTitle = "This TXT Is Already in Your Library"  // T-IMPORT-DUPLICATE-TITLE
        static func importDuplicateMessage(title: String) -> String { "“\(title)” in your Library has exactly the same content as this file, so it won’t be imported again." }  // T-IMPORT-DUPLICATE-MESSAGE
        static let importDuplicateOpen = "Open Existing Book"  // T-IMPORT-DUPLICATE-OPEN
        static let importDuplicateBack = "Back to Library"  // T-IMPORT-DUPLICATE-BACK
        // MARK: 01 §6.4 双语阅读、翻译、朗读
        static let readerLoading = "Opening this book…"  // T-READER-LOADING
        static let readerToc = "Contents"  // T-READER-TOC
        static let readerSettings = "Settings"  // T-READER-SETTINGS
        static let readerMenuLookup = "Define"  // T-READER-MENU-LOOKUP
        static let readerMenuCollect = "Save Word"  // T-READER-MENU-COLLECT
        static let readerMenuPronounce = "Pronounce"  // T-READER-MENU-PRONOUNCE
        static let readerCollected = "Added to Vocabulary"  // T-READER-COLLECTED
        static let readerAlreadyCollected = "Already saved · View Word Card"  // T-READER-ALREADY-COLLECTED
        static func readerDictNone(term: String) -> String { "The system dictionary has no entry for “\(term)”. You can still tap “Save Word”, and BilingualDesk will generate a machine Chinese hint for it." }  // T-READER-DICT-NONE
        static let readerReadAloud = "Read Aloud from Here"  // T-READER-READ-ALOUD
        static let readerPause = "Pause"  // T-READER-PAUSE
        static let readerResume = "Resume"  // T-READER-RESUME
        static let readerStop = "Stop"  // T-READER-STOP
        static func readerReadingStatus(order: Int) -> String { "Reading paragraph \(order)" }  // T-READER-READING-STATUS
        static func readerPausedStatus(order: Int) -> String { "Paused at paragraph \(order)" }  // T-READER-PAUSED-STATUS
        static let trWaiting = "Waiting to translate…"  // T-TR-WAITING
        static let trTranslating = "Translating…"  // T-TR-TRANSLATING
        static let trPrepare = "Prepare English–Chinese Translation"  // T-TR-PREPARE
        // MARK: 01 §6.5 目录与阅读设置
        static let tocTitle = "Contents"  // T-TOC-TITLE
        static let tocWholeBook = "Full Text"  // T-TOC-WHOLE-BOOK
        static let tocBeginning = "Beginning"  // T-TOC-BEGINNING
        static let settingsTitle = "Reading Settings"  // T-SETTINGS-TITLE
        static let settingsMode = "Display Mode"  // T-SETTINGS-MODE
        static let settingsModeBilingual = "Bilingual"  // T-SETTINGS-MODE-BILINGUAL
        static let settingsModeEnglishOnly = "English Only"  // T-SETTINGS-MODE-ENGLISH-ONLY
        static let settingsModeFootnote = "Display mode applies to this book only."  // T-SETTINGS-MODE-FOOTNOTE
        static let settingsFont = "Text Size"  // T-SETTINGS-FONT
        static func settingsFontValue(en: Int, zh: Int) -> String { "English \(en) pt · Chinese \(zh) pt" }  // T-SETTINGS-FONT-VALUE
        static let settingsTheme = "Theme"  // T-SETTINGS-THEME
        static let settingsThemeSystem = "System"  // T-SETTINGS-THEME-SYSTEM
        static let settingsThemeDay = "Light"  // T-SETTINGS-THEME-DAY
        static let settingsThemeNight = "Dark"  // T-SETTINGS-THEME-NIGHT
        static let settingsRate = "Read-Aloud Speed"  // T-SETTINGS-RATE
        static let settingsRateSlower = "Slower"  // T-SETTINGS-RATE-SLOWER
        static let settingsRateNormal = "Normal"  // T-SETTINGS-RATE-NORMAL
        static let settingsRateFaster = "Faster"  // T-SETTINGS-RATE-FASTER
        // MARK: 01 §6.6 单词本、词卡、机器提示
        static let vocabTitle = "Vocabulary"  // T-VOCAB-TITLE
        static let vocabSearchPrompt = "Search English words or phrases"  // T-VOCAB-SEARCH-PROMPT
        static let vocabNeedsChineseFilter = "Needs Chinese Only"  // T-VOCAB-NEEDS-CHINESE-FILTER
        static let vocabLoading = "Loading Vocabulary…"  // T-VOCAB-LOADING
        static let vocabEmptyTitle = "No Word Cards Yet"  // T-VOCAB-EMPTY-TITLE
        static let vocabEmptyMessage = "While reading, press and hold an English word and tap “Save Word”. It’s saved here along with the sentence it came from."  // T-VOCAB-EMPTY-MESSAGE
        static let vocabNoResultsTitle = "No Matching Word Cards"  // T-VOCAB-NO-RESULTS-TITLE
        static let vocabNoResultsMessage = "Try another keyword, or turn off “Needs Chinese Only”."  // T-VOCAB-NO-RESULTS-MESSAGE
        static func vocabRowSource(title: String) -> String { "“\(title)”" }  // T-VOCAB-ROW-SOURCE
        static let vocabDeleteConfirmTitle = "Delete This Word Card?"  // T-VOCAB-DELETE-CONFIRM-TITLE
        static let vocabDeleteConfirmMessage = "The word card and the meaning you wrote will be deleted together. The book isn’t affected."  // T-VOCAB-DELETE-CONFIRM-MESSAGE
        static let meaningLeftBlank = "Left Blank"  // T-MEANING-LEFT-BLANK
        static let meaningHintPending = "Machine hint pending"  // T-MEANING-HINT-PENDING
        static let meaningHintFailed = "Machine hint not generated"  // T-MEANING-HINT-FAILED
        static let meaningMachineTag = "Machine Hint"  // T-MEANING-MACHINE-TAG
        static let cardTitle = "Word Card"  // T-CARD-TITLE
        static let cardBack = "Back"  // T-CARD-BACK
        static let cardPronounce = "Pronounce"  // T-CARD-PRONOUNCE
        static let cardSectionHint = "Machine Hint"  // T-CARD-SECTION-HINT
        static let cardHintPending = "Generating machine hint…"  // T-CARD-HINT-PENDING
        static let cardHintFailed = "The machine hint wasn’t generated. Tap “Regenerate” to try again, or write the Chinese yourself in “My Meaning”."  // T-CARD-HINT-FAILED
        static let cardRegenerate = "Regenerate"  // T-CARD-REGENERATE
        static let cardSectionMeaning = "My Meaning"  // T-CARD-SECTION-MEANING
        static let cardMeaningPlaceholder = "Write what it means in this context (up to 500 characters)"  // T-CARD-MEANING-PLACEHOLDER
        static func cardMeaningCount(count: Int) -> String { "\(count)/500" }  // T-CARD-MEANING-COUNT
        static let cardMeaningUnsetNote = "No meaning written yet: Vocabulary shows the machine hint."  // T-CARD-MEANING-UNSET-NOTE
        static let cardMeaningLeftBlankNote = "Currently “Left Blank”: Vocabulary won’t show the machine hint."  // T-CARD-MEANING-LEFT-BLANK-NOTE
        static let cardSaveMeaning = "Save Meaning"  // T-CARD-SAVE-MEANING
        static let cardUseMachineHint = "Use Machine Hint"  // T-CARD-USE-MACHINE-HINT
        static let cardMeaningSaved = "Meaning saved"  // T-CARD-MEANING-SAVED
        static let cardSectionContext = "Context"  // T-CARD-SECTION-CONTEXT
        static let cardSectionContextTranslation = "Paragraph Translation (When Saved)"  // T-CARD-SECTION-CONTEXT-TRANSLATION
        static let cardNoContextTranslation = "This paragraph had no Chinese translation yet when the word was saved."  // T-CARD-NO-CONTEXT-TRANSLATION
        static let cardSectionSource = "Source"  // T-CARD-SECTION-SOURCE
        static func cardSource(title: String, order: Int) -> String { "“\(title)”, paragraph \(order)" }  // T-CARD-SOURCE
        static let cardBackToSource = "Go to Source"  // T-CARD-BACK-TO-SOURCE
        static let cardSourceGone = "The book was removed from your Library; the saved context is still available."  // T-CARD-SOURCE-GONE
        static let cardDelete = "Delete Word Card"  // T-CARD-DELETE
        static let cardLeaveConfirmTitle = "Save Your Meaning Before Leaving?"  // T-CARD-LEAVE-CONFIRM-TITLE
        static let cardLeaveSave = "Save"  // T-CARD-LEAVE-SAVE
        static let cardLeaveDiscard = "Discard"  // T-CARD-LEAVE-DISCARD
        static let cardLeaveKeepEditing = "Keep Editing"  // T-CARD-LEAVE-KEEP-EDITING
        static let cardLoading = "Loading word card…"  // T-CARD-LOADING
        // MARK: 01 §6.7 待导入文件、Share 扩展
        static let inboxTitle = "Pending Imports"  // T-INBOX-TITLE
        static func inboxRowDetail(dateTime: String, size: String) -> String { "Received \(dateTime) · \(size)" }  // T-INBOX-ROW-DETAIL
        static let inboxFootnote = "Tap an item to open Import Preview. Once it’s imported, the file is removed from this list automatically."  // T-INBOX-FOOTNOTE
        static let inboxEmptyTitle = "No Pending Imports"  // T-INBOX-EMPTY-TITLE
        static let inboxEmptyMessage = "In the Files app, press and hold a TXT and choose “Share” → “BilingualDesk”. It will appear here."  // T-INBOX-EMPTY-MESSAGE
        static let inboxDeleteConfirmTitle = "Delete This Pending Import?"  // T-INBOX-DELETE-CONFIRM-TITLE
        static let inboxDeleteConfirmMessage = "Only the copy BilingualDesk received will be deleted. The original file in the Files app isn’t affected."  // T-INBOX-DELETE-CONFIRM-MESSAGE
        static let shareSaving = "Adding TXT to BilingualDesk…"  // T-SHARE-SAVING
        static let shareSaved = "Added to Pending Imports in BilingualDesk. Open the app to finish importing."  // T-SHARE-SAVED
        static let shareDefaultFileName = "Shared Text"  // T-SHARE-DEFAULT-FILE-NAME
        // MARK: 01 §6.8 小组件与无障碍
        static let widgetDescription = "Continue your latest book and see your newest word card and how many cards need Chinese."  // T-WIDGET-DESCRIPTION
        static let widgetContinueReading = "Continue Reading"  // T-WIDGET-CONTINUE-READING
        static func widgetProgress(percent: Int) -> String { "\(percent)% read" }  // T-WIDGET-PROGRESS
        static let widgetLatestCard = "Latest Word Card"  // T-WIDGET-LATEST-CARD
        static let widgetNoCard = "No Word Cards Yet"  // T-WIDGET-NO-CARD
        static let widgetNoCardHint = "Press and hold a word while reading to save it"  // T-WIDGET-NO-CARD-HINT
        static func widgetNeedsChinese(count: Int) -> String { "Needs Chinese: \(count)" }  // T-WIDGET-NEEDS-CHINESE
        static let widgetEmpty = "No books yet · Open BilingualDesk to import a TXT"  // T-WIDGET-EMPTY
        static let widgetSampleTitle = "My English Story"  // T-WIDGET-SAMPLE-TITLE
        static let widgetSampleWord = "curious"  // T-WIDGET-SAMPLE-WORD
        static let widgetSampleMeaning = "好奇的"  // T-WIDGET-SAMPLE-MEANING
        static let a11yReadingNow = "Reading aloud"  // T-A11Y-READING-NOW
        static func a11yTranslation(text: String) -> String { "Chinese translation: \(text)" }  // T-A11Y-TRANSLATION
        static func a11yWidgetOpenBook(title: String) -> String { "Open “\(title)” to continue reading" }  // T-A11Y-WIDGET-OPEN-BOOK
        static func a11yWidgetOpenCard(word: String) -> String { "Open word card \(word)" }  // T-A11Y-WIDGET-OPEN-CARD
    }

    /// 错误文案（E-）：发生了什么 + 下一步
    enum E {
        // MARK: 01 §6.1 通用与启动
        static let appStoreFailed = "Your Library couldn’t open: the on-device database failed to load. Tap “Retry”; if it still fails, fully quit BilingualDesk, reopen it, and check that your iPhone has free storage. Your saved books and word cards won’t be deleted."  // E-APP-STORE-FAILED
        static let appgroupUnavailable = "Sharing and widgets are unavailable: the App Group isn’t set up. Library and reading still work; check the signing team and App Group of all three targets."  // E-APPGROUP-UNAVAILABLE
        static let bookGone = "This book was removed from your Library. Its word cards are still in “Vocabulary”; choose another book in Library."  // E-BOOK-GONE
        static let cardGone = "This word card was deleted. See your other word cards in “Vocabulary”."  // E-CARD-GONE
        static let linkLookupFailed = "Couldn’t open the widget’s item: the on-device database can’t be read right now. Open it yourself from “Library” or “Vocabulary”."  // E-LINK-LOOKUP-FAILED
        // MARK: 01 §6.2 书库
        static let libLoadFailed = "Couldn’t load your Library: reading the on-device database failed. Pull down to refresh; if it still fails, fully quit BilingualDesk and reopen it."  // E-LIB-LOAD-FAILED
        static let removeBookNotFound = "This book is no longer in your Library (it may have just been removed). The list has been refreshed; there’s nothing else to do."  // E-REMOVE-BOOK-NOT-FOUND
        static let removeFailed = "The book wasn’t removed: writing to the on-device database failed, so the book and word cards are unchanged. Swipe left and tap “Remove from Library” again in a moment."  // E-REMOVE-FAILED
        // MARK: 01 §6.3 导入
        static let importTooLarge = "This TXT is over 10 MB (10,000,000 bytes), so BilingualDesk can’t import it. Split it into smaller TXT files and import them one by one."  // E-IMPORT-TOO-LARGE
        static let importEmptyFile = "This file is empty (0 bytes), so there’s nothing to import. Check that you picked the right file, or export the TXT again from the original app."  // E-IMPORT-EMPTY-FILE
        static let importUnreadable = "Couldn’t read this file: iOS didn’t let BilingualDesk open it, or it hasn’t downloaded to this iPhone yet. Open it once in the Files app to make sure it’s available, then choose it again."  // E-IMPORT-UNREADABLE
        static let importUnknownEncoding = "Couldn’t recognize the file’s text encoding. Save the file as UTF-8, then try again."  // E-IMPORT-UNKNOWN-ENCODING
        static let importNotPlainText = "This file has many control characters and doesn’t look like a plain-text TXT (it may be a renamed Word, PDF or zip file). Export it as a plain-text .txt from the original app, then import again."  // E-IMPORT-NOT-PLAIN-TEXT
        static let importNoText = "The file contains only whitespace, with no English text to read. Check the file’s contents, then choose it again."  // E-IMPORT-NO-TEXT
        static let importTitleEmpty = "The title can’t be empty. Enter a title of 1–120 characters, then tap “Import”."  // E-IMPORT-TITLE-EMPTY
        static let importTitleTooLong = "The title is over 120 characters. Shorten it to 120 characters or fewer, then tap “Import”."  // E-IMPORT-TITLE-TOO-LONG
        static let importSaveFailed = "The book wasn’t saved to your Library: writing to the on-device database failed. The preview is still here; tap “Import” again in a moment. If it keeps failing, check that your iPhone has free storage."  // E-IMPORT-SAVE-FAILED
        // MARK: 01 §6.4 双语阅读、翻译、朗读
        static let readerLoadFailed = "This book’s text couldn’t be loaded: reading the on-device database failed. Go back to Library and open the book again."  // E-READER-LOAD-FAILED
        static let readerModeSaveFailed = "Display mode wasn’t saved: writing to the on-device database failed. This session still uses the mode you chose; next time you open this book, switch it again in “Settings”."  // E-READER-MODE-SAVE-FAILED
        static let positionOutOfRange = "Reading position wasn’t saved: the paragraph number is outside this book’s range. The book will reopen at the last saved position; scroll to the paragraph you want before leaving."  // E-POSITION-OUT-OF-RANGE
        static let positionSaveFailed = "Reading position wasn’t saved: writing to the on-device database failed. The book will reopen at the last saved position; open it again, scroll to your current paragraph, then leave once more."  // E-POSITION-SAVE-FAILED
        static let saveEmptySelection = "The selection is only spaces or line breaks, so it can’t be saved. Press and hold to select an English word or phrase, then tap “Save Word”."  // E-SAVE-EMPTY-SELECTION
        static let saveSelectionTooLong = "The selection is over 200 characters, too long for a word card. Select something shorter (a word or phrase), then tap “Save Word”."  // E-SAVE-SELECTION-TOO-LONG
        static let saveSelectionMismatch = "The selection no longer matches this paragraph’s text; the page may have just refreshed. Press and hold to select again, then tap “Save Word”."  // E-SAVE-SELECTION-MISMATCH
        static let saveSourceGone = "Not saved: this book or paragraph is no longer in your Library. Go back to Library, reopen (or re-import) the book, then save the word again."  // E-SAVE-SOURCE-GONE
        static let saveFailed = "The word card wasn’t saved: writing to the on-device database failed. Your selection is still there; tap “Save Word” again in a moment."  // E-SAVE-FAILED
        static let trNeedsLanguage = "Chinese can’t be shown yet: this iPhone hasn’t downloaded the English–Chinese translation languages. Tap “Prepare English–Chinese Translation” below (needs internet once; works offline afterward)."  // E-TR-NEEDS-LANGUAGE
        static let trPrepareFailed = "English–Chinese translation isn’t ready: the download was canceled or there’s no internet. Connect to the internet, then tap “Prepare English–Chinese Translation” again; English text and word cards still work."  // E-TR-PREPARE-FAILED
        static let trSimulator = "The Simulator doesn’t support system translation. English text and word cards still work; view the Chinese on an iPhone."  // E-TR-SIMULATOR
        static let trUnsupported = "This iPhone’s system translation doesn’t support English to Simplified Chinese, so no Chinese will be shown. Reading, pronunciation and word cards still work; you can write a card’s Chinese yourself in “My Meaning”."  // E-TR-UNSUPPORTED
        static let trFailed = "Chinese for this paragraph wasn’t generated: system translation returned no result this time. Tap “Retry”; you can keep reading the English."  // E-TR-FAILED
        static let speechNoVoice = "No English voice is available on this device right now. Download an English voice in the system’s speech settings, then try again."  // E-SPEECH-NO-VOICE
        static let speechAudioUnavailable = "Read-aloud didn’t start: system audio is busy (for example, a phone call or another app recording). End the call or recording, then try again."  // E-SPEECH-AUDIO-UNAVAILABLE
        // MARK: 01 §6.6 单词本、词卡、机器提示
        static let vocabLoadFailed = "Couldn’t load Vocabulary: reading the on-device database failed. Pull down to refresh; if it still fails, fully quit BilingualDesk and reopen it."  // E-VOCAB-LOAD-FAILED
        static let cardLoadFailed = "This word card couldn’t be loaded: reading the on-device database failed. Go back to Vocabulary and open it again."  // E-CARD-LOAD-FAILED
        static let cardMeaningTooLong = "“My Meaning” is over 500 characters, so it wasn’t saved. Shorten it to 500 characters or fewer, then tap “Save Meaning”."  // E-CARD-MEANING-TOO-LONG
        static let cardSaveFailed = "Your meaning wasn’t saved: writing to the on-device database failed. Your text is still here; tap “Save Meaning” again in a moment."  // E-CARD-SAVE-FAILED
        static let cardDeleteFailed = "The word card wasn’t deleted: writing to the on-device database failed. Try deleting it again in a moment."  // E-CARD-DELETE-FAILED
        static let hintNeedsLanguage = "Machine hint not generated: this iPhone hasn’t downloaded the English–Chinese translation languages. Open any book, tap “Prepare English–Chinese Translation” under a paragraph, then come back and tap “Regenerate”."  // E-HINT-NEEDS-LANGUAGE
        static let hintSimulator = "Machine hint not generated: the Simulator doesn’t support system translation. Tap “Regenerate” on an iPhone, or write the Chinese yourself in “My Meaning”."  // E-HINT-SIMULATOR
        static let hintUnsupported = "Machine hint not generated: this iPhone’s system translation doesn’t support English to Simplified Chinese. Write the Chinese yourself in “My Meaning”."  // E-HINT-UNSUPPORTED
        static let hintFailed = "Machine hint not generated: system translation returned no result this time. Tap “Regenerate” to try again."  // E-HINT-FAILED
        static let hintSaveFailed = "The machine hint was generated but not saved: writing to the on-device database failed. Tap “Regenerate” to try again."  // E-HINT-SAVE-FAILED
        // MARK: 01 §6.7 待导入文件、Share 扩展
        static let inboxScanFailed = "Couldn’t load pending imports: the shared folder can’t be accessed right now. Unlock your iPhone and return to BilingualDesk; the list will refresh automatically."  // E-INBOX-SCAN-FAILED
        static let inboxFileUnreadable = "This pending import can’t be read: it may not have been saved completely when it was shared. Swipe left to delete it, then share the TXT again from the Files app."  // E-INBOX-FILE-UNREADABLE
        static let inboxDeleteFailed = "This pending import wasn’t deleted: writing to the shared folder failed. Swipe left and delete it again in a moment."  // E-INBOX-DELETE-FAILED
        static let shareNoFile = "No TXT file to import was received. In the Files app, press and hold one .txt file (one at a time), then choose “Share” → “BilingualDesk”."  // E-SHARE-NO-FILE
        static let shareTooLarge = "This TXT is over 10 MB (10,000,000 bytes), so it wasn’t added to Pending Imports. Split it into smaller TXT files and share them one by one."  // E-SHARE-TOO-LARGE
        static let shareEmptyFile = "This file is empty (0 bytes), so it wasn’t added to Pending Imports. Check that you picked the right file, then share it again."  // E-SHARE-EMPTY-FILE
        static let shareLoadFailed = "Couldn’t get the file’s contents: the source app didn’t hand the file to BilingualDesk (it may still be downloading from iCloud). Wait for the download to finish, then share it again."  // E-SHARE-LOAD-FAILED
        static let shareAppgroup = "Couldn’t add to Pending Imports: BilingualDesk’s shared folder (App Group) isn’t set up. Open BilingualDesk to see the notice, check the signing team and App Group of all three targets, then share again."  // E-SHARE-APPGROUP
        static let shareWriteFailed = "Not added to Pending Imports: writing to the shared folder failed (your iPhone may be low on storage). Free up some space, then share again."  // E-SHARE-WRITE-FAILED
        // MARK: 01 §6.8 小组件与无障碍
        static let widgetNeedsSetup = "Open BilingualDesk once to finish setup"  // E-WIDGET-NEEDS-SETUP
    }

    // MARK: 格式化（固定英文格式，不跟系统语言与地区变化；01 §4 通用规则）

    /// "Oct 12"：用于 T-LIB-ROW-UNREAD / T-LIB-ROW-READING 的 {date}。
    static func monthDay(_ date: Date) -> String {
        makeFormatter(pattern: "MMM d").string(from: date)
    }

    /// "Oct 12, 09:30"：用于 T-INBOX-ROW-DETAIL 的 {dateTime}（24 小时制）。
    static func monthDayTime(_ date: Date) -> String {
        makeFormatter(pattern: "MMM d, HH:mm").string(from: date)
    }

    /// 系统字节格式（如 "18 KB"、"1.2 MB"）：用于 {size}。
    static func fileSize(_ byteCount: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    /// 每次新建 DateFormatter：调用频率低（列表行级别），换来线程安全，三个 target 都能放心调用。
    private static func makeFormatter(pattern: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = pattern
        return formatter
    }
}
