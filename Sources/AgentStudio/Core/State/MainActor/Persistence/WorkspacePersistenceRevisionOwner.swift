import Foundation

struct WorkspacePersistenceProcessGeneration: Hashable, Sendable {
    let rawValue: UUID

    static func make() -> Self {
        Self(rawValue: UUIDv7.generate())
    }

    var isUUIDv7: Bool {
        UUIDv7.isV7(rawValue)
    }
}

struct WorkspacePersistenceRevision: Hashable, Sendable, Comparable {
    let rawValue: UInt64

    static let zero = Self(ownedRawValue: 0)

    fileprivate init(ownedRawValue: UInt64) {
        rawValue = ownedRawValue
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    fileprivate func next() -> Self {
        let (nextRawValue, overflowed) = rawValue.addingReportingOverflow(1)
        precondition(!overflowed, "workspace persistence revision exhausted")
        return Self(ownedRawValue: nextRawValue)
    }
}

struct WorkspacePersistenceTransaction: Hashable, Sendable {
    let processGeneration: WorkspacePersistenceProcessGeneration
    let expectedPreviousRevision: WorkspacePersistenceRevision
    let proposedRevision: WorkspacePersistenceRevision

    fileprivate init(
        processGeneration: WorkspacePersistenceProcessGeneration,
        expectedPreviousRevision: WorkspacePersistenceRevision,
        proposedRevision: WorkspacePersistenceRevision
    ) {
        self.processGeneration = processGeneration
        self.expectedPreviousRevision = expectedPreviousRevision
        self.proposedRevision = proposedRevision
    }
}

struct WorkspacePersistenceTransactionPreparation: Sendable {
    let transaction: WorkspacePersistenceTransaction
    fileprivate let participantMutations: WorkspacePreparedParticipantCustody

    func commit<TransactionResult>(
        _ body: @escaping @MainActor () -> TransactionResult
    ) -> WorkspacePersistencePreparedMutation<TransactionResult> {
        WorkspacePersistencePreparedMutation(body: body)
    }
}

@MainActor
private final class WorkspacePreparedParticipantCustody {
    private struct Entry {
        let apply: @MainActor () -> Void
        let cancel: @MainActor () -> Void
    }

    private enum State {
        case collecting(participantIdentities: Set<ObjectIdentifier>, entries: [Entry])
        case consumed
    }

    private var state: State = .collecting(participantIdentities: [], entries: [])

    func append(
        participant: AnyObject,
        apply: @escaping @MainActor () -> Void,
        cancel: @escaping @MainActor () -> Void
    ) -> WorkspaceParticipantRegistration {
        guard case .collecting(var participantIdentities, var entries) = state else {
            return .rejected(.transactionNotPreparing)
        }
        guard participantIdentities.insert(ObjectIdentifier(participant)).inserted else {
            return .rejected(.participantAlreadyPrepared)
        }
        entries.append(Entry(apply: apply, cancel: cancel))
        state = .collecting(participantIdentities: participantIdentities, entries: entries)
        return .registered
    }

    func applyAll() {
        guard case .collecting(_, let entries) = state else {
            preconditionFailure("prepared participant custody was consumed more than once")
        }
        state = .consumed
        for entry in entries { entry.apply() }
    }

    func cancelIfCollecting() {
        guard case .collecting(_, let entries) = state else { return }
        state = .consumed
        for entry in entries { entry.cancel() }
    }
}

enum WorkspaceParticipantRegistration: Equatable, Sendable {
    case registered
    case rejected(WorkspaceParticipantRegistrationRejection)
}

enum WorkspaceParticipantRegistrationRejection: Equatable, Sendable {
    case participantAlreadyPrepared
    case preparationCustodyMismatch
    case transactionNotPreparing
    case transactionMismatch
}

struct WorkspacePersistencePreparedMutation<TransactionResult> {
    fileprivate let body: @MainActor () -> TransactionResult

    fileprivate init(body: @escaping @MainActor () -> TransactionResult) {
        self.body = body
    }
}

enum WorkspacePersistenceTransactionDecision<TransactionResult> {
    case unchanged(TransactionResult)
    case commit(WorkspacePersistencePreparedMutation<TransactionResult>)
}

enum WorkspacePersistenceRevisionOwnerError: Error, Equatable {
    case reentrantTransaction
}

enum WorkspacePersistenceActiveTransactionValidation: Equatable, Sendable {
    case active
    case rejected(WorkspacePersistenceActiveTransactionRejection)
}

enum WorkspacePersistenceActiveTransactionRejection: Equatable, Sendable {
    case notCommitting
    case transactionMismatch
}

/// Process-local MainActor authority for canonical persistence revisions.
///
/// The transaction body is deliberately synchronous. The proposed revision is
/// published only after the body returns successfully, so rejected work cannot
/// create a gap in the canonical revision stream.
@MainActor
final class WorkspacePersistenceRevisionOwner {
    private enum State {
        case idle
        case preparing(
            WorkspacePersistenceTransaction,
            WorkspacePreparedParticipantCustody
        )
        case committing(WorkspacePersistenceTransaction)
    }

    let processGeneration: WorkspacePersistenceProcessGeneration
    private(set) var committedRevision: WorkspacePersistenceRevision = .zero
    private var state: State = .idle

    init(processGeneration: WorkspacePersistenceProcessGeneration = .make()) {
        precondition(processGeneration.isUUIDv7, "workspace persistence process generation must be UUIDv7")
        self.processGeneration = processGeneration
    }

    func performSynchronousTransaction<TransactionResult>(
        _ prepare: (WorkspacePersistenceTransactionPreparation) throws -> WorkspacePersistencePreparedMutation<
            TransactionResult
        >
    ) throws -> TransactionResult {
        try performSynchronousTransactionDecision { preparation in
            WorkspacePersistenceTransactionDecision.commit(try prepare(preparation))
        }
    }

    func performSynchronousTransactionDecision<TransactionResult>(
        _ prepare: (WorkspacePersistenceTransactionPreparation) throws
            -> WorkspacePersistenceTransactionDecision<TransactionResult>
    ) throws -> TransactionResult {
        guard case .idle = state else {
            throw WorkspacePersistenceRevisionOwnerError.reentrantTransaction
        }
        let transaction = WorkspacePersistenceTransaction(
            processGeneration: processGeneration,
            expectedPreviousRevision: committedRevision,
            proposedRevision: committedRevision.next()
        )
        let participantMutations = WorkspacePreparedParticipantCustody()
        state = .preparing(transaction, participantMutations)
        defer {
            participantMutations.cancelIfCollecting()
            state = .idle
        }

        let decision = try prepare(
            WorkspacePersistenceTransactionPreparation(
                transaction: transaction,
                participantMutations: participantMutations
            )
        )
        switch decision {
        case .unchanged(let result):
            return result
        case .commit(let preparedMutation):
            state = .committing(transaction)
            participantMutations.applyAll()
            let result = preparedMutation.body()
            committedRevision = transaction.proposedRevision
            return result
        }
    }

    func registerPreparedParticipantMutation(
        participant: AnyObject,
        preparation: WorkspacePersistenceTransactionPreparation,
        apply: @escaping @MainActor () -> Void,
        cancel: @escaping @MainActor () -> Void
    ) -> WorkspaceParticipantRegistration {
        guard case .preparing(let activeTransaction, let activeParticipantMutations) = state else {
            return .rejected(.transactionNotPreparing)
        }
        guard activeTransaction == preparation.transaction else {
            return .rejected(.transactionMismatch)
        }
        guard activeParticipantMutations === preparation.participantMutations else {
            return .rejected(.preparationCustodyMismatch)
        }
        return preparation.participantMutations.append(participant: participant, apply: apply, cancel: cancel)
    }

    func validateActiveCommit(
        _ transaction: WorkspacePersistenceTransaction
    ) -> WorkspacePersistenceActiveTransactionValidation {
        guard case .committing(let activeTransaction) = state else {
            return .rejected(.notCommitting)
        }
        guard activeTransaction == transaction else {
            return .rejected(.transactionMismatch)
        }
        return .active
    }
}
