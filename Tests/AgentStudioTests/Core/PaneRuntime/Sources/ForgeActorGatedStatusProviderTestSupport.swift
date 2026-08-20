import Foundation
import Testing

@testable import AgentStudioCore

actor GatedForgeStatusProvider: ForgeStatusProvider {
    private struct PendingCall {
        let origin: String
        let continuation: CheckedContinuation<ForgePullRequestQueryOutcome, Never>
    }

    private struct CallCountWaiter {
        let expectedCount: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private var calls: [PendingCall] = []
    private var callCountWaiters: [CallCountWaiter] = []

    var callCount: Int { calls.count }
    var origins: [String] { calls.map(\.origin) }

    func pullRequests(origin: String) async -> ForgePullRequestQueryOutcome {
        await withCheckedContinuation { continuation in
            calls.append(PendingCall(origin: origin, continuation: continuation))
            resumeSatisfiedCallCountWaiters()
        }
    }

    func resolve(callAt index: Int, with outcome: ForgePullRequestQueryOutcome) {
        guard calls.indices.contains(index) else {
            Issue.record("No Forge provider call at index \(index); recorded \(calls.count)")
            return
        }
        calls[index].continuation.resume(returning: outcome)
    }

    func resolveIfPresent(callAt index: Int, with outcome: ForgePullRequestQueryOutcome) {
        guard calls.indices.contains(index) else { return }
        calls[index].continuation.resume(returning: outcome)
    }

    func waitForCallCount(_ expectedCount: Int) async -> Bool {
        if calls.count < expectedCount {
            await withCheckedContinuation { continuation in
                callCountWaiters.append(
                    CallCountWaiter(
                        expectedCount: expectedCount,
                        continuation: continuation
                    )
                )
            }
        }
        return true
    }

    private func resumeSatisfiedCallCountWaiters() {
        var remainingWaiters: [CallCountWaiter] = []
        for waiter in callCountWaiters {
            if calls.count >= waiter.expectedCount {
                waiter.continuation.resume()
            } else {
                remainingWaiters.append(waiter)
            }
        }
        callCountWaiters = remainingWaiters
    }
}
