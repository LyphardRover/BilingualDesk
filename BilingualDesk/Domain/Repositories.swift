// File: BilingualDesk/Domain/Repositories.swift
// Targets: App
import Foundation

/// 仓库层的底层错误。不直接显示给用户：Use Case 负责映射成自己的错误枚举（ER-3）。
enum RepositoryError: Error, Equatable {
    case bookNotFound
    case paragraphNotFound
    case cardNotFound
    case duplicateContentHash
    case storageFailed(String)   // 底层错误描述，仅供调试
}

/// 书与段落的数据访问（02 §6）。只接收、返回 Domain 值类型（L4）；
/// 不做业务校验（长度、去空白等由 Use Case 负责），只做存在性与唯一性检查。
@MainActor
protocol BookRepository: AnyObject {
    func books(matching searchText: String) async throws -> [Book]
    func book(id: UUID) async throws -> Book?
    func book(contentHash: String) async throws -> Book?
    func insertBook(_ record: NewBookRecord) async throws -> Book
    func paragraphs(bookID: UUID) async throws -> [ReadingParagraph]
    func paragraph(bookID: UUID, order: Int) async throws -> ReadingParagraph?
    func chapters(bookID: UUID) async throws -> [ReadingChapter]
    func saveTranslation(paragraphID: UUID, text: String, sourceHash: String) async throws
    func saveReadingPosition(bookID: UUID, paragraphOrder: Int, at date: Date) async throws -> Book
    func markOpened(bookID: UUID, at date: Date) async throws -> Book
    func saveBilingualMode(bookID: UUID, mode: BilingualMode) async throws -> Book
    func deleteBook(id: UUID) async throws
}

/// 词卡的数据访问（02 §6）。「待补中文」谓词由实现方定义（F16）。
@MainActor
protocol VocabularyRepository: AnyObject {
    func cards(matching searchText: String, needsChineseOnly: Bool) async throws -> [VocabularyCard]
    func card(id: UUID) async throws -> VocabularyCard?
    func card(paragraphID: UUID, location: Int, length: Int) async throws -> VocabularyCard?
    func insertCard(_ draft: VocabularyCardDraft, at date: Date) async throws -> VocabularyCard
    func saveMachineHint(cardID: UUID, hint: String, at date: Date) async throws -> VocabularyCard?
    func markMachineHintFailed(cardID: UUID, at date: Date) async throws -> VocabularyCard?
    func saveUserMeaning(cardID: UUID, meaning: String?, at date: Date) async throws -> VocabularyCard
    func deleteCard(id: UUID) async throws
    func latestCard() async throws -> VocabularyCard?
    func countCardsNeedingChinese() async throws -> Int
}
