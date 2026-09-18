import Foundation

package struct AgentStudioIPCCredentialPersistenceDrainResult: Equatable, Sendable {
    package let failedOperationCount: Int

    package init(failedOperationCount: Int) {
        self.failedOperationCount = failedOperationCount
    }
}

package protocol AgentStudioIPCCredentialContinuityPort: Sendable {
    func registerIssuedPaneCredential(
        _ credential: AgentStudioIPCIssuedPaneCredential,
        if remainsEligible: @escaping @Sendable () -> Bool
    ) async throws -> Bool

    func revokeAllPaneCredentials(paneID: UUID) async throws
}

package final class AgentStudioIPCCredentialPersistenceLane: @unchecked Sendable {
    private enum Operation: Sendable {
        case register(
            credential: AgentStudioIPCIssuedPaneCredential,
            remainsEligible: @Sendable () -> Bool,
            didPersist: @Sendable () -> Void
        )
        case revokeAll(paneID: UUID)

        var registrationRecordID: UUID? {
            guard case .register(let credential, _, _) = self else { return nil }
            return credential.credentialRecordID
        }
    }

    private struct State {
        var operations: [Operation] = []
        var queuedRegistrationRecordIDs: Set<UUID> = []
        var isWorkerRunning = false
        var failureCount = 0
        var drainWaiters: [CheckedContinuation<AgentStudioIPCCredentialPersistenceDrainResult, Never>] = []
    }

    private let lock = NSLock()
    private let continuityPort: any AgentStudioIPCCredentialContinuityPort
    private var state = State()

    package init(continuityPort: any AgentStudioIPCCredentialContinuityPort) {
        self.continuityPort = continuityPort
    }

    package func enqueueRegistration(
        _ credential: AgentStudioIPCIssuedPaneCredential,
        remainsEligible: @escaping @Sendable () -> Bool,
        didPersist: @escaping @Sendable () -> Void
    ) {
        guard remainsEligible() else { return }
        enqueue(.register(credential: credential, remainsEligible: remainsEligible, didPersist: didPersist))
    }

    package func enqueueFinalRevoke(paneID: UUID) {
        enqueue(.revokeAll(paneID: paneID))
    }

    package func drain() async -> AgentStudioIPCCredentialPersistenceDrainResult {
        await withCheckedContinuation { continuation in
            let immediateResult = lock.withLock { () -> AgentStudioIPCCredentialPersistenceDrainResult? in
                guard state.isWorkerRunning || !state.operations.isEmpty else {
                    let result = AgentStudioIPCCredentialPersistenceDrainResult(
                        failedOperationCount: state.failureCount)
                    state.failureCount = 0
                    return result
                }
                state.drainWaiters.append(continuation)
                return nil
            }
            if let immediateResult { continuation.resume(returning: immediateResult) }
        }
    }

    private func enqueue(_ operation: Operation) {
        let shouldStartWorker = lock.withLock {
            if let recordID = operation.registrationRecordID {
                guard state.queuedRegistrationRecordIDs.insert(recordID).inserted else { return false }
            }
            state.operations.append(operation)
            guard !state.isWorkerRunning else { return false }
            state.isWorkerRunning = true
            return true
        }
        guard shouldStartWorker else { return }
        Task { await runOperationsInFIFOOrder() }
    }

    private func runOperationsInFIFOOrder() async {
        while let operation = takeNextOperation() {
            let succeeded = await execute(operation)
            finish(operation, succeeded: succeeded)
        }
        finishDraining()
    }

    private func takeNextOperation() -> Operation? {
        lock.withLock {
            guard !state.operations.isEmpty else { return nil }
            return state.operations.removeFirst()
        }
    }

    private func execute(_ operation: Operation) async -> Bool {
        do {
            switch operation {
            case .register(let credential, let remainsEligible, let didPersist):
                if try await continuityPort.registerIssuedPaneCredential(
                    credential,
                    if: remainsEligible
                ) {
                    didPersist()
                }
            case .revokeAll(let paneID):
                try await continuityPort.revokeAllPaneCredentials(paneID: paneID)
            }
            return true
        } catch {
            return false
        }
    }

    private func finish(_ operation: Operation, succeeded: Bool) {
        lock.withLock {
            if let recordID = operation.registrationRecordID {
                state.queuedRegistrationRecordIDs.remove(recordID)
            }
            if !succeeded { state.failureCount += 1 }
        }
    }

    private func finishDraining() {
        let settlement = lock.withLock {
            () -> (
                [CheckedContinuation<AgentStudioIPCCredentialPersistenceDrainResult, Never>],
                AgentStudioIPCCredentialPersistenceDrainResult,
                Bool
            ) in
            if !state.operations.isEmpty {
                return ([], .init(failedOperationCount: 0), true)
            }
            state.isWorkerRunning = false
            let waiters = state.drainWaiters
            state.drainWaiters.removeAll(keepingCapacity: false)
            let result = AgentStudioIPCCredentialPersistenceDrainResult(
                failedOperationCount: state.failureCount)
            if !waiters.isEmpty { state.failureCount = 0 }
            return (waiters, result, false)
        }
        if settlement.2 {
            Task { await runOperationsInFIFOOrder() }
            return
        }
        for waiter in settlement.0 { waiter.resume(returning: settlement.1) }
    }
}
