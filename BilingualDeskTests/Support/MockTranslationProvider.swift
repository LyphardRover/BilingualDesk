// File: BilingualDeskTests/Support/MockTranslationProvider.swift
// Targets: Tests
import Foundation
@testable import BilingualDesk

@MainActor
final class MockTranslationProvider: TranslationProviding {
    // MARK: 可设置
    var availabilityToReturn: TranslationAvailability = .ready
    var resultToReturn: Result<String, TranslationProviderError> = .success("译文")
    /// 在返回结果前执行，用来插入「翻译还没回来时发生的事」。
    var beforeReturning: (@MainActor () async -> Void)?

    // MARK: 可检查
    private(set) var translatedTexts: [String] = []

    init() {}

    func availability() async -> TranslationAvailability {
        availabilityToReturn
    }

    func translateEnglishToChinese(_ text: String) async throws -> String {
        translatedTexts.append(text)
        if let beforeReturning {
            await beforeReturning()
        }
        return try resultToReturn.get()
    }
}
