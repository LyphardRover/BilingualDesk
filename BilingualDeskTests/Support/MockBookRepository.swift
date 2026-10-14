// File: BilingualDeskTests/Support/MockBookRepository.swift
// Targets: Tests
import Foundation
@testable import BilingualDesk

@MainActor
final class MockBookRepository: BookRepository {
    // MARK: 可设置
    var storedBooks: [Book] = []
    /// 键 = bookID，数组下标 = order（查找时按 order 属性匹配，不依赖下标）。
    var storedParagraphs: [UUID: [ReadingParagraph]] = [:]
    /// 非 nil 时每个方法都抛它。
    var errorToThrow: RepositoryError?

    // MARK: 可检查
    private(set) var insertedRecords: [NewBookRecord] = []
    private(set) var savedTranslations: [(paragraphID: UUID, text: String, sourceHash: String)] = []
    private(set) var savedPositions: [(bookID: UUID, order: Int)] = []
    private(set) var deletedBookIDs: [UUID] = []

    init() {}

    func books(matching searchText: String) async throws -> [Book] {
        try throwIfNeeded()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = query.isEmpty ? storedBooks : storedBooks.filter {
            $0.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        return matched.sorted(by: Self.libraryOrder)
    }

    func book(id: UUID) async throws -> Book? {
        try throwIfNeeded()
        return storedBooks.first { $0.id == id }
    }

    func book(contentHash: String) async throws -> Book? {
        try throwIfNeeded()
        return storedBooks.first { $0.contentHash == contentHash }
    }

    func insertBook(_ record: NewBookRecord) async throws -> Book {
        try throwIfNeeded()
        if storedBooks.contains(where: { $0.contentHash == record.contentHash }) {
            throw RepositoryError.duplicateContentHash
        }
        let book = Book(
            id: record.id,
            title: record.title,
            importedAt: record.importedAt,
            lastOpenedAt: nil,
            contentHash: record.contentHash,
            paragraphCount: record.paragraphs.count,
            readingParagraphOrder: 0,
            bilingualMode: .bilingual,
            splitRule: record.splitRule,
            encodingName: record.encodingName
        )
        storedBooks.append(book)
        storedParagraphs[record.id] = record.paragraphs.map { parsed in
            ReadingParagraph(
                id: UUID(),
                bookID: record.id,
                order: parsed.order,
                text: parsed.text,
                sourceHash: parsed.sourceHash,
                chapterIndex: parsed.chapterIndex,
                chapterTitle: parsed.chapterTitle,
                isChapterHeading: parsed.isChapterHeading,
                translatedText: nil,
                translatedSourceHash: nil
            )
        }
        insertedRecords.append(record)
        return book
    }

    func paragraphs(bookID: UUID) async throws -> [ReadingParagraph] {
        try throwIfNeeded()
        return (storedParagraphs[bookID] ?? []).sorted { $0.order < $1.order }
    }

    func paragraph(bookID: UUID, order: Int) async throws -> ReadingParagraph? {
        try throwIfNeeded()
        return storedParagraphs[bookID]?.first { $0.order == order }
    }

    func chapters(bookID: UUID) async throws -> [ReadingChapter] {
        try throwIfNeeded()
        return (storedParagraphs[bookID] ?? [])
            .filter { $0.isChapterHeading }
            .sorted { $0.order < $1.order }
            .map { ReadingChapter(title: $0.text, startOrder: $0.order) }
    }

    func saveTranslation(paragraphID: UUID, text: String, sourceHash: String) async throws {
        try throwIfNeeded()
        for (bookID, list) in storedParagraphs {
            guard let index = list.firstIndex(where: { $0.id == paragraphID }) else { continue }
            let old = list[index]
            storedParagraphs[bookID]?[index] = ReadingParagraph(
                id: old.id,
                bookID: old.bookID,
                order: old.order,
                text: old.text,
                sourceHash: old.sourceHash,
                chapterIndex: old.chapterIndex,
                chapterTitle: old.chapterTitle,
                isChapterHeading: old.isChapterHeading,
                translatedText: text,
                translatedSourceHash: sourceHash
            )
            savedTranslations.append((paragraphID: paragraphID, text: text, sourceHash: sourceHash))
            return
        }
        throw RepositoryError.paragraphNotFound
    }

    func saveReadingPosition(bookID: UUID, paragraphOrder: Int, at date: Date) async throws -> Book {
        try throwIfNeeded()
        guard let index = storedBooks.firstIndex(where: { $0.id == bookID }) else {
            throw RepositoryError.bookNotFound
        }
        let old = storedBooks[index]
        let updated = Self.copy(of: old, lastOpenedAt: date, readingParagraphOrder: paragraphOrder, bilingualMode: old.bilingualMode)
        storedBooks[index] = updated
        savedPositions.append((bookID: bookID, order: paragraphOrder))
        return updated
    }

    func markOpened(bookID: UUID, at date: Date) async throws -> Book {
        try throwIfNeeded()
        guard let index = storedBooks.firstIndex(where: { $0.id == bookID }) else {
            throw RepositoryError.bookNotFound
        }
        let old = storedBooks[index]
        let updated = Self.copy(of: old, lastOpenedAt: date, readingParagraphOrder: old.readingParagraphOrder, bilingualMode: old.bilingualMode)
        storedBooks[index] = updated
        return updated
    }

    func saveBilingualMode(bookID: UUID, mode: BilingualMode) async throws -> Book {
        try throwIfNeeded()
        guard let index = storedBooks.firstIndex(where: { $0.id == bookID }) else {
            throw RepositoryError.bookNotFound
        }
        let old = storedBooks[index]
        let updated = Self.copy(of: old, lastOpenedAt: old.lastOpenedAt, readingParagraphOrder: old.readingParagraphOrder, bilingualMode: mode)
        storedBooks[index] = updated
        return updated
    }

    func deleteBook(id: UUID) async throws {
        try throwIfNeeded()
        guard storedBooks.contains(where: { $0.id == id }) else {
            throw RepositoryError.bookNotFound
        }
        storedBooks.removeAll { $0.id == id }
        storedParagraphs[id] = nil
        deletedBookIDs.append(id)
    }

    // MARK: 私有辅助

    private func throwIfNeeded() throws {
        if let errorToThrow {
            throw errorToThrow
        }
    }

    /// 02 §4.4 书库排序：打开过的在前（lastOpenedAt 降序），同组内 importedAt 降序。
    private static func libraryOrder(_ first: Book, _ second: Book) -> Bool {
        switch (first.lastOpenedAt, second.lastOpenedAt) {
        case let (firstOpened?, secondOpened?) where firstOpened != secondOpened:
            return firstOpened > secondOpened
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            return first.importedAt > second.importedAt
        }
    }

    private static func copy(of book: Book, lastOpenedAt: Date?, readingParagraphOrder: Int, bilingualMode: BilingualMode) -> Book {
        Book(
            id: book.id,
            title: book.title,
            importedAt: book.importedAt,
            lastOpenedAt: lastOpenedAt,
            contentHash: book.contentHash,
            paragraphCount: book.paragraphCount,
            readingParagraphOrder: readingParagraphOrder,
            bilingualMode: bilingualMode,
            splitRule: book.splitRule,
            encodingName: book.encodingName
        )
    }
}
