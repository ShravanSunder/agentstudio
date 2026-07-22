@testable import AgentStudio

actor ProducerLifecycleAcknowledgementGate {
    private var acknowledgements: [BridgeProductProducerLifecycleAcknowledgement] = []
    private var invocationWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var releaseContinuations: [CheckedContinuation<Bool, Never>] = []
    private var releaseCredits = 0

    var acknowledgedLeases: [BridgeProductProducerLease] {
        acknowledgements.map(\.producerLease)
    }

    func acknowledge(
        _ acknowledgement: BridgeProductProducerLifecycleAcknowledgement
    ) async -> Bool {
        acknowledgements.append(acknowledgement)
        resumeSatisfiedInvocationWaiters()
        return await withCheckedContinuation { continuation in
            if releaseCredits > 0 {
                releaseCredits -= 1
                continuation.resume(returning: true)
            } else {
                releaseContinuations.append(continuation)
            }
        }
    }

    func waitForInvocationCount(_ count: Int) async {
        if acknowledgements.count >= count { return }
        await withCheckedContinuation { continuation in
            invocationWaiters.append((count: count, continuation: continuation))
        }
    }

    func releaseNext() {
        guard !releaseContinuations.isEmpty else {
            releaseCredits += 1
            return
        }
        releaseContinuations.removeFirst().resume(returning: true)
    }

    private func resumeSatisfiedInvocationWaiters() {
        var pendingWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in invocationWaiters {
            if acknowledgements.count >= waiter.count {
                waiter.continuation.resume()
            } else {
                pendingWaiters.append(waiter)
            }
        }
        invocationWaiters = pendingWaiters
    }
}
