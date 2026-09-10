import Foundation

@testable import AgentStudioCore

actor SuspendedForgeStatusProvider: ForgeStatusProvider {
    private struct PendingCall {
        let continuation: CheckedContinuation<ForgePullRequestQueryOutcome, Never>
    }

    private var pendingCalls: [PendingCall] = []
    private var startedCallCount = 0
    private var activeCallCount = 0
    private var startedCallWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var maximumActiveCallCount = 0

    var startedCount: Int { startedCallCount }

    func pullRequests(
        origin _: String,
        demandedBranches _: Set<String>
    ) async -> ForgePullRequestQueryOutcome {
        startedCallCount += 1
        activeCallCount += 1
        maximumActiveCallCount = max(maximumActiveCallCount, activeCallCount)
        resumeSatisfiedStartedCallWaiters()
        defer { activeCallCount -= 1 }
        return await withCheckedContinuation { continuation in
            pendingCalls.append(PendingCall(continuation: continuation))
        }
    }

    func waitForStartedCallCount(_ expectedCount: Int) async {
        guard startedCallCount < expectedCount else { return }
        await withCheckedContinuation { continuation in
            startedCallWaiters.append((expectedCount, continuation))
        }
    }

    func finishNextCall(returning counts: [String: Int]) {
        let pendingCall = pendingCalls.removeFirst()
        let pullRequests = counts.flatMap { branch, count in
            (0..<count).map { index in
                ForgePullRequest(
                    headRefName: branch,
                    url: URL(string: "https://example.test/pull/\(index)")!
                )
            }
        }
        pendingCall.continuation.resume(returning: .complete(pullRequests))
    }

    func failNextCall() {
        pendingCalls.removeFirst().continuation.resume(returning: .failed(message: "failed"))
    }

    private func resumeSatisfiedStartedCallWaiters() {
        var pendingWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
        for (expectedCount, continuation) in startedCallWaiters {
            if startedCallCount >= expectedCount {
                continuation.resume()
            } else {
                pendingWaiters.append((expectedCount, continuation))
            }
        }
        startedCallWaiters = pendingWaiters
    }
}

actor SequencedForgeStatusProvider: ForgeStatusProvider {
    private var results: [[String: Int]]
    private var callCount = 0
    private var callCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(results: [[String: Int]]) {
        self.results = results
    }

    func pullRequests(
        origin _: String,
        demandedBranches _: Set<String>
    ) async -> ForgePullRequestQueryOutcome {
        let result = results.removeFirst()
        callCount += 1
        resumeSatisfiedCallCountWaiters()
        let pullRequests = result.flatMap { branch, count in
            (0..<count).map { index in
                ForgePullRequest(
                    headRefName: branch,
                    url: URL(string: "https://example.test/pull/\(index)")!
                )
            }
        }
        return .complete(pullRequests)
    }

    func waitForCallCount(_ expectedCount: Int) async {
        guard callCount < expectedCount else { return }
        await withCheckedContinuation { continuation in
            callCountWaiters.append((expectedCount, continuation))
        }
    }

    private func resumeSatisfiedCallCountWaiters() {
        var pendingWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
        for (expectedCount, continuation) in callCountWaiters {
            if callCount >= expectedCount {
                continuation.resume()
            } else {
                pendingWaiters.append((expectedCount, continuation))
            }
        }
        callCountWaiters = pendingWaiters
    }
}

actor CancellationObservingForgeStatusProvider: ForgeStatusProvider {
    private var didStart = false
    private var didCancel = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []

    var didObserveCancellation: Bool { didCancel }

    func pullRequests(
        origin _: String,
        demandedBranches _: Set<String>
    ) async -> ForgePullRequestQueryOutcome {
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters {
            waiter.resume()
        }

        while !Task.isCancelled {
            await Task.yield()
        }

        didCancel = true
        let pendingCancellationWaiters = cancellationWaiters
        cancellationWaiters.removeAll(keepingCapacity: false)
        for waiter in pendingCancellationWaiters {
            waiter.resume()
        }
        return .failed(message: "cancelled")
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func waitUntilCancelled() async {
        guard !didCancel else { return }
        await withCheckedContinuation { continuation in
            cancellationWaiters.append(continuation)
        }
    }
}
