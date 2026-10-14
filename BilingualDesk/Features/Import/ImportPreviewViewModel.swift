// File: BilingualDesk/Features/Import/ImportPreviewViewModel.swift
// Targets: App
import Foundation
import Combine

/// 导入预览页结束时交给呈现方的结果（书库 sheet 或 “Pending Imports” sheet）。
enum ImportPreviewResult: Equatable {
    case imported(Book)
    case duplicateOpenExisting(Book)
    case duplicateBackToLibrary(Book)
    case cancelled
}

/// 导入预览页（页面二）的状态：后台分段、切换分段规则时取消上一次、确认导入（01 §4.2）。
@MainActor
final class ImportPreviewViewModel: ObservableObject {
    enum Phase: Equatable {
        case parsing
        case ready
        case saving
        case parseFailed(String)   // E- 文案
    }

    let candidate: ImportCandidate
    @Published var title: String
    @Published private(set) var splitRule: ParagraphSplitRule = .blankLine
    @Published private(set) var phase: Phase = .parsing
    @Published private(set) var preview: ImportPreview?
    @Published var duplicateBook: Book?          // 非 nil 时显示重复 Alert
    @Published var saveErrorMessage: String?     // 保存失败 Alert

    private let importBook: ImportTXTBook
    private var parseTask: Task<Void, Never>?
    /// 每次开始解析或取消都加 1；迟到的旧结果与当前代次不同就丢弃。
    private var parseGeneration = 0

    init(candidate: ImportCandidate, importBook: ImportTXTBook) {
        self.candidate = candidate
        self.importBook = importBook
        self.title = ImportTXTBook.defaultTitle(forFileName: candidate.fileName)
    }

    // MARK: - 派生状态

    /// 书名计数（去首尾空白后的字符数），显示为 T-IMPORT-TITLE-COUNT。
    var titleCharacterCount: Int {
        title.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    /// 书名行内红字：E-IMPORT-TITLE-EMPTY / E-IMPORT-TITLE-TOO-LONG / nil。
    var titleErrorMessage: String? {
        do {
            _ = try ImportTXTBook.validatedTitle(title)
            return nil
        } catch let error as ImportTXTBookError {
            return error.message
        } catch {
            return AppText.E.importTitleEmpty
        }
    }

    var canImport: Bool {
        phase == .ready && titleErrorMessage == nil
    }

    /// 「{fileName} · {size}」。
    var fileSummary: String {
        AppText.T.importFileSummary(fileName: candidate.fileName, size: AppText.fileSize(candidate.data.count))
    }

    /// “Encoding: {encoding} (auto-detected)”（T-IMPORT-ENCODING）；解析完成前为 nil。
    var encodingText: String? {
        guard let preview else { return nil }
        return AppText.T.importEncoding(encoding: preview.parsed.encodingName)
    }

    /// “Paragraphs: N · Chapters: M”（T-IMPORT-RESULT）或 “Paragraphs: N · No chapters found…”（T-IMPORT-RESULT-NO-CHAPTERS）；解析完成前为 nil。
    var resultText: String? {
        guard let preview else { return nil }
        let paragraphCount = preview.parsed.paragraphs.count
        let chapterCount = preview.parsed.chapterCount
        if chapterCount > 0 {
            return AppText.T.importResult(paragraphs: paragraphCount, chapters: chapterCount)
        }
        return AppText.T.importResultNoChapters(paragraphs: paragraphCount)
    }

    // MARK: - 动作

    /// 以当前分段规则解析（先取消上一次）。解析本身在主线程以外进行（BR-IMPORT-15）。
    func start() {
        parseTask?.cancel()
        parseGeneration += 1
        let generation = parseGeneration
        phase = .parsing
        preview = nil

        let candidate = candidate
        let splitRule = splitRule
        let importBook = importBook
        parseTask = Task { [weak self] in
            do {
                let result = try await importBook.preview(candidate, splitRule: splitRule)
                guard let self, generation == self.parseGeneration else { return }
                self.preview = result
                self.phase = .ready
            } catch is CancellationError {
                // 取消（切换分段规则、点 “Cancel”、关闭页面）：界面不提示。
            } catch let error as ImportTXTBookError {
                guard let self, generation == self.parseGeneration else { return }
                self.phase = .parseFailed(error.message)
            } catch {
                guard let self, generation == self.parseGeneration else { return }
                self.phase = .parseFailed(AppText.E.importUnknownEncoding)
            }
        }
    }

    /// 切换分段规则 → 取消上一次分段并重新分段；分段失败时换规则也能重试。
    func changeSplitRule(_ rule: ParagraphSplitRule) {
        guard phase != .saving, rule != splitRule else { return }
        splitRule = rule
        start()
    }

    /// 取消正在进行的分段（“Cancel” 按钮、下拉关闭、页面消失）。
    func cancel() {
        parseTask?.cancel()
        parseTask = nil
        parseGeneration += 1
    }

    /// 成功 → .imported；内容重复 → 设 duplicateBook 并返回 nil；失败 → 设 saveErrorMessage 并返回 nil。
    func confirmImport() async -> ImportPreviewResult? {
        guard canImport, let preview else { return nil }
        phase = .saving
        do {
            switch try await importBook.execute(preview, title: title) {
            case .imported(let book):
                // 保持 .saving：呈现方马上关闭页面，期间按钮保持禁用，避免重复点按。
                return .imported(book)
            case .alreadyInLibrary(let book):
                phase = .ready
                duplicateBook = book
                return nil
            }
        } catch is CancellationError {
            phase = .ready
            return nil
        } catch let error as ImportTXTBookError {
            phase = .ready
            saveErrorMessage = error.message
            return nil
        } catch {
            phase = .ready
            saveErrorMessage = AppText.E.importSaveFailed
            return nil
        }
    }
}
