import Foundation

actor BadProducerGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
}

final class BadReadBarrier: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
}

final class BadCommitLatch: @unchecked Sendable {
    private let condition: NSCondition = NSCondition()
}

actor BadStateHold {
    private struct State {
        var continuation: UnsafeContinuation<Void, Never>?
    }
    private var state = State()
}

func waitUntilDrained() async {}

func requireFocusCommitted() async throws {}

func expectRowsEventually() async {}
