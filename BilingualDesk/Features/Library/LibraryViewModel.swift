// File: BilingualDesk/Features/Library/LibraryViewModel.swift
// Targets: App
import Foundation
import Combine

/// 书库页面（页面一）的状态：列表、搜索、移出书库、读取文件选择器选中的文件。
@MainActor
final class LibraryViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var books: [Book] = []
    @Published private(set) var phase: Phase = .loading
    @Published var searchText: String = ""
    @Published var bookPendingRemoval: Book?
    @Published var alertMessage: String?

    private let bookRepository: any BookRepository
    private let removeBook: RemoveBookKeepingVocabulary
    private let fileLoader: ImportFileLoader
    private let router: AppRouter
    private var searchTask: Task<Void, Never>?
    private var loadGeneration = 0

    init(books: any BookRepository, removeBook: RemoveBookKeepingVocabulary, fileLoader: ImportFileLoader, router: AppRouter) {
        self.bookRepository = books
        self.removeBook = removeBook
        self.fileLoader = fileLoader
        self.router = router
    }

    /// 书库一本书都没有，且搜索框为空。
    var showsEmptyLibrary: Bool {
        phase == .loaded && books.isEmpty && trimmedSearchText.isEmpty
    }

    /// 有搜索词但没有匹配的书。
    var showsNoResults: Bool {
        phase == .loaded && books.isEmpty && !trimmedSearchText.isEmpty
    }

    /// 读取列表。只读查询可以直接调 Repository（L2）。
    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        do {
            let result = try await bookRepository.books(matching: trimmedSearchText)
            // 只接受最后一次请求的结果，避免旧搜索覆盖新搜索。
            guard generation == loadGeneration else { return }
            books = result
            phase = .loaded
        } catch {
            guard generation == loadGeneration else { return }
            books = []
            phase = .failed(AppText.E.libLoadFailed)
        }
    }

    /// 输入停止 300 ms 后再查询。
    func searchTextChanged() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.load()
        }
    }

    /// 确认 “Remove from Library”。成功或书已不在时都刷新列表；失败时行保留（不先删行再报错）。
    func confirmRemoval() async {
        guard let book = bookPendingRemoval else { return }
        bookPendingRemoval = nil
        do {
            try await removeBook.execute(bookID: book.id)
            await load()
        } catch let error as RemoveBookKeepingVocabularyError {
            alertMessage = error.message
            if error == .bookNotFound {
                await load()
            }
        } catch is CancellationError {
            // 不提示
        } catch let error as UserFacingError {
            alertMessage = error.message
        } catch {
            alertMessage = AppText.E.removeFailed
        }
    }

    /// 行副标题：Not started · Imported Oct 11 / 37% read · Opened Oct 12。
    func rowSubtitle(for book: Book) -> String {
        if let openedAt = book.lastOpenedAt {
            return AppText.T.libRowReading(percent: book.progressPercent, date: AppText.monthDay(openedAt))
        }
        return AppText.T.libRowUnread(date: AppText.monthDay(book.importedAt))
    }

    /// 文件选择器的结果。读文件放在 ViewModel（L1），成功后由路由打开导入预览 sheet。
    func importPickedFile(_ result: Result<URL, any Error>) async {
        switch result {
        case .failure(let error):
            // 读者自己取消选择器时什么也不提示（01 §4.1）。
            if let cocoaError = error as? CocoaError, cocoaError.code == .userCancelled { return }
            alertMessage = AppText.E.importUnreadable
        case .success(let url):
            do {
                let candidate = try await fileLoader.loadCandidate(from: url)
                router.importCandidate = candidate
            } catch let error as ImportTXTBookError {
                alertMessage = error.message
            } catch is CancellationError {
                // 不提示
            } catch {
                alertMessage = AppText.E.importUnreadable
            }
        }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
