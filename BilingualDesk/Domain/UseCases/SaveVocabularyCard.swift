// File: BilingualDesk/Domain/UseCases/SaveVocabularyCard.swift
// Targets: App
import Foundation
import NaturalLanguage

enum SaveVocabularyCardError: UserFacingError, Equatable {
    case emptySelection
    case selectionTooLong
    case selectionMismatch
    case sourceGone
    case saveFailed

    var message: String {
        switch self {
        case .emptySelection: return AppText.E.saveEmptySelection
        case .selectionTooLong: return AppText.E.saveSelectionTooLong
        case .selectionMismatch: return AppText.E.saveSelectionMismatch
        case .sourceGone: return AppText.E.saveSourceGone
        case .saveFailed: return AppText.E.saveFailed
        }
    }
}

/// 长按选词 “Save Word”（T-READER-MENU-COLLECT）：核对选区 → 去空白 → 查重 → 取所在句 → 保存词卡快照（BR-SAVE-1…9）。
/// 机器中文提示不在这里启动：调用方拿到 wasCreated == true 后再请求（BR-SAVE-9）。
@MainActor
struct SaveVocabularyCard {
    let books: any BookRepository
    let vocabulary: any VocabularyRepository
    let widget: any WidgetSnapshotPublishing
    let now: () -> Date

    init(books: any BookRepository, vocabulary: any VocabularyRepository, widget: any WidgetSnapshotPublishing, now: @escaping () -> Date = Date.init) {
        self.books = books
        self.vocabulary = vocabulary
        self.widget = widget
        self.now = now
    }

    func execute(_ selection: ParagraphSelection) async throws -> VocabularySaveResult {
        // BR-SAVE-1：读回原文核对；不存在 → sourceGone，读取失败 → saveFailed。
        let paragraph: ReadingParagraph?
        let book: Book?
        do {
            paragraph = try await books.paragraph(bookID: selection.bookID, order: selection.paragraphOrder)
            book = try await books.book(id: selection.bookID)
        } catch {
            throw SaveVocabularyCardError.saveFailed
        }
        guard let paragraph, let book, paragraph.id == selection.paragraphID else {
            throw SaveVocabularyCardError.sourceGone
        }

        // BR-SAVE-2：选区必须落在这一段里，且切出的文字与读者看到的一致。
        let text = paragraph.text
        guard selection.location >= 0,
              selection.length > 0,
              selection.location + selection.length <= text.utf16.count,
              let rawRange = Range(NSRange(location: selection.location, length: selection.length), in: text),
              String(text[rawRange]) == selection.selectedText else {
            throw SaveVocabularyCardError.selectionMismatch
        }

        // BR-SAVE-3：去掉首尾空白和换行，位置与长度同步收缩（UTF-16 计）。
        let trimmed = Self.trimmedSelection(selection.selectedText)
        guard !trimmed.text.isEmpty else {
            throw SaveVocabularyCardError.emptySelection
        }
        guard trimmed.text.count <= VocabularyLimits.maximumSelectionLength else {
            throw SaveVocabularyCardError.selectionTooLong
        }
        let location = selection.location + trimmed.leadingUTF16Count
        let length = trimmed.text.utf16.count

        // BR-SAVE-4：同一段同一范围已收藏 → 返回已有词卡，不写库、不发布。
        let existing: VocabularyCard?
        do {
            existing = try await vocabulary.card(paragraphID: paragraph.id, location: location, length: length)
        } catch {
            throw SaveVocabularyCardError.saveFailed
        }
        if let existing {
            return VocabularySaveResult(card: existing, wasCreated: false)
        }

        // BR-SAVE-5/6/7：所在句、整段有效缓存译文、来源快照。
        let draft = VocabularyCardDraft(
            selectedText: trimmed.text,
            selectionLocation: location,
            selectionLength: length,
            contextText: Self.contextSentence(in: text, location: location, length: length),
            contextTranslation: paragraph.validTranslation,
            sourceBookID: book.id,
            sourceBookTitle: book.title,
            sourceParagraphID: paragraph.id,
            sourceParagraphOrder: paragraph.order
        )

        // BR-SAVE-8：新卡 hintStatus = pending（仓库负责）。
        let card: VocabularyCard
        do {
            card = try await vocabulary.insertCard(draft, at: now())
        } catch RepositoryError.paragraphNotFound {
            throw SaveVocabularyCardError.sourceGone
        } catch {
            throw SaveVocabularyCardError.saveFailed
        }

        // BR-SAVE-9 / P4。
        await widget.publish()
        return VocabularySaveResult(card: card, wasCreated: true)
    }

    /// BR-SAVE-5：用 NLTokenizer(.sentence)（英文）切句，取与选区相交的全部句子，
    /// 从第一句起点到最后一句终点，去首尾空白；切分失败时用整段。
    static func contextSentence(in text: String, location: Int, length: Int) -> String {
        let wholeParagraph = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard location >= 0, length > 0,
              let selection = Range(NSRange(location: location, length: length), in: text) else {
            return wholeParagraph
        }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.setLanguage(.english)
        tokenizer.string = text

        var start: String.Index?
        var end: String.Index?
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { sentence, _ in
            if sentence.overlaps(selection) {
                if start == nil { start = sentence.lowerBound }
                end = sentence.upperBound
            } else if start != nil {
                return false   // 已经越过选区，后面的句子不会再相交
            }
            return true
        }

        guard let start, let end, start < end else {
            return wholeParagraph
        }
        let context = text[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return context.isEmpty ? wholeParagraph : context
    }

    // MARK: - 私有

    /// 按 Unicode 标量去掉首尾空白和换行（与 trimmingCharacters(in: .whitespacesAndNewlines) 一致），
    /// 同时返回被去掉的前导部分的 UTF-16 长度，用来修正 location。
    private static func trimmedSelection(_ raw: String) -> (text: String, leadingUTF16Count: Int) {
        let scalars = raw.unicodeScalars
        let blanks = CharacterSet.whitespacesAndNewlines
        var lower = scalars.startIndex
        var upper = scalars.endIndex
        while lower < upper, blanks.contains(scalars[lower]) {
            lower = scalars.index(after: lower)
        }
        while upper > lower, blanks.contains(scalars[scalars.index(before: upper)]) {
            upper = scalars.index(before: upper)
        }
        let leading = String(String.UnicodeScalarView(scalars[scalars.startIndex..<lower]))
        let core = String(String.UnicodeScalarView(scalars[lower..<upper]))
        return (core, leading.utf16.count)
    }
}
