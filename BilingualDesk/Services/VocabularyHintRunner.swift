// File: BilingualDesk/Services/VocabularyHintRunner.swift
// Targets: App
import Foundation

/// 收藏后在后台生成机器中文提示（02 §9.8 F42；BR-SAVE-9、BR-HINT-1…6）。
/// 每张词卡同一时刻最多一个任务；错误只写进词卡状态，不弹窗。
@MainActor
final class VocabularyHintRunner: VocabularyHintRequesting {
    private let generateHint: GenerateVocabularyHint
    private let hintFinished: @MainActor () -> Void
    private var runningTasks: [UUID: Task<Void, Never>] = [:]

    /// hintFinished：每个任务结束（成功、失败或丢弃）后调用一次，用来通知单词本刷新。
    init(generateHint: GenerateVocabularyHint, hintFinished: @escaping @MainActor () -> Void = {}) {
        self.generateHint = generateHint
        self.hintFinished = hintFinished
    }

    func requestHint(for cardID: UUID) {
        guard runningTasks[cardID] == nil else { return }
        let generateHint = self.generateHint
        // Task 在主 actor 上创建，继承主 actor；Use Case 本身也是 @MainActor。
        runningTasks[cardID] = Task { [weak self] in
            do {
                _ = try await generateHint.execute(cardID: cardID)
            } catch {
                // 失败状态已由 GenerateVocabularyHint 写入词卡（BR-HINT-4），读者在单词本里看到 “Machine hint not generated”。
                #if DEBUG
                print("VocabularyHintRunner: hint for \(cardID) not generated: \(error)")
                #endif
            }
            self?.runningTasks[cardID] = nil
            self?.hintFinished()
        }
    }
}
