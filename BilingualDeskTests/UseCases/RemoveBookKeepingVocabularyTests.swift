// File: BilingualDeskTests/UseCases/RemoveBookKeepingVocabularyTests.swift
// Targets: Tests
import Foundation
import XCTest
@testable import BilingualDesk

/// U17：RemoveBookKeepingVocabulary（BR-REMOVE）。只用 Mock 仓库与 Mock 朗读。
final class RemoveBookKeepingVocabularyTests: XCTestCase {

    // U17 · BR-REMOVE-2/4/5 · happy（含一个错误路径）
    @MainActor
    func test_removingBook_stopsItsReadAloud_deletesBook_andPublishesWidget() async throws {
        let readingBook = Fixtures.book(title: "My English Story", contentHash: "hash-1")
        let otherBook = Fixtures.book(title: "Another Story", contentHash: "hash-2")
        let books = MockBookRepository()
        books.storedBooks = [readingBook, otherBook]
        books.storedParagraphs = [
            readingBook.id: [Fixtures.paragraph(bookID: readingBook.id, order: 0, text: "Prologue")],
            otherBook.id: [Fixtures.paragraph(bookID: otherBook.id, order: 0, text: "Chapter 1")]
        ]
        let speech = MockSpeechPlayer()
        speech.state = .reading(bookID: readingBook.id, paragraphOrder: 2)
        let widget = MockWidgetSnapshotPublisher()
        let remove = RemoveBookKeepingVocabulary(books: books, speech: speech, widget: widget)

        // 移出另一本书：正在朗读的不是它，朗读继续
        try await remove.execute(bookID: otherBook.id)
        XCTAssertEqual(speech.stopCallCount, 0)
        XCTAssertEqual(speech.state, .reading(bookID: readingBook.id, paragraphOrder: 2))

        // 移出正在朗读的书：先停朗读，再删书和段落
        try await remove.execute(bookID: readingBook.id)
        XCTAssertEqual(speech.stopCallCount, 1)
        XCTAssertEqual(books.deletedBookIDs, [otherBook.id, readingBook.id])
        XCTAssertTrue(books.storedBooks.isEmpty)
        XCTAssertNil(books.storedParagraphs[readingBook.id])
        XCTAssertEqual(widget.publishCount, 2, "每次移出成功都发布（P3）")

        // 书已不在：bookNotFound，不再发布
        do {
            try await remove.execute(bookID: readingBook.id)
            XCTFail("书已不在时应报 bookNotFound")
        } catch let error as RemoveBookKeepingVocabularyError {
            XCTAssertEqual(error, .bookNotFound)
            XCTAssertEqual(error.message, AppText.E.removeBookNotFound)
        }
        XCTAssertEqual(widget.publishCount, 2)
    }
}
