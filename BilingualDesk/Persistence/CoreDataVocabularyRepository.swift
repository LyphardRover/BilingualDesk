// File: BilingualDesk/Persistence/CoreDataVocabularyRepository.swift
// Targets: App
import Foundation
import CoreData

/// VocabularyRepository 的 Core Data 实现（02 §6 语义表、§4.4 谓词），全部在 viewContext 上执行。
@MainActor
final class CoreDataVocabularyRepository: VocabularyRepository {
    /// 「待补中文」：还没写个人理解，且机器提示生成中或失败（A3 要求的领域谓词，02 §4.4）。
    /// cards(matching:needsChineseOnly:) 与 countCardsNeedingChinese() 共用这一个常量。
    static let needsChinesePredicate = NSPredicate(
        format: "userMeaningOverride == nil AND hintStatus IN %@",
        [MachineHintStatus.pending.rawValue, MachineHintStatus.failed.rawValue]
    )

    private let stack: CoreDataStack

    init(stack: CoreDataStack) {
        self.stack = stack
    }

    private var viewContext: NSManagedObjectContext { stack.viewContext }

    // MARK: - 查询

    func cards(matching searchText: String, needsChineseOnly: Bool) async throws -> [VocabularyCard] {
        var predicates: [NSPredicate] = []
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            predicates.append(NSPredicate(format: "selectedText CONTAINS[cd] %@", query))
        }
        if needsChineseOnly {
            predicates.append(Self.needsChinesePredicate)
        }
        let request = VocabularyCardEntity.request()
        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return try fetch(request).map { $0.toDomain() }
    }

    func card(id: UUID) async throws -> VocabularyCard? {
        try fetchCard(id: id)?.toDomain()
    }

    func card(paragraphID: UUID, location: Int, length: Int) async throws -> VocabularyCard? {
        let request = VocabularyCardEntity.request()
        request.predicate = NSPredicate(
            format: "sourceParagraph.id == %@ AND selectionLocation == %d AND selectionLength == %d",
            paragraphID as NSUUID, Int32(clamping: location), Int32(clamping: length)
        )
        request.fetchLimit = 1
        return try fetch(request).first?.toDomain()
    }

    func latestCard() async throws -> VocabularyCard? {
        let request = VocabularyCardEntity.request()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        request.fetchLimit = 1
        return try fetch(request).first?.toDomain()
    }

    func countCardsNeedingChinese() async throws -> Int {
        let request = VocabularyCardEntity.request()
        request.predicate = Self.needsChinesePredicate
        do {
            return try viewContext.count(for: request)
        } catch {
            throw RepositoryError.storageFailed(String(describing: error))
        }
    }

    // MARK: - 写入

    /// 原样保存 draft 的全部字段；hintStatus = pending，机器提示与个人理解为 nil。
    func insertCard(_ draft: VocabularyCardDraft, at date: Date) async throws -> VocabularyCard {
        let paragraphRequest = ReadingParagraphEntity.request()
        paragraphRequest.predicate = NSPredicate(format: "id == %@", draft.sourceParagraphID as NSUUID)
        paragraphRequest.fetchLimit = 1
        guard let paragraph = try fetch(paragraphRequest).first else {
            throw RepositoryError.paragraphNotFound
        }

        let card = VocabularyCardEntity(context: viewContext)
        card.id = UUID()
        card.selectedText = draft.selectedText
        card.selectionLocation = Int32(clamping: draft.selectionLocation)
        card.selectionLength = Int32(clamping: draft.selectionLength)
        card.contextText = draft.contextText
        card.contextTranslation = draft.contextTranslation
        card.machineHint = nil
        card.hintStatus = MachineHintStatus.pending.rawValue
        card.userMeaningOverride = nil
        card.createdAt = date
        card.updatedAt = date
        card.sourceBookID = draft.sourceBookID
        card.sourceBookTitle = draft.sourceBookTitle
        card.sourceParagraphOrder = Int32(clamping: draft.sourceParagraphOrder)
        card.sourceParagraph = paragraph
        card.sourceBook = paragraph.book
        try saveViewContext()
        return card.toDomain()
    }

    /// 只写 machineHint / hintStatus / updatedAt，不碰 userMeaningOverride（BR-HINT-5）。卡不存在返回 nil。
    func saveMachineHint(cardID: UUID, hint: String, at date: Date) async throws -> VocabularyCard? {
        guard let card = try fetchCard(id: cardID) else { return nil }
        card.machineHint = hint
        card.hintStatus = MachineHintStatus.ready.rawValue
        card.updatedAt = date
        try saveViewContext()
        return card.toDomain()
    }

    /// hintStatus = failed；machineHint 保持不变。卡不存在返回 nil。
    func markMachineHintFailed(cardID: UUID, at date: Date) async throws -> VocabularyCard? {
        guard let card = try fetchCard(id: cardID) else { return nil }
        card.hintStatus = MachineHintStatus.failed.rawValue
        card.updatedAt = date
        try saveViewContext()
        return card.toDomain()
    }

    /// meaning 原样写入：nil = 没写（显示机器提示），"" = 已留空。
    func saveUserMeaning(cardID: UUID, meaning: String?, at date: Date) async throws -> VocabularyCard {
        guard let card = try fetchCard(id: cardID) else {
            throw RepositoryError.cardNotFound
        }
        card.userMeaningOverride = meaning
        card.updatedAt = date
        try saveViewContext()
        return card.toDomain()
    }

    /// 幂等：词卡不存在不抛错。
    func deleteCard(id: UUID) async throws {
        guard let card = try fetchCard(id: id) else { return }
        viewContext.delete(card)
        try saveViewContext()
    }

    // MARK: - 私有

    private func fetchCard(id: UUID) throws -> VocabularyCardEntity? {
        let request = VocabularyCardEntity.request()
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
