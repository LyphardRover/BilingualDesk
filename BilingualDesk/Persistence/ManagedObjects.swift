// File: BilingualDesk/Persistence/ManagedObjects.swift
// Targets: App
import Foundation
import CoreData

// 三个手写 NSManagedObject 子类（模型 Codegen = Manual/None，02 §4.5）。
// @objc(类名) 与模型里的 representedClassName 一致，Module 留空。
// 托管对象只在 Persistence/ 内部使用；对外一律用 toDomain() 转成 Domain 值类型（L4）。

@objc(BookEntity)
class BookEntity: NSManagedObject {
    static func request() -> NSFetchRequest<BookEntity> {
        NSFetchRequest<BookEntity>(entityName: "Book")
    }

    @NSManaged var id: UUID
    @NSManaged var title: String
    @NSManaged var importedAt: Date
    @NSManaged var lastOpenedAt: Date?
    @NSManaged var contentHash: String
    @NSManaged var paragraphCount: Int32
    @NSManaged var readingParagraphOrder: Int32
    @NSManaged var bilingualMode: String
    @NSManaged var splitRule: String
    @NSManaged var encodingName: String
    @NSManaged var paragraphs: Set<ReadingParagraphEntity>
    @NSManaged var cards: Set<VocabularyCardEntity>

    /// 非法 rawValue 回退 .bilingual / .blankLine。
    func toDomain() -> Book {
        Book(
            id: id,
            title: title,
            importedAt: importedAt,
            lastOpenedAt: lastOpenedAt,
            contentHash: contentHash,
            paragraphCount: Int(paragraphCount),
            readingParagraphOrder: Int(readingParagraphOrder),
            bilingualMode: BilingualMode(rawValue: bilingualMode) ?? .bilingual,
            splitRule: ParagraphSplitRule(rawValue: splitRule) ?? .blankLine,
            encodingName: encodingName
        )
    }
}

@objc(ReadingParagraphEntity)
class ReadingParagraphEntity: NSManagedObject {
    static func request() -> NSFetchRequest<ReadingParagraphEntity> {
        NSFetchRequest<ReadingParagraphEntity>(entityName: "ReadingParagraph")
    }

    @NSManaged var id: UUID
    @NSManaged var order: Int32
    @NSManaged var text: String
    @NSManaged var sourceHash: String
    @NSManaged var chapterIndex: Int32
    @NSManaged var chapterTitle: String?
    @NSManaged var isChapterHeading: Bool
    @NSManaged var translatedText: String?
    @NSManaged var translatedSourceHash: String?
    @NSManaged var book: BookEntity?
    @NSManaged var cards: Set<VocabularyCardEntity>

    /// bookID 由调用方传入（查询时已知），避免为了取 id 去触发 book 关系的 fault。
    func toDomain(bookID: UUID) -> ReadingParagraph {
        ReadingParagraph(
            id: id,
            bookID: bookID,
            order: Int(order),
            text: text,
            sourceHash: sourceHash,
            chapterIndex: Int(chapterIndex),
            chapterTitle: chapterTitle,
            isChapterHeading: isChapterHeading,
            translatedText: translatedText,
            translatedSourceHash: translatedSourceHash
        )
    }
}

@objc(VocabularyCardEntity)
class VocabularyCardEntity: NSManagedObject {
    static func request() -> NSFetchRequest<VocabularyCardEntity> {
        NSFetchRequest<VocabularyCardEntity>(entityName: "VocabularyCard")
    }

    @NSManaged var id: UUID
    @NSManaged var selectedText: String
    @NSManaged var selectionLocation: Int32
    @NSManaged var selectionLength: Int32
    @NSManaged var contextText: String
    @NSManaged var contextTranslation: String?
    @NSManaged var machineHint: String?
    @NSManaged var hintStatus: String
    @NSManaged var userMeaningOverride: String?
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var sourceBookID: UUID?
    @NSManaged var sourceBookTitle: String
    @NSManaged var sourceParagraphOrder: Int32
    @NSManaged var sourceBook: BookEntity?
    @NSManaged var sourceParagraph: ReadingParagraphEntity?

    /// sourceParagraphID = sourceParagraph?.id（移出书库后为 nil）；非法 hintStatus 回退 .pending。
    func toDomain() -> VocabularyCard {
        VocabularyCard(
            id: id,
            selectedText: selectedText,
            selectionLocation: Int(selectionLocation),
            selectionLength: Int(selectionLength),
            contextText: contextText,
            contextTranslation: contextTranslation,
            machineHint: machineHint,
            hintStatus: MachineHintStatus(rawValue: hintStatus) ?? .pending,
            userMeaningOverride: userMeaningOverride,
            createdAt: createdAt,
            updatedAt: updatedAt,
            sourceBookID: sourceBookID,
            sourceBookTitle: sourceBookTitle,
            sourceParagraphOrder: Int(sourceParagraphOrder),
            sourceParagraphID: sourceParagraph?.id
        )
    }
}
