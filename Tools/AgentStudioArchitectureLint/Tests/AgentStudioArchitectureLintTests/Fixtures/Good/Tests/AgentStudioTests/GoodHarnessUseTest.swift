import Foundation

struct GoodCountingGate {
    var count = 0
}

final class GoodEventRecorder: @unchecked Sendable {
    private var waiters: [CheckedContinuation<Void, Never>] = []
}

func waitUntilDrained() async -> Int { 1 }

func requireFocusCommitted() async throws -> String { "" }

func waitsForNothing() async {}

func requiredValue() async {}
