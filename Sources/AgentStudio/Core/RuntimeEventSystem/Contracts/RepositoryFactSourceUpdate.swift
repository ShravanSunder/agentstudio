import Foundation

package enum RepositoryFactSource: String, CaseIterable, Hashable, Sendable {
    case localGit = "local_git"
    case remoteReferences = "remote_references"
    case forge
}

package enum RepositoryFactSourceUpdateOutcome: Equatable, Sendable {
    case completed
    case failed
    case obsolete
    case cancelled
}

package struct RepositoryFactSourceUpdateLease: Sendable {
    package let source: RepositoryFactSource
    package let attemptId: UUID
    private let settlementTask: Task<RepositoryFactSourceUpdateOutcome, Never>

    package init(
        source: RepositoryFactSource,
        attemptId: UUID,
        settlementTask: Task<RepositoryFactSourceUpdateOutcome, Never>
    ) {
        self.source = source
        self.attemptId = attemptId
        self.settlementTask = settlementTask
    }

    package func settlement() async -> RepositoryFactSourceUpdateOutcome {
        await settlementTask.value
    }
}

package enum RepositoryFactSourceUpdateAdmission: Sendable {
    case notApplicable
    case obsolete
    case accepted(RepositoryFactSourceUpdateLease)

    package var acceptedLease: RepositoryFactSourceUpdateLease? {
        guard case .accepted(let lease) = self else { return nil }
        return lease
    }
}

struct RepositoryFactSourceUpdateSettlement {
    let lease: RepositoryFactSourceUpdateLease
    let continuation: AsyncStream<RepositoryFactSourceUpdateOutcome>.Continuation

    init(source: RepositoryFactSource, attemptId: UUID) {
        let streamPair = AsyncStream.makeStream(
            of: RepositoryFactSourceUpdateOutcome.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let settlementTask = Task {
            for await outcome in streamPair.stream {
                return outcome
            }
            return .cancelled
        }
        lease = RepositoryFactSourceUpdateLease(
            source: source,
            attemptId: attemptId,
            settlementTask: settlementTask
        )
        continuation = streamPair.continuation
    }

    func resolve(_ outcome: RepositoryFactSourceUpdateOutcome) {
        continuation.yield(outcome)
        continuation.finish()
    }
}
