// File: BilingualDesk/Domain/UseCases/ImportTXTBook.swift
// Targets: App
import Foundation

enum ImportTXTBookError: UserFacingError, Equatable {
    case fileTooLarge
    case fileEmpty
    case fileUnreadable
    case unknownEncoding
    case notPlainText
    case noReadableText
    case titleEmpty
    case titleTooLong
    case saveFailed

    var message: String {
        switch self {
        case .fileTooLarge: return AppText.E.importTooLarge
        case .fileEmpty: return AppText.E.importEmptyFile
        case .fileUnreadable: return AppText.E.importUnreadable
        case .unknownEncoding: return AppText.E.importUnknownEncoding
        case .notPlainText: return AppText.E.importNotPlainText
        case .noReadableText: return AppText.E.importNoText
        case .titleEmpty: return AppText.E.importTitleEmpty
        case .titleTooLong: return AppText.E.importTitleTooLong
        case .saveFailed: return AppText.E.importSaveFailed
        }
    }
}

/// 导入一本 TXT：先预览（解析、分段、章节），读者确认书名后入库（BR-IMPORT-1…15）。
@MainActor
struct ImportTXTBook {
    let books: any BookRepository
    let parser: any TXTParsing
    let widget: any WidgetSnapshotPublishing
    let now: () -> Date

    init(books: any BookRepository, parser: any TXTParsing, widget: any WidgetSnapshotPublishing, now: @escaping () -> Date = Date.init) {
        self.books = books
        self.parser = parser
        self.widget = widget
        self.now = now
    }

    /// 解析候选文件，生成导入预览。只抛 ImportTXTBookError 或 CancellationError。
    func preview(_ candidate: ImportCandidate, splitRule: ParagraphSplitRule) async throws -> ImportPreview {
        // BR-IMPORT-1：解析前检查大小（恰好 10,000,000 字节允许）。
        guard candidate.data.count <= ImportLimits.maximumFileBytes else {
            throw ImportTXTBookError.fileTooLarge
        }
        // BR-IMPORT-2：0 字节。
        guard !candidate.data.isEmpty else {
            throw ImportTXTBookError.fileEmpty
        }

        // BR-IMPORT-15 / C3：解析与 SHA-256 在主线程以外执行，并继承本 Task 的取消。
        let parsed: ParsedBook
        do {
            parsed = try await Self.parseOffMain(parser: parser, data: candidate.data, splitRule: splitRule)
        } catch let error as TXTParseError {
            throw Self.importError(for: error)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // 解析器按合同只抛上面两类错误；这里只是让 switch 完整。
            throw ImportTXTBookError.unknownEncoding
        }
        // 解析刚结束时被取消（例如读者已切换分段规则）：结果作废，界面不提示。
        try Task.checkCancellation()

        return ImportPreview(
            candidate: candidate,
            parsed: parsed,
            defaultTitle: Self.defaultTitle(forFileName: candidate.fileName),
            previewParagraphs: Self.previewParagraphs(of: parsed)
        )
    }

    /// 读者点 “Import”（T-IMPORT-CONFIRM）后入库（BR-IMPORT-13、14）。
    func execute(_ preview: ImportPreview, title: String) async throws -> ImportOutcome {
        let cleanTitle = try Self.validatedTitle(title)
        let contentHash = preview.parsed.contentHash

        // 先查重：已有同内容的书 → 不写库、不发布。
        let existing: Book?
        do {
            existing = try await books.book(contentHash: contentHash)
        } catch {
            throw ImportTXTBookError.saveFailed
        }
        if let existing {
            return .alreadyInLibrary(existing)
        }

        let record = NewBookRecord(
            id: UUID(),
            title: cleanTitle,
            importedAt: now(),
            contentHash: contentHash,
            encodingName: preview.parsed.encodingName,
            splitRule: preview.parsed.splitRule,
            paragraphs: preview.parsed.paragraphs
        )

        let inserted: Book
        do {
            inserted = try await books.insertBook(record)
        } catch RepositoryError.duplicateContentHash {
            // 查重与保存之间被别处抢先导入：再查一次，按「已在书库中」处理。
            if let winner = try? await books.book(contentHash: contentHash) {
                return .alreadyInLibrary(winner)
            }
            throw ImportTXTBookError.saveFailed
        } catch {
            throw ImportTXTBookError.saveFailed
        }

        // BR-IMPORT-14 / P2：只在真正新建成功后发布。
        await widget.publish()
        return .imported(inserted)
    }

    /// BR-IMPORT-10：文件名去掉末尾 .txt（不分大小写）→ 去首尾空白 → 前 120 个字符；为空用 T-IMPORT-DEFAULT-TITLE。
    static func defaultTitle(forFileName fileName: String) -> String {
        var name = fileName
        if let suffix = name.range(of: ".txt", options: [.caseInsensitive, .anchored, .backwards]) {
            name.removeSubrange(suffix)
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let limited = String(trimmed.prefix(ImportLimits.maximumTitleLength))
        return limited.isEmpty ? AppText.T.importDefaultTitle : limited
    }

    /// BR-IMPORT-10：去首尾空白（含换行）后 1–120 个字符；返回去空白后的书名。
    static func validatedTitle(_ title: String) throws -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportTXTBookError.titleEmpty }
        guard trimmed.count <= ImportLimits.maximumTitleLength else { throw ImportTXTBookError.titleTooLong }
        return trimmed
    }

    /// BR-IMPORT-11：前 5 段；超过 600 个字符的段取前 600 个再接 T-IMPORT-PREVIEW-TRUNCATED。
    static func previewParagraphs(of parsed: ParsedBook) -> [String] {
        parsed.paragraphs.prefix(ImportLimits.previewParagraphCount).map { paragraph in
            guard paragraph.text.count > ImportLimits.previewCharactersPerParagraph else {
                return paragraph.text
            }
            return String(paragraph.text.prefix(ImportLimits.previewCharactersPerParagraph))
                + AppText.T.importPreviewTruncated
        }
    }

    // MARK: - 私有

    /// C3：nonisolated async 在全局并发执行器上运行（构建设置 Approachable Concurrency = No），
    /// 所以解析不占主线程；它仍在调用方的 Task 里，Task.checkCancellation() 能看到取消。
    private nonisolated static func parseOffMain(parser: any TXTParsing, data: Data, splitRule: ParagraphSplitRule) async throws -> ParsedBook {
        try parser.parse(data, splitRule: splitRule)
    }

    /// 02 §8.1 的 TXTParseError → ImportTXTBookError 映射。
    private static func importError(for error: TXTParseError) -> ImportTXTBookError {
        switch error {
        case .emptyFile: return .fileEmpty
        case .unknownEncoding: return .unknownEncoding
        case .notPlainText: return .notPlainText
        case .noReadableText: return .noReadableText
        }
    }
}
