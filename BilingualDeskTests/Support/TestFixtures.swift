// File: BilingualDeskTests/Support/TestFixtures.swift
// Targets: Tests
import Foundation
@testable import BilingualDesk

/// 02 §16.1 的固定样本 TXT 与解析器测试用的字节。
/// 手动验收用的 BilingualDeskSample.txt 必须与 sampleText 逐字相同（UTF-8、LF、末尾无换行）。
enum TXTSamples {
    static let sampleText = """
        Prologue

        The café opened early. A curious student kept reading. 🙂

        She wrote "curious" in her notebook.
        The next line belongs to the same paragraph.

        Chapter 1

        The rain stopped.

        The rain stopped.

        Chapter 2

        A lead pencil lay beside the book. She would lead the group tomorrow.
        """

    /// 按 “Blank Lines”（`.blankLine`）分段后的第 2 段（order 1），curious 第一次出现在这里。
    static let curiousParagraph = "The café opened early. A curious student kept reading. 🙂"

    /// curious 在 curiousParagraph 中的 UTF-16 范围（02 §16.1 样本预期）。
    static let curiousRange = NSRange(location: 25, length: 7)

    static var utf8: Data {
        Data(sampleText.utf8)
    }

    /// FF FE + 小端 UTF-16 编码单元。
    static var utf16LittleEndianWithBOM: Data {
        var bytes: [UInt8] = [0xFF, 0xFE]
        for unit in sampleText.utf16 {
            bytes.append(UInt8(unit & 0x00FF))
            bytes.append(UInt8(unit >> 8))
        }
        return Data(bytes)
    }

    /// 0xFF 不可能出现在合法 UTF-8 里。
    static let invalidUTF8 = Data([0x43, 0xFF, 0x55])

    /// "Team: 👩🏽‍💻👨‍👩‍👧 rocks"：含肤色修饰符和零宽连接符（U+200D，Cf 类，不是控制字符）。
    static let emojiWithZeroWidthJoiner = "Team: \u{1F469}\u{1F3FD}\u{200D}\u{1F4BB}\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467} rocks"

    /// BR-IMPORT-8 必须接受的 8 个章节标题。
    static let acceptedHeadings: [String] = [
        "Chapter 1",
        "CHAPTER 12",
        "Chapter IV",
        "Chapter 3: The Escape",
        "Chapter 7 - Home",
        "Chapter 2. A New Day",
        "Prologue",
        "Epilogue"
    ]

    /// BR-IMPORT-8 必须拒绝的 3 个句子。
    static let rejectedHeadings: [String] = [
        "Chapter 1 was boring, so she closed the book.",
        "Chapter I cried for an hour.",
        "chapter mix tape"
    ]
}

/// 书、段、词卡的工厂。默认值对应 01 §8 的验收场景（书名 My English Story、8 段、收藏 curious）。
enum Fixtures {
    /// 2026-10-12T09:00:00Z
    static let fixedDate = Date(timeIntervalSince1970: 1_791_795_600)

    static func book(
        id: UUID = UUID(),
        title: String = "My English Story",
        paragraphCount: Int = 8,
        readingParagraphOrder: Int = 0,
        contentHash: String = "hash-1"
    ) -> Book {
        Book(
            id: id,
            title: title,
            importedAt: fixedDate,
            lastOpenedAt: nil,
            contentHash: contentHash,
            paragraphCount: paragraphCount,
            readingParagraphOrder: readingParagraphOrder,
            bilingualMode: .bilingual,
            splitRule: .blankLine,
            encodingName: "UTF-8"
        )
    }

    /// sourceHash = 段文字的 SHA-256；有译文时 translatedSourceHash 取同一个 hash（= 有效缓存）。
    static func paragraph(bookID: UUID, order: Int, text: String, translatedText: String? = nil) -> ReadingParagraph {
        let hash = TextFingerprint.sha256Hex(text)
        return ReadingParagraph(
            id: UUID(),
            bookID: bookID,
            order: order,
            text: text,
            sourceHash: hash,
            chapterIndex: 0,
            chapterTitle: nil,
            isChapterHeading: false,
            translatedText: translatedText,
            translatedSourceHash: translatedText == nil ? nil : hash
        )
    }

    static func card(
        id: UUID = UUID(),
        selectedText: String = "curious",
        paragraphID: UUID? = UUID(),
        userMeaningOverride: String? = nil,
        hintStatus: MachineHintStatus = .pending,
        machineHint: String? = nil
    ) -> VocabularyCard {
        VocabularyCard(
            id: id,
            selectedText: selectedText,
            selectionLocation: 25,
            selectionLength: selectedText.utf16.count,
            contextText: "A curious student kept reading.",
            contextTranslation: nil,
            machineHint: machineHint,
            hintStatus: hintStatus,
            userMeaningOverride: userMeaningOverride,
            createdAt: fixedDate,
            updatedAt: fixedDate,
            sourceBookID: UUID(),
            sourceBookTitle: "My English Story",
            sourceParagraphOrder: 1,
            sourceParagraphID: paragraphID
        )
    }
}
