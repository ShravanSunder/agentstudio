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

    fileprivate init(transaction: WorkspacePersistenceTransaction) {
        self.transaction = transaction
    }

    func commit<TransactionResult>(
        _ body: @escaping @MainActor () -> TransactionResult
    ) -> WorkspacePersistencePreparedMutation<TransactionResult> {
        WorkspacePersistencePreparedMutation(body: body)
    }
}

struct WorkspacePersistencePreparedMutation<TransactionResult> {
    fileprivate let body: @MainActor () -> TransactionResult

    fileprivate init(body: @escaping @MainActor () -> TransactionResult) {
        self.body = body
    }
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
        case preparing(WorkspacePersistenceTransaction)
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
        guard case .idle = state else {
            throw WorkspacePersistenceRevisionOwnerError.reentrantTransaction
        }
        let transaction = WorkspacePersistenceTransaction(
            processGeneration: processGeneration,
            expectedPreviousRevision: committedRevision,
            proposedRevision: committedRevision.next()
        )
        state = .preparing(transaction)
        defer { state = .idle }

        let preparedMutation = try prepare(WorkspacePersistenceTransactionPreparation(transaction: transaction))
        state = .committing(transaction)
        let result = preparedMutation.body()
        committedRevision = transaction.proposedRevision
        return result
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
