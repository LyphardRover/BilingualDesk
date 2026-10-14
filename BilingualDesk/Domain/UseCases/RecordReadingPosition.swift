// File: BilingualDesk/Domain/UseCases/RecordReadingPosition.swift
// Targets: App
import Foundation

enum RecordReadingPositionError: UserFacingError, Equatable {
    case bookNotFound
    case paragraphOutOfRange
    case saveFailed

    var message: String {
        switch self {
        case .bookNotFound: return AppText.E.bookGone
        case .paragraphOutOfRange: return AppText.E.positionOutOfRange
        case .saveFailed: return AppText.E.positionSaveFailed
        }
    }
}

/// 记录「打开了这本书」与「读到第几段」（BR-POS-1…4）。
/// execute 只在离开阅读页、App 进入后台时由 ReaderViewModel 调用（BR-POS-3），滚动过程中不调用。
@MainActor
struct RecordReadingPosition {
    let books: any BookRepository
    let widget: any WidgetSnapshotPublishing
    let now: () -> Date

    init(books: any BookRepository, widget: any WidgetSnapshotPublishing, now: @escaping () -> Date = Date.init) {
        self.books = books
        self.widget = widget
        self.now = now
    }

    /// BR-POS-4：只写 lastOpenedAt，不发布。ReaderViewModel 用 try? 调用，失败不影响阅读。
    func bookOpened(bookID: UUID) async throws {
        do {
            _ = try await books.markOpened(bookID: bookID, at: now())
        } catch RepositoryError.bookNotFound {
            throw RecordReadingPositionError.bookNotFound
        } catch {
            throw RecordReadingPositionError.saveFailed
        }
    }

    /// BR-POS-1/2/3：核对段序号范围后保存位置与打开时间，成功后发布（P7 / P8）。
    func execute(bookID: UUID, paragraphOrder: Int) async throws {
        let book: Book?
        do {
            book = try await books.book(id: bookID)
        } catch {
            throw RecordReadingPositionError.saveFailed
        }
        guard let book else {
            throw RecordReadingPositionError.bookNotFound
        }
        guard paragraphOrder >= 0, paragraphOrder < book.paragraphCount else {
            throw RecordReadingPositionError.paragraphOutOfRange
        }

        do {
            _ = try await books.saveReadingPosition(bookID: bookID, paragraphOrder: paragraphOrder, at: now())
        } catch RepositoryError.bookNotFound {
            throw RecordReadingPositionError.bookNotFound
        } catch {
            throw RecordReadingPositionError.saveFailed
        }
        await widget.publish()
    }
}
