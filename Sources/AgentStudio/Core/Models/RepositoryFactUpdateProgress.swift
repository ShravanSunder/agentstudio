import Foundation

package enum RepositoryFactUpdatePhase: Equatable, Sendable {
    case captured
    case inProgress
    case settled
}

package enum RepositoryFactUpdateSourceResult: Equatable, Sendable {
    case notApplicable
    case completed
    case failed
    case obsolete
    case cancelled

    package init(_ outcome: RepositoryFactSourceUpdateOutcome) {
        switch outcome {
        case .completed:
            self = .completed
        case .failed:
            self = .failed
        case .obsolete:
            self = .obsolete
        case .cancelled:
            self = .cancelled
        }
    }
}

package struct RepositoryFactUpdateProgress: Equatable, Sendable {
    package let repoId: UUID
    package let attemptId: UUID
    package let phase: RepositoryFactUpdatePhase
    package let applicableSources: Set<RepositoryFactSource>
    package let unsettledSources: Set<RepositoryFactSource>
    package let settledResultsBySource: [RepositoryFactSource: RepositoryFactUpdateSourceResult]

    package var isLoading: Bool {
        !unsettledSources.isEmpty
    }

    package static func captured(repoId: UUID, attemptId: UUID) -> Self {
        Self(
            repoId: repoId,
            attemptId: attemptId,
            phase: .captured,
            applicableSources: [],
            unsettledSources: [],
            settledResultsBySource: [:]
        )
    }

    package static func admitted(
        repoId: UUID,
        attemptId: UUID,
        applicableSources: Set<RepositoryFactSource>,
        terminalResultsBySource: [RepositoryFactSource: RepositoryFactUpdateSourceResult]
    ) -> Self {
        Self(
            repoId: repoId,
            attemptId: attemptId,
            phase: applicableSources.isEmpty ? .settled : .inProgress,
            applicableSources: applicableSources,
            unsettledSources: applicableSources,
            settledResultsBySource: terminalResultsBySource
        )
    }

    package func settled(
        _ outcomesBySource: [RepositoryFactSource: RepositoryFactSourceUpdateOutcome]
    ) -> Self {
        var resultsBySource = settledResultsBySource
        for (source, outcome) in outcomesBySource {
            resultsBySource[source] = RepositoryFactUpdateSourceResult(outcome)
        }
        return Self(
            repoId: repoId,
            attemptId: attemptId,
            phase: .settled,
            applicableSources: applicableSources,
            unsettledSources: [],
            settledResultsBySource: resultsBySource
        )
    }
}
