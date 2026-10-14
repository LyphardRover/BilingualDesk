// File: BilingualDeskTests/Support/MockWidgetSnapshotPublisher.swift
// Targets: Tests
import Foundation
@testable import BilingualDesk

@MainActor
final class MockWidgetSnapshotPublisher: WidgetSnapshotPublishing {
    private(set) var publishCount = 0

    init() {}

    func publish() async {
        publishCount += 1
    }
}
