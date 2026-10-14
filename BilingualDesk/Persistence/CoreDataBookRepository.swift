// File: BilingualDesk/Persistence/CoreDataBookRepository.swift
// Targets: App
import Foundation
import CoreData

/// BookRepository 的 Core Data 实现（02 §6 语义表、§4.4 谓词）。
/// 小读写在 viewContext（主队列）同步执行；insertBook、paragraphs(bookID:)、deleteBook
/// 在后台 context 的 perform 里执行，闭包只捕获 Sendable 值、只返回 Domain 值或对象 ID（C5）。
@MainActor
final class CoreDataBookRepository: BookRepository {
    private let stack: CoreDataStack

    init(stack: CoreDataStack) {
        self.stack = stack
    }

    private var viewContext: NSManagedObjectContext { stack.viewContext }

    // MARK: - 查询（viewContext）

    func books(matching searchText: String) async throws -> [Book] {
        let request = BookEntity.request()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            request.predicate = NSPredicate(format: "title CONTAINS[cd] %@", query)
        }
        // SQLite 降序时 nil 排在最后：没打开过的书排在打开过的之后，组内按导入时间新到旧。
        request.sortDescriptors = [
            NSSortDescriptor(key: "lastOpenedAt", ascending: false),
            NSSortDescriptor(key: "importedAt", ascending: false)
        ]
        return try fetch(request).map { $0.toDomain() }
    }

    func book(id: UUID) async throws -> Book? {
        try fetchBook(id: id)?.toDomain()
    }

    func book(contentHash: String) async throws -> Book? {
        let request = BookEntity.request()
        request.predicate = NSPredicate(format: "contentHash == %@", contentHash)
        request.fetchLimit = 1
        return try fetch(request).first?.toDomain()
    }

    func paragraph(bookID: UUID, order: Int) async throws -> ReadingParagraph? {
        let request = ReadingParagraphEntity.request()
        request.predicate = NSPredicate(format: "book.id == %@ AND order == %d", bookID as NSUUID, Int32(clamping: order))
        request.fetchLimit = 1
        return try fetch(request).first?.toDomain(bookID: bookID)
    }

    func chapters(bookID: UUID) async throws -> [ReadingChapter] {
        let request = ReadingParagraphEntity.request()
        request.predicate = NSPredicate(format: "book.id == %@ AND isChapterHeading == YES", bookID as NSUUID)
        request.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
        return try fetch(request).map { ReadingChapter(title: $0.text, startOrder: Int($0.order)) }
    }

    // MARK: - 小写入（viewContext）

    func saveTranslation(paragraphID: UUID, text: String, sourceHash: String) async throws {
        let request = ReadingParagraphEntity.request()
        request.predicate = NSPredicate(format: "id == %@", paragraphID as NSUUID)
        request.fetchLimit = 1
        guard let paragraph = try fetch(request).first else {
            throw RepositoryError.paragraphNotFound
        }
        paragraph.translatedText = text
        paragraph.translatedSourceHash = sourceHash
        try saveViewContext()
    }

    func saveReadingPosition(bookID: UUID, paragraphOrder: Int, at date: Date) async throws -> Book {
        guard let book = try fetchBook(id: bookID) else {
            throw RepositoryError.bookNotFound
        }
        book.readingParagraphOrder = Int32(clamping: paragraphOrder)
        book.lastOpenedAt = date
        try saveViewContext()
        return book.toDomain()
    }

    func markOpened(bookID: UUID, at date: Date) async throws -> Book {
        guard let book = try fetchBook(id: bookID) else {
            throw RepositoryError.bookNotFound
        }
        book.lastOpenedAt = date
        try saveViewContext()
        return book.toDomain()
    }

    func saveBilingualMode(bookID: UUID, mode: BilingualMode) async throws -> Book {
        guard let book = try fetchBook(id: bookID) else {
            throw RepositoryError.bookNotFound
        }
        book.bilingualMode = mode.rawValue
        try saveViewContext()
        return book.toDomain()
    }

    // MARK: - 后台 context

    /// 新建 Book 与全部段落，一次 save()（单次 save 本身是原子的）。
    func insertBook(_ record: NewBookRecord) async throws -> Book {
        let context = stack.newBackgroundContext()
        do {
            return try await context.perform {
                try insertBookRecord(record, in: context)
            }
        } catch let error as RepositoryError {
            throw error
        } catch {
            throw RepositoryError.storageFailed(String(describing: error))
        }
    }

    /// 某书全部段落，order 升序；书不存在返回 []。
    func paragraphs(bookID: UUID) async throws -> [ReadingParagraph] {
        let context = stack.newBackgroundContext()
        do {
            return try await context.perform {
                let request = ReadingParagraphEntity.request()
                request.predicate = NSPredicate(format: "book.id == %@", bookID as NSUUID)
                request.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
                request.fetchBatchSize = 200
                return try context.fetch(request).map { $0.toDomain(bookID: bookID) }
            }
        } catch {
            throw RepositoryError.storageFailed(String(describing: error))
        }
    }

    /// 删除书：段落级联删除，词卡的 sourceBook / sourceParagraph 置空，快照字段保留（02 §4.3）。
    /// 返回前把这次删除合并进 viewContext（02 §6）：已加载的词卡对象此刻就看到关系为 nil，
    /// 不依赖 automaticallyMergesChangesFromParent 的异步合并何时执行。
    func deleteBook(id: UUID) async throws {
        let context = stack.newBackgroundContext()
        let changes: DeletedBookChanges
        do {
            changes = try await context.perform {
                try deleteBookEntity(id: id, in: context)
            }
        } catch let error as RepositoryError {
            throw error
        } catch {
            throw RepositoryError.storageFailed(String(describing: error))
        }
        NSManagedObjectContext.mergeChanges(
            fromRemoteContextSave: [
                NSDeletedObjectsKey: changes.deletedObjectIDs,
                NSUpdatedObjectsKey: changes.updatedObjectIDs
            ],
            into: [viewContext]
        )
    }

    // MARK: - 私有（viewContext）

    private func fetchBook(id: UUID) throws -> BookEntity? {
        let request = BookEntity.request()
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 1
        return try fetch(request).first
    }

    private func fetch<T: NSManagedObject>(_ request: NSFetchRequest<T>) throws -> [T] {
        do {
            return try viewContext.fetch(request)
        } catch {
            throw RepositoryError.storageFailed(String(describing: error))
        }
    }

    /// 写失败先 rollback() 再抛 storageFailed（02 §6）。
    private func saveViewContext() throws {
        guard viewContext.hasChanges else { return }
        do {
            try viewContext.save()
        } catch {
            viewContext.rollback()
            throw RepositoryError.storageFailed(String(describing: error))
        }
    }
}

// MARK: - 在后台 context 队列上执行的函数
// 写成文件级函数（默认 nonisolated），这样才能在 perform 闭包里调用；它们只碰传入的 context。

private func insertBookRecord(_ record: NewBookRecord, in context: NSManagedObjectContext) throws -> Book {
    // 先查重（§4.4「重复检测」，走 byContentHash 索引）。模型没有唯一约束（02 §4.1），
    // 重复导入由这里在同一个后台 context 内「先 count、再插入」保证。
    let duplicateRequest = BookEntity.request()
    duplicateRequest.predicate = NSPredicate(format: "contentHash == %@", record.contentHash)
    if try context.count(for: duplicateRequest) > 0 {
        throw RepositoryError.duplicateContentHash
    }

    let book = BookEntity(context: context)
    book.id = record.id
    book.title = record.title
    book.importedAt = record.importedAt
    book.lastOpenedAt = nil
    book.contentHash = record.contentHash
    book.paragraphCount = Int32(clamping: record.paragraphs.count)
    book.readingParagraphOrder = 0
    book.bilingualMode = BilingualMode.bilingual.rawValue
    book.splitRule = record.splitRule.rawValue
    book.encodingName = record.encodingName

    for parsed in record.paragraphs {
        let paragraph = ReadingParagraphEntity(context: context)
        paragraph.id = UUID()
        paragraph.order = Int32(clamping: parsed.order)
        paragraph.text = parsed.text
        paragraph.sourceHash = parsed.sourceHash
        paragraph.chapterIndex = Int32(clamping: parsed.chapterIndex)
        paragraph.chapterTitle = parsed.chapterTitle
        paragraph.isChapterHeading = parsed.isChapterHeading
        paragraph.translatedText = nil
        paragraph.translatedSourceHash = nil
        paragraph.book = book
    }

    do {
        try context.save()
    } catch {
        context.rollback()
        // 保存失败后再查一次：同 hash 已存在（别处刚好先保存了同一本书）也按 duplicateContentHash 处理。
        if (try? context.count(for: duplicateRequest)) ?? 0 > 0 {
            throw RepositoryError.duplicateContentHash
        }
        throw RepositoryError.storageFailed(String(describing: error))
    }
    return book.toDomain()
}

/// 一次删书影响到的对象 ID（NSManagedObjectID 是 Sendable，可以从 perform 闭包里带回主 actor）。
private struct DeletedBookChanges: Sendable {
    let deletedObjectIDs: [NSManagedObjectID]     // Book 与级联删除的段
    let updatedObjectIDs: [NSManagedObjectID]     // 关系被置空的词卡
}

private func deleteBookEntity(id: UUID, in context: NSManagedObjectContext) throws -> DeletedBookChanges {
    let request = BookEntity.request()
    request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
    request.fetchLimit = 1
    guard let book = try context.fetch(request).first else {
        throw RepositoryError.bookNotFound
    }
    context.delete(book)
    // 先执行删除规则（段 Cascade、词卡关系 Nullify），deletedObjects / updatedObjects 才包含全部受影响对象。
    context.processPendingChanges()
    let changes = DeletedBookChanges(
        deletedObjectIDs: context.deletedObjects.map(\.objectID),
        updatedObjectIDs: context.updatedObjects.map(\.objectID)
    )
    do {
        try context.save()
    } catch {
        context.rollback()
        throw RepositoryError.storageFailed(String(describing: error))
    }
    return changes
}
