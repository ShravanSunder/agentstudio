import AgentStudioInfrastructure
import Foundation

/// Session-owned operation results. Admission and settlement are serialized by
/// BridgeProductSession; provider tasks never own a result slot themselves.
struct BridgeProductOperationTable {
    struct Entry {
        let admission: BridgeProductSessionPendingControl
        let operationId: String
        let waitKind: BridgeProductOperationWaitKind
        var deadlineTask: Task<Void, Never>?
        var executionTask: Task<Void, Never>?
        var resultWaiters: [UUID: CheckedContinuation<BridgeProductOperationResultResponse?, Never>] = [:]
        var settlement: BridgeProductOperationResultResponse?
    }

    private(set) var entriesById: [String: Entry] = [:]
    private(set) var executionTasksById: [String: Task<Void, Never>] = [:]
    private var operationIdByToken: [BridgeProductControlAdmissionToken: String] = [:]

    func entry(for token: BridgeProductControlAdmissionToken) -> Entry? {
        guard let operationId = operationIdByToken[token] else { return nil }
        return entriesById[operationId]
    }

    func hasCapacity(for waitKind: BridgeProductOperationWaitKind) -> Bool {
        let capacity: Int =
            switch waitKind {
            case .ordinary: AppPolicies.Bridge.maximumOrdinaryProductOperations
            case .human: AppPolicies.Bridge.maximumHumanWaitProductOperations
            }
        return entriesById.values.filter { $0.waitKind == waitKind }.count < capacity
    }

    mutating func admit(
        operationId: String,
        waitKind: BridgeProductOperationWaitKind,
        admission: BridgeProductSessionPendingControl
    ) {
        precondition(hasCapacity(for: waitKind))
        precondition(entriesById[operationId] == nil)
        entriesById[operationId] = Entry(
            admission: admission,
            operationId: operationId,
            waitKind: waitKind
        )
        operationIdByToken[admission.token] = operationId
    }

    mutating func registerTasks(
        operationId: String,
        executionTask: Task<Void, Never>,
        deadlineTask: Task<Void, Never>?
    ) {
        guard var entry = entriesById[operationId], entry.settlement == nil else {
            executionTask.cancel()
            deadlineTask?.cancel()
            return
        }
        entry.executionTask = executionTask
        entry.deadlineTask = deadlineTask
        entriesById[operationId] = entry
        executionTasksById[operationId] = executionTask
    }

    mutating func finishExecution(operationId: String) {
        executionTasksById.removeValue(forKey: operationId)
    }

    @discardableResult
    mutating func observeResult(
        operationId: String,
        waiterId: UUID,
        continuation: CheckedContinuation<BridgeProductOperationResultResponse?, Never>
    ) -> Bool {
        guard var entry = entriesById[operationId] else {
            continuation.resume(returning: nil)
            return false
        }
        if let settlement = entry.settlement {
            continuation.resume(returning: settlement)
            return false
        }
        // Keep the optional at the session boundary so an unknown id can be
        // reported without fabricating an operation settlement.
        entry.resultWaiters[waiterId] = continuation
        entriesById[operationId] = entry
        return true
    }

    mutating func cancelResultWaiter(operationId: String, waiterId: UUID) {
        guard var entry = entriesById[operationId],
            let waiter = entry.resultWaiters.removeValue(forKey: waiterId)
        else { return }
        entriesById[operationId] = entry
        waiter.resume(returning: nil)
    }

    @discardableResult
    mutating func settle(_ result: BridgeProductOperationResultResponse) -> Bool {
        guard var entry = entriesById[result.operationId], entry.settlement == nil else {
            return false
        }
        entry.settlement = result
        entry.deadlineTask?.cancel()
        let waiters = Array(entry.resultWaiters.values)
        entry.resultWaiters.removeAll(keepingCapacity: false)
        entriesById[result.operationId] = entry
        for waiter in waiters {
            waiter.resume(returning: result)
        }
        return true
    }

    mutating func acknowledge(operationId: String) -> Bool {
        guard let entry = entriesById[operationId], entry.settlement != nil else { return false }
        entry.deadlineTask?.cancel()
        entriesById.removeValue(forKey: operationId)
        operationIdByToken.removeValue(forKey: entry.admission.token)
        return true
    }

    mutating func cancelUnsettledOperations() {
        for task in executionTasksById.values { task.cancel() }
        for operationId in Array(entriesById.keys) {
            guard let entry = entriesById[operationId], entry.settlement == nil else { continue }
            settle(
                BridgeProductOperationResultResponse(
                    operationId: operationId,
                    outcome: .cancelled
                )
            )
        }
    }

    mutating func cancelAndForgetAllOperations() {
        cancelUnsettledOperations()
        for entry in entriesById.values {
            entry.deadlineTask?.cancel()
        }
        entriesById.removeAll(keepingCapacity: false)
        operationIdByToken.removeAll(keepingCapacity: false)
    }
}
