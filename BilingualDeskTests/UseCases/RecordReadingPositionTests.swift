// File: BilingualDeskTests/UseCases/RecordReadingPositionTests.swift
// Targets: Tests
import Foundation
import XCTest
@testable import BilingualDesk

/// U18：RecordReadingPosition（BR-POS）。只用 Mock 仓库。
final class RecordReadingPositionTests: XCTestCase {

    // U18 · BR-POS-1/2/3 · 边界
    @MainActor
    func test_recordingPositionBeyondLastParagraph_isRejectedWithoutSaving() async throws {
        let book = Fixtures.book(paragraphCount: 8, readingParagraphOrder: 3)
        let books = MockBookRepository()
        books.storedBooks = [book]
        let widget = MockWidgetSnapshotPublisher()
        let record = RecordReadingPosition(books: books, widget: widget, now: { Fixtures.fixedDate })

        for order in [8, -1] {
            do {
                try await record.execute(bookID: book.id, paragraphOrder: order)
                XCTFail("段序号 \(order) 超出 0..<8，应被拒绝")
            } catch let error as RecordReadingPositionError {
                XCTAssertEqual(error, .paragraphOutOfRange)
                XCTAssertEqual(error.message, AppText.E.positionOutOfRange)
            }
        }
        XCTAssertTrue(books.savedPositions.isEmpty, "越界不写库")
        XCTAssertEqual(widget.publishCount, 0, "越界不发布")
        let unchanged = try await books.book(id: book.id)
        XCTAssertEqual(unchanged?.readingParagraphOrder, 3)

        // 最后一段是合法边界
        try await record.execute(bookID: book.id, paragraphOrder: 7)
        XCTAssertEqual(books.savedPositions.count, 1)
        XCTAssertEqual(books.savedPositions.first?.order, 7)
        let saved = try await books.book(id: book.id)
        XCTAssertEqual(saved?.readingParagraphOrder, 7)
        XCTAssertEqual(saved?.lastOpenedAt, Fixtures.fixedDate)
        XCTAssertEqual(saved?.progressPercent, 100)
        XCTAssertEqual(widget.publishCount, 1, "离开阅读页保存成功后发布（P7）")
    }
}
