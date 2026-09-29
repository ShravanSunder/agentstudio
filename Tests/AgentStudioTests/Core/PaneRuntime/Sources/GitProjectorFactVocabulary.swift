import AgentStudioTestHarness
import Foundation

@testable import AgentStudioCore

extension FactVocabulary<GitProjectorScope, GitProjectorFact> {
    static let gitProjector = FactVocabulary(
        describeScope: { String(describing: $0) },
        describeFact: { String(describing: $0) },
        isClosing: { scope, fact in
            switch (scope, fact) {
            case (.intake(_, _), .changesetAccepted),
                (.intake(_, _), .changesetCoalesced(_)),
                (.intake(_, _), .changesetDropped(_)),
                (.refresh(_, _), .refreshClosed(_)),
                (.deadline(_, _, _), .deadlineDisposition(_)),
                (.capacity(_, _), .capacityRetryClosed(_)),
                (.backoff(_, _), .backoffClosed),
                (.quarantine(_, _), .quarantineClosed),
                (.lifetime(_), .shutdownCompleted):
                true
            default:
                false
            }
        }
    )
}

extension FactRecorder where Scope == GitProjectorScope, Fact == GitProjectorFact {
    func expectNextRefreshStarted(worktreeId: UUID) async throws -> UInt64 {
        let scope = try await expectNextOperation(
            matching: {
                if case .refresh(let scopedWorktreeId, _) = $0 { return scopedWorktreeId == worktreeId }
                return false
            }, opening: { $0 == .refreshAdmitted }, "refresh admitted for \(worktreeId)"
        )
        guard case .refresh(_, let requestSequence) = scope else {
            throw UnexpectedFact.forExpectation(
                expected: "refresh scope", actual: String(describing: scope),
                scope: String(describing: scope), callSite: #function)
        }
        try await expectRefreshStarted(worktreeId: worktreeId, requestSequence: requestSequence)
        return requestSequence
    }

    func expectRefreshStarted(worktreeId: UUID, requestSequence: UInt64) async throws {
        let scope = GitProjectorScope.refresh(worktreeId: worktreeId, requestSequence: requestSequence)
        try await expectNext(in: scope, .refreshAdmitted)
        try await expectNext(in: scope, .refreshStarted)
    }

    func expectRefreshClosed(
        worktreeId: UUID,
        requestSequence: UInt64
    ) async throws -> GitProjectorRefreshOutcome {
        let scope = GitProjectorScope.refresh(worktreeId: worktreeId, requestSequence: requestSequence)
        while true {
            let fact = try await expectNext(in: scope, where: { _ in true }, "refresh closed")
            switch fact {
            case .refreshAdmitted, .refreshStarted:
                continue
            case .refreshClosed(let outcome):
                return outcome
            default:
                throw UnexpectedFact.forExpectation(
                    expected: "refresh fact", actual: String(describing: fact),
                    scope: String(describing: scope), callSite: #function)
            }
        }
    }

    /// Consume earlier input facts in this lifetime and stop at the requested envelope.
    /// Each iteration awaits an emitted fact; no scheduler turn or elapsed time decides the verdict.
    func expectHandledEnvelope(
        seq expectedSequence: UInt64,
        lifetime: UInt64 = 1
    ) async throws -> GitProjectorEnvelopeDisposition {
        while true {
            let fact = try await expectNext(
                in: .lifetime(lifetime), where: { _ in true }, "envelope handled through sequence \(expectedSequence)"
            )
            guard case .envelopeHandled(let sequence, let disposition) = fact else { continue }
            if sequence == expectedSequence { return disposition }
            if sequence > expectedSequence {
                throw UnexpectedProjectorEnvelopeSequence(expected: expectedSequence, actual: sequence)
            }
        }
    }

    func expectShutdownCompleted(lifetime: UInt64 = 1) async throws -> UInt64 {
        var droppedEnvelopes: UInt64 = 0
        while true {
            let fact = try await expectNext(
                in: .lifetime(lifetime), where: { _ in true }, "shutdown completed"
            )
            switch fact {
            case .envelopesDropped(let count):
                droppedEnvelopes &+= count
            case .envelopeHandled:
                continue
            case .shutdownCompleted:
                try await finish()
                return droppedEnvelopes
            default:
                throw UnexpectedFact.forExpectation(
                    expected: "lifetime fact", actual: String(describing: fact),
                    scope: String(describing: GitProjectorScope.lifetime(lifetime)), callSite: #function)
            }
        }
    }

    func expectNoDroppedEnvelopes(from opening: OpeningPosition<GitProjectorScope>) async throws {
        try await expectNone(
            of: {
                if case .envelopesDropped = $0 { return true }
                return false
            },
            "dropped projector envelopes",
            from: opening,
            closedBy: { $0 == .shutdownCompleted }
        )
        try await finish()
    }
}

private struct UnexpectedProjectorEnvelopeSequence: Error {
    let expected: UInt64
    let actual: UInt64
}

/// Adapts the projector's fact sink to the local recorder.
final class GitProjectorFactSource: Sendable {
    private let localSource = LocalFactSource(
        vocabulary: FactVocabulary<GitProjectorScope, GitProjectorFact>.gitProjector)

    var sink: GitProjectorFactSink {
        localSource.sink
    }

    func attach() throws -> FactRecorder<GitProjectorScope, GitProjectorFact> {
        try localSource.attach()
    }

    func expectNextRefreshClosed(
        facts: FactRecorder<GitProjectorScope, GitProjectorFact>,
        worktreeId: UUID
    ) async throws -> GitProjectorRefreshOutcome {
        let scope = try await facts.expectNextOperation(
            matching: {
                if case .refresh(let scopedWorktreeId, _) = $0 { return scopedWorktreeId == worktreeId }
                return false
            }, opening: { $0 == .refreshAdmitted }, "refresh admitted for \(worktreeId)"
        )
        guard case .refresh(_, let requestSequence) = scope else {
            throw UnexpectedFact.forExpectation(
                expected: "refresh scope", actual: String(describing: scope),
                scope: String(describing: scope), callSite: #function)
        }
        return try await facts.expectRefreshClosed(worktreeId: worktreeId, requestSequence: requestSequence)
    }

    func expectDeadlineRegistered(
        facts: FactRecorder<GitProjectorScope, GitProjectorFact>,
        worktreeId: UUID,
        kind: GitProjectorDeadlineKind
    ) async throws -> GitProjectorScope {
        let description = "\(kind) deadline registered for \(worktreeId)"
        let scope = try await facts.expectNextOperation(
            matching: {
                if case .deadline(let scopedWorktreeId, let scopedKind, _) = $0 {
                    return scopedWorktreeId == worktreeId && scopedKind == kind
                }
                return false
            }, opening: { $0 == .deadlineRegistered(kind) }, description
        )
        try await facts.expectNext(in: scope, .deadlineRegistered(kind))
        return scope
    }

    func expectDeadlineRegistered(
        facts: FactRecorder<GitProjectorScope, GitProjectorFact>,
        kind: GitProjectorDeadlineKind
    ) async throws -> GitProjectorScope {
        let scope = try await facts.expectNextOperation(
            matching: {
                if case .deadline(_, let scopedKind, _) = $0 { return scopedKind == kind }
                return false
            }, opening: { $0 == .deadlineRegistered(kind) }, "\(kind) deadline registered"
        )
        try await facts.expectNext(in: scope, .deadlineRegistered(kind))
        return scope
    }
}
