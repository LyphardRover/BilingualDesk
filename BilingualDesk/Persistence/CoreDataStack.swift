// File: BilingualDesk/Persistence/CoreDataStack.swift
// Targets: App
import Foundation
import CoreData

enum CoreDataStackError: Error {
    case modelNotFound
    case storeLoadFailed(String)
}

/// 加载 BilingualDesk.momd 与持久化容器（02 §4.6）。
/// 磁盘库放在 NSPersistentContainer 默认位置（App 私有 Application Support）；
/// 加载失败只抛错：不自动改用内存库、不删除数据库文件（由 RootView 显示 E-APP-STORE-FAILED + “Retry”）。
@MainActor
final class CoreDataStack {
    static let modelName = "BilingualDesk"

    let container: NSPersistentContainer

    var viewContext: NSManagedObjectContext { container.viewContext }

    /// 模型只加载一次，多个容器（集成测试会建好几个内存库）共用它，
    /// 避免「多个实体描述声明同一个 NSManagedObject 子类」的警告。
    private static let sharedModel: NSManagedObjectModel? = {
        guard let url = Bundle(for: BookEntity.self).url(forResource: modelName, withExtension: "momd") else {
            return nil
        }
        return NSManagedObjectModel(contentsOf: url)
    }()

    private init(container: NSPersistentContainer) {
        self.container = container
    }

    static func load(inMemory: Bool) async throws -> CoreDataStack {
        guard let model = sharedModel else {
            throw CoreDataStackError.modelNotFound
        }
        let container = NSPersistentContainer(name: modelName, managedObjectModel: model)
        if inMemory {
            // 指向 /dev/null 的 SQLite：数据只在内存里，行为（排序、索引、删除规则）与磁盘库一致。
            container.persistentStoreDescriptions = [NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))]
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            container.loadPersistentStores { _, error in
                if let error {
                    continuation.resume(throwing: CoreDataStackError.storeLoadFailed(String(describing: error)))
                } else {
                    continuation.resume()
                }
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.error   // 即 NSErrorMergePolicy
        return CoreDataStack(container: container)
    }

    /// insertBook、paragraphs(bookID:)、deleteBook 用的后台 context（C5）。
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.error   // 即 NSErrorMergePolicy
        return context
    }
}
