// File: BilingualDesk/Domain/UseCases/RemoveBookKeepingVocabulary.swift
// Targets: App
import Foundation

enum RemoveBookKeepingVocabularyError: UserFacingError, Equatable {
    case bookNotFound
    case deleteFailed

    var message: String {
        switch self {
        case .bookNotFound: return AppText.E.removeBookNotFound
        case .deleteFailed: return AppText.E.removeFailed
        }
    }
}

/// 移出书库：删除书与正文，词卡保留收藏时的快照（BR-REMOVE-1…5）。
@MainActor
struct RemoveBookKeepingVocabulary {
    let books: any BookRepository
    let speech: any SpeechPlaying
    let widget: any WidgetSnapshotPublishing

    init(books: any BookRepository, speech: any SpeechPlaying, widget: any WidgetSnapshotPublishing) {
        self.books = books
        self.speech = speech
        self.widget = widget
    }

    func execute(bookID: UUID) async throws {
        // BR-REMOVE-1
        let book: Book?
        do {
            book = try await books.book(id: bookID)
        } catch {
            throw RemoveBookKeepingVocabularyError.deleteFailed
        }
        guard book != nil else {
            throw RemoveBookKeepingVocabularyError.bookNotFound
        }

        // BR-REMOVE-2：正在朗读（或暂停在）这本书 → 先停。
        if speech.state.bookID == bookID {
            speech.stop()
        }

        // BR-REMOVE-3：翻译队列已在离开阅读页时取消，这里无需处理。
        // BR-REMOVE-4：段落级联删除，词卡关系置空、快照保留；本版不保存原始 TXT，没有文件要删。
        do {
            try await books.deleteBook(id: bookID)
        } catch RepositoryError.bookNotFound {
            throw RemoveBookKeepingVocabularyError.bookNotFound
        } catch {
            throw RemoveBookKeepingVocabularyError.deleteFailed
        }

        // BR-REMOVE-5 / P3
        await widget.publish()
    }
}
