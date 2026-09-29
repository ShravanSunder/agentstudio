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
                preconditionFailure("Only refresh facts belong to a refresh scope")
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
}

private struct UnexpectedProjectorEnvelopeSequence: Error {
    let expected: UInt64
    let actual: UInt64
}
