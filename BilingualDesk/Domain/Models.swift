// File: BilingualDesk/Domain/Models.swift
// Targets: App
import Foundation
import CryptoKit

// MARK: - 面向用户的错误

/// 所有 Use Case 错误枚举都遵守它；message 只返回 01 §6 的 E- 文案（ER-1）。
protocol UserFacingError: Error {
    var message: String { get }
}

// MARK: - 枚举

/// 每本书的显示模式（按书保存在 Book.bilingualMode）。
enum BilingualMode: String, CaseIterable, Identifiable, Sendable {
    case bilingual
    case englishOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bilingual: return AppText.T.settingsModeBilingual
        case .englishOnly: return AppText.T.settingsModeEnglishOnly
        }
    }
}

/// 导入时选择的分段规则（BR-IMPORT-7）。
enum ParagraphSplitRule: String, CaseIterable, Identifiable, Sendable {
    case blankLine
    case eachLine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blankLine: return AppText.T.importSplitBlankLine
        case .eachLine: return AppText.T.importSplitEachLine
        }
    }
}

/// 机器中文提示的生成状态（存为 VocabularyCard.hintStatus 字符串）。
enum MachineHintStatus: String, Sendable {
    case pending
    case ready
    case failed
}

// MARK: - 书与段落

struct Book: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let importedAt: Date
    let lastOpenedAt: Date?
    let contentHash: String
    let paragraphCount: Int
    let readingParagraphOrder: Int
    let bilingualMode: BilingualMode
    let splitRule: ParagraphSplitRule
    let encodingName: String

    /// 已读百分比（02 §5）：段数 ≤ 1 → 0；否则按「保存的段序号 / 最后一段序号」四舍五入，夹到 0...100。
    var progressPercent: Int {
        guard paragraphCount > 1 else { return 0 }
        let ratio = Double(readingParagraphOrder) / Double(paragraphCount - 1) * 100
        return min(100, max(0, Int(ratio.rounded())))
    }
}

struct ReadingParagraph: Identifiable, Equatable, Sendable {
    let id: UUID
    let bookID: UUID
    let order: Int
    let text: String
    let sourceHash: String
    let chapterIndex: Int
    let chapterTitle: String?
    let isChapterHeading: Bool
    let translatedText: String?
    let translatedSourceHash: String?

    /// 有效缓存译文：生成译文时的 sourceHash 与当前一致，且去空白后非空（BR-TR-1）。
    var validTranslation: String? {
        guard let translatedText,
              translatedSourceHash == sourceHash,
              !translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return translatedText
    }
}

struct ReadingChapter: Identifiable, Equatable, Sendable {
    let title: String
    let startOrder: Int

    var id: Int { startOrder }
}

// MARK: - 词卡

/// 词卡在单词本、Widget 中显示的「中文含义」（02 §5 的确定规则）。
enum VocabularyMeaning: Equatable, Sendable {
    case personal(String)
    case leftBlank
    case machine(String)
    case hintPending
    case hintFailed

    var displayText: String {
        switch self {
        case .personal(let text): return text
        case .leftBlank: return AppText.T.meaningLeftBlank
        case .machine(let hint): return hint
        case .hintPending: return AppText.T.meaningHintPending
        case .hintFailed: return AppText.T.meaningHintFailed
        }
    }
}

struct VocabularyCard: Identifiable, Equatable, Sendable {
    let id: UUID
    let selectedText: String
    let selectionLocation: Int
    let selectionLength: Int
    let contextText: String
    let contextTranslation: String?
    let machineHint: String?
    let hintStatus: MachineHintStatus
    let userMeaningOverride: String?
    let createdAt: Date
    let updatedAt: Date
    let sourceBookID: UUID?
    let sourceBookTitle: String
    let sourceParagraphOrder: Int
    let sourceParagraphID: UUID?

    /// 来源段还在书库中（移出书库后关系被置空 → false）。
    var isSourceAvailable: Bool { sourceParagraphID != nil }

    /// 「待补中文」：没有个人理解，且机器提示不是 ready（与 02 §4.4 的谓词等价）。
    var needsChinese: Bool { userMeaningOverride == nil && hintStatus != .ready }

    var meaning: VocabularyMeaning {
        if let userMeaningOverride {
            return userMeaningOverride.isEmpty ? .leftBlank : .personal(userMeaningOverride)
        }
        switch hintStatus {
        case .ready:
            if let machineHint, !machineHint.isEmpty { return .machine(machineHint) }
            return .hintFailed
        case .pending:
            return .hintPending
        case .failed:
            return .hintFailed
        }
    }
}

/// 收藏时交给 VocabularyRepository.insertCard 的草稿；仓库「原样」保存这些字段。
struct VocabularyCardDraft: Equatable, Sendable {
    let selectedText: String
    let selectionLocation: Int
    let selectionLength: Int
    let contextText: String
    let contextTranslation: String?
    let sourceBookID: UUID
    let sourceBookTitle: String
    let sourceParagraphID: UUID
    let sourceParagraphOrder: Int
}

struct VocabularySaveResult: Equatable, Sendable {
    let card: VocabularyCard
    let wasCreated: Bool
}

/// 阅读页长按选词得到的原始选区（UTF-16 位置与长度，未去空白）。
struct ParagraphSelection: Equatable, Sendable {
    let bookID: UUID
    let paragraphID: UUID
    let paragraphOrder: Int
    let location: Int
    let length: Int
    let selectedText: String
}

// MARK: - 导入

enum ImportOrigin: Hashable, Sendable {
    case filePicker
    case shareInbox(itemID: UUID)
}

/// 待导入的一份文件：文件名 + 原始字节 + 来源。
struct ImportCandidate: Identifiable, Hashable, Sendable {
    let id: UUID
    let fileName: String
    let data: Data
    let origin: ImportOrigin

    init(id: UUID = UUID(), fileName: String, data: Data, origin: ImportOrigin) {
        self.id = id
        self.fileName = fileName
        self.data = data
        self.origin = origin
    }
}

struct ParsedParagraph: Equatable, Sendable {
    let order: Int
    let text: String
    let sourceHash: String
    let chapterIndex: Int
    let chapterTitle: String?
    let isChapterHeading: Bool
}

struct ParsedBook: Equatable, Sendable {
    let contentHash: String
    let encodingName: String
    let splitRule: ParagraphSplitRule
    let paragraphs: [ParsedParagraph]

    /// 章节数 = 章节标题段的个数。
    var chapterCount: Int { paragraphs.filter(\.isChapterHeading).count }
}

struct ImportPreview: Equatable, Sendable {
    let candidate: ImportCandidate
    let parsed: ParsedBook
    let defaultTitle: String
    let previewParagraphs: [String]
}

/// 交给 BookRepository.insertBook 的新书记录（全部段落，不截断）。
struct NewBookRecord: Equatable, Sendable {
    let id: UUID
    let title: String
    let importedAt: Date
    let contentHash: String
    let encodingName: String
    let splitRule: ParagraphSplitRule
    let paragraphs: [ParsedParagraph]
}

enum ImportOutcome: Equatable, Sendable {
    case imported(Book)
    case alreadyInLibrary(Book)

    var book: Book {
        switch self {
        case .imported(let book), .alreadyInLibrary(let book):
            return book
        }
    }
}

// MARK: - 限制常量（数字的唯一定义在 01 开头，这里只是代码入口）

enum ImportLimits {
    static let maximumFileBytes = SharedConfiguration.maximumTXTBytes
    static let maximumTitleLength = 120
    static let previewParagraphCount = 5
    static let previewCharactersPerParagraph = 600
}

enum VocabularyLimits {
    static let maximumSelectionLength = 200
    static let maximumMeaningLength = 500
}

// MARK: - 指纹

/// SHA-256，输出 64 位小写十六进制（BR-IMPORT-9）。
enum TextFingerprint {
    static func sha256Hex(_ data: Data) -> String {
        let digits = Array("0123456789abcdef".utf8)
        var hex: [UInt8] = []
        hex.reserveCapacity(64)
        for byte in SHA256.hash(data: data) {
            hex.append(digits[Int(byte >> 4)])
            hex.append(digits[Int(byte & 0x0F)])
        }
        return String(decoding: hex, as: UTF8.self)
    }

    static func sha256Hex(_ text: String) -> String {
        sha256Hex(Data(text.utf8))
    }
}
