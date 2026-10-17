// File: BilingualDesk/Domain/Services.swift
// Targets: App
import Foundation
import Combine

// MARK: - TXT 解析

/// 解析器的底层错误；ImportTXTBook 把它映射成 ImportTXTBookError（02 §8.1）。
enum TXTParseError: Error, Equatable {
    case emptyFile
    case unknownEncoding
    case notPlainText
    case noReadableText
}

/// 同步、纯数据的解析接口（实现：F18 FoundationTXTParser）。
/// 只抛 TXTParseError 或 CancellationError；实现每处理 500 行调用一次 try Task.checkCancellation()。
protocol TXTParsing: Sendable {
    func parse(_ data: Data, splitRule: ParagraphSplitRule) throws -> ParsedBook
}

// MARK: - 翻译

enum TranslationAvailability: Equatable, Sendable {
    case ready                      // 可以去翻译（语言已安装；真机 F40 对 .supported 也报这个，SV-1）
    case needsDownload              // 支持但未下载（真机 F40 不再返回，真没下载由翻译报 notInstalled，SV-2）
    case unsupportedLanguagePair
    case simulatorUnsupported
}

enum TranslationProviderError: Error, Equatable {
    case notInstalled
    case unsupportedLanguagePair
    case simulatorUnsupported
    case failed
}

/// en → zh-Hans 设备端翻译（实现：F40 AppleTranslationProvider）。
/// 只抛 TranslationProviderError 或 CancellationError。
@MainActor
protocol TranslationProviding: AnyObject {
    func availability() async -> TranslationAvailability
    func translateEnglishToChinese(_ text: String) async throws -> String
}

// MARK: - 朗读

/// 三档语速，对应 AVSpeechUtterance.rate 0.40 / 0.50 / 0.58（界面不标倍速）。
enum SpeechRate: String, CaseIterable, Identifiable, Sendable {
    case slower
    case normal
    case faster

    var id: String { rawValue }

    var utteranceRate: Float {
        switch self {
        case .slower: return 0.40
        case .normal: return 0.50
        case .faster: return 0.58
        }
    }

    var title: String {
        switch self {
        case .slower: return AppText.T.settingsRateSlower
        case .normal: return AppText.T.settingsRateNormal
        case .faster: return AppText.T.settingsRateFaster
        }
    }
}

struct SpeechParagraph: Equatable, Sendable {
    let order: Int
    let text: String
}

enum SpeechState: Equatable, Sendable {
    case idle
    case pronouncing
    case reading(bookID: UUID, paragraphOrder: Int)
    case paused(bookID: UUID, paragraphOrder: Int)

    /// 连续朗读（含暂停）时所属的书；其他状态为 nil（BR-REMOVE-2、RD-8 用它判断要不要停）。
    var bookID: UUID? {
        switch self {
        case .reading(let bookID, _), .paused(let bookID, _):
            return bookID
        case .idle, .pronouncing:
            return nil
        }
    }
}

enum SpeechError: UserFacingError, Equatable {
    case noEnglishVoice
    case audioSessionUnavailable

    var message: String {
        switch self {
        case .noEnglishVoice: return AppText.E.speechNoVoice
        case .audioSessionUnavailable: return AppText.E.speechAudioUnavailable
        }
    }
}

/// 发音与前台连续朗读（实现：F41 SpeechPlayer，全 App 只有一个实例）。
@MainActor
protocol SpeechPlaying: AnyObject {
    var state: SpeechState { get }
    /// 先发当前值，之后每次变化发一次。
    var statePublisher: AnyPublisher<SpeechState, Never> { get }
    /// 先停止任何朗读，再读出 text。
    func pronounce(_ text: String, rate: SpeechRate) throws
    func startReading(bookID: UUID, paragraphs: [SpeechParagraph], rate: SpeechRate) throws
    /// 从下一段起生效。
    func setRate(_ rate: SpeechRate)
    func pause()
    func resume()
    func stop()
}

// MARK: - Widget 快照

/// 生成并写入 Widget 快照、刷新时间线（实现：F45 WidgetSnapshotPublisher）。
/// 只在 02 §11.3 的 P1–P8 调用；永不抛错，失败只在 DEBUG 打印。
@MainActor
protocol WidgetSnapshotPublishing: AnyObject {
    func publish() async
}
