// File: BilingualDesk/Import/FoundationTXTParser.swift
// Targets: App
import Foundation

/// TXT 解析器（BR-IMPORT-2…9、12）：编码识别 → 换行规范化 → 纯文本判定 → 分段 → 章节 → 哈希。
/// 同步、纯数据，不碰数据库和界面；ImportTXTBook 在主线程以外调用它（C3）。
struct FoundationTXTParser: TXTParsing {
    /// BR-IMPORT-8 的章节正则（与 02 §8.1 逐字一致）。关键字不分大小写（内联 (?i:)），
    /// 罗马数字只认大写；编号后只能是行尾，或「分隔符 : . - – — + 短标题」。
    static let chapterHeadingPattern = #"^(?:(?i:chapter)\s+(?:[0-9]{1,4}|[IVXLCDM]{1,8})(?:\s*[:.\-–—](?:\s*\S.*)?)?|(?i:prologue|epilogue))$"#

    /// 章节标题行的最大字符数（去首尾空白后）。
    private static let maximumHeadingLength = 80
    /// 每处理这么多行检查一次取消。
    private static let linesPerCancellationCheck = 500

    init() {}

    func parse(_ data: Data, splitRule: ParagraphSplitRule) throws -> ParsedBook {
        guard !data.isEmpty else { throw TXTParseError.emptyFile }

        // BR-IMPORT-3：编码识别（UTF-32 BOM 先于 UTF-16 BOM 判定）。
        let decoded = try Self.decode(data)
        // 解码后含 U+0000：多半是没有 BOM 的 UTF-16，按「无法识别编码」处理。
        if decoded.text.unicodeScalars.contains(where: { $0.value == 0 }) {
            throw TXTParseError.unknownEncoding
        }
        try Task.checkCancellation()

        // BR-IMPORT-4：先 CRLF → LF，再 CR → LF。
        let normalized = decoded.text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // BR-IMPORT-5：只数 Cc 类控制字符（排除 Tab、LF、CR）；Cf 类（ZWJ、软连字符等）不算。
        var scalarCount = 0
        var controlCount = 0
        for scalar in normalized.unicodeScalars {
            scalarCount += 1
            if scalar.properties.generalCategory == .control,
               scalar.value != 0x09, scalar.value != 0x0A, scalar.value != 0x0D {
                controlCount += 1
            }
        }
        if controlCount > max(2, scalarCount / 100) {
            throw TXTParseError.notPlainText
        }

        // BR-IMPORT-6：去空白后为空。
        if normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw TXTParseError.noReadableText
        }
        try Task.checkCancellation()

        // BR-IMPORT-7/8：分段与章节标题。
        let segments = try Self.makeSegments(normalized, splitRule: splitRule)
        guard !segments.isEmpty else { throw TXTParseError.noReadableText }

        // BR-IMPORT-9/12：连续 order、章节编号与标题、段哈希。
        var paragraphs: [ParsedParagraph] = []
        paragraphs.reserveCapacity(segments.count)
        var chapterIndex = 0
        var chapterTitle: String?
        for (order, segment) in segments.enumerated() {
            if order % Self.linesPerCancellationCheck == 0 {
                try Task.checkCancellation()
            }
            if segment.isHeading {
                chapterIndex += 1
                chapterTitle = segment.text
            }
            paragraphs.append(ParsedParagraph(
                order: order,
                text: segment.text,
                sourceHash: TextFingerprint.sha256Hex(segment.text),
                chapterIndex: chapterIndex,
                chapterTitle: chapterTitle,
                isChapterHeading: segment.isHeading
            ))
        }

        return ParsedBook(
            contentHash: TextFingerprint.sha256Hex(data),   // 原始字节，不是解码后的文本
            encodingName: decoded.name,
            splitRule: splitRule,
            paragraphs: paragraphs
        )
    }

    // MARK: - 编码

    private static func decode(_ data: Data) throws -> (text: String, name: String) {
        let bytes = [UInt8](data)
        func starts(with prefix: [UInt8]) -> Bool {
            bytes.count >= prefix.count && Array(bytes[0..<prefix.count]) == prefix
        }

        // UTF-32 BOM 的前两个字节与 UTF-16 LE BOM 相同，必须先判断，不能让它冒充 UTF-16。
        if starts(with: [0xFF, 0xFE, 0x00, 0x00]) || starts(with: [0x00, 0x00, 0xFE, 0xFF]) {
            throw TXTParseError.unknownEncoding
        }
        if starts(with: [0xEF, 0xBB, 0xBF]) {
            guard let text = String(data: Data(bytes[3...]), encoding: .utf8) else {
                throw TXTParseError.unknownEncoding
            }
            return (text, "UTF-8 (BOM)")
        }
        if starts(with: [0xFF, 0xFE]) {
            return (try decodeUTF16(Array(bytes[2...]), littleEndian: true), "UTF-16 LE (BOM)")
        }
        if starts(with: [0xFE, 0xFF]) {
            return (try decodeUTF16(Array(bytes[2...]), littleEndian: false), "UTF-16 BE (BOM)")
        }
        // 没有 BOM：只接受严格 UTF-8（坏字节直接失败，不用 � 替换）。
        guard let text = String(data: data, encoding: .utf8) else {
            throw TXTParseError.unknownEncoding
        }
        return (text, "UTF-8")
    }

    /// 严格 UTF-16：字节数必须为偶数，代理项必须成对，否则 unknownEncoding。
    private static func decodeUTF16(_ bytes: [UInt8], littleEndian: Bool) throws -> String {
        guard bytes.count % 2 == 0 else { throw TXTParseError.unknownEncoding }
        var units: [UInt16] = []
        units.reserveCapacity(bytes.count / 2)
        var index = 0
        while index < bytes.count {
            let first = UInt16(bytes[index])
            let second = UInt16(bytes[index + 1])
            units.append(littleEndian ? (first | (second << 8)) : ((first << 8) | second))
            index += 2
        }

        var position = 0
        while position < units.count {
            let unit = units[position]
            if (0xD800...0xDBFF).contains(unit) {
                guard position + 1 < units.count, (0xDC00...0xDFFF).contains(units[position + 1]) else {
                    throw TXTParseError.unknownEncoding
                }
                position += 2
            } else if (0xDC00...0xDFFF).contains(unit) {
                throw TXTParseError.unknownEncoding
            } else {
                position += 1
            }
        }
        return String(decoding: units, as: UTF16.self)
    }

    // MARK: - 分段

    private struct Segment {
        let text: String
        let isHeading: Bool
    }

    /// BR-IMPORT-7：每行先去首尾空格/制表符。
    /// blankLine：连续非空行用一个空格连成一段，空行结束一段；章节标题行总是单独成段并结束前一段。
    /// eachLine：每个非空行一段。空行不产生段。
    private static func makeSegments(_ text: String, splitRule: ParagraphSplitRule) throws -> [Segment] {
        let expression = try! NSRegularExpression(pattern: chapterHeadingPattern)   // 固定常量，U06 验证
        var segments: [Segment] = []
        var pendingLines: [String] = []

        func flushPending() {
            guard !pendingLines.isEmpty else { return }
            segments.append(Segment(text: pendingLines.joined(separator: " "), isHeading: false))
            pendingLines.removeAll(keepingCapacity: true)
        }

        for (lineNumber, rawLine) in text.components(separatedBy: "\n").enumerated() {
            if lineNumber % linesPerCancellationCheck == 0 {
                try Task.checkCancellation()
            }
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushPending()
                continue
            }
            let isHeading = isChapterHeading(line, expression: expression)
            switch splitRule {
            case .eachLine:
                segments.append(Segment(text: line, isHeading: isHeading))
            case .blankLine:
                if isHeading {
                    flushPending()
                    segments.append(Segment(text: line, isHeading: true))
                } else {
                    pendingLines.append(line)
                }
            }
        }
        flushPending()
        return segments
    }

    /// BR-IMPORT-8：去空白后 ≤ 80 个字符，且整行匹配章节正则（NSRegularExpression，无额外 options）。
    private static func isChapterHeading(_ line: String, expression: NSRegularExpression) -> Bool {
        guard line.count <= maximumHeadingLength else { return false }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return expression.firstMatch(in: line, options: [], range: range) != nil
    }
}
