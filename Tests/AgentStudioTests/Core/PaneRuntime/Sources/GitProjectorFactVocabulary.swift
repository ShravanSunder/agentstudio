import AgentStudioTestHarness
import Foundation
import Synchronization

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

/// Retains only deadline identities emitted by the injected sink. Tests still
/// consume and verify the corresponding fact through FactRecorder; this source
/// resolves a dynamic generation without reading projector scheduler state.
final class GitProjectorFactSource: Sendable {
    private let localSource = LocalFactSource(
        vocabulary: FactVocabulary<GitProjectorScope, GitProjectorFact>.gitProjector)
    private let deadlineScopes = Mutex(DeadlineScopeState())

    var sink: GitProjectorFactSink {
        { [self] scope, fact in
            self.localSource.sink(scope, fact)
            guard case .deadlineRegistered(let kind) = fact,
                case .deadline(let worktreeId, let scopedKind, _) = scope,
                kind == scopedKind
            else { return }
            let key = DeadlineKey(worktreeId: worktreeId, kind: kind)
            let waiters = self.deadlineScopes.withLock { state -> [CheckedContinuation<GitProjectorScope, Never>] in
                var resumed: [CheckedContinuation<GitProjectorScope, Never>] = []
                if let waiter = state.waiters.removeValue(forKey: key) {
                    resumed.append(waiter)
                } else {
                    state.pending[key, default: []].append(scope)
                }
                if let waiter = state.anyWorktreeWaiters.removeValue(forKey: kind) {
                    resumed.append(waiter)
                } else {
                    state.anyWorktreePending[kind, default: []].append(scope)
                }
                return resumed
            }
            for waiter in waiters { waiter.resume(returning: scope) }
        }
    }

    func attach() throws -> FactRecorder<GitProjectorScope, GitProjectorFact> {
        try localSource.attach()
    }

    func nextDeadlineScope(worktreeId: UUID, kind: GitProjectorDeadlineKind) async -> GitProjectorScope {
        let key = DeadlineKey(worktreeId: worktreeId, kind: kind)
        return await withCheckedContinuation { continuation in
            let pending = deadlineScopes.withLock { state -> GitProjectorScope? in
                if var scopes = state.pending[key], !scopes.isEmpty {
                    let scope = scopes.removeFirst()
                    state.pending[key] = scopes
                    return scope
                }
                precondition(state.waiters[key] == nil, "One deadline scope consumer per worktree and kind")
                state.waiters[key] = continuation
                return nil
            }
            if let pending { continuation.resume(returning: pending) }
        }
    }

    func nextDeadlineScope(kind: GitProjectorDeadlineKind) async -> GitProjectorScope {
        await withCheckedContinuation { continuation in
            let pending = deadlineScopes.withLock { state -> GitProjectorScope? in
                if var scopes = state.anyWorktreePending[kind], !scopes.isEmpty {
                    let scope = scopes.removeFirst()
                    state.anyWorktreePending[kind] = scopes
                    return scope
                }
                precondition(state.anyWorktreeWaiters[kind] == nil, "One deadline scope consumer per kind")
                state.anyWorktreeWaiters[kind] = continuation
                return nil
            }
            if let pending { continuation.resume(returning: pending) }
        }
    }

    func expectDeadlineRegistered(
        facts: FactRecorder<GitProjectorScope, GitProjectorFact>,
        worktreeId: UUID,
        kind: GitProjectorDeadlineKind
    ) async throws -> GitProjectorScope {
        let scope = await nextDeadlineScope(worktreeId: worktreeId, kind: kind)
        try await facts.expectNext(in: scope, .deadlineRegistered(kind))
        return scope
    }

    func expectDeadlineRegistered(
        facts: FactRecorder<GitProjectorScope, GitProjectorFact>,
        kind: GitProjectorDeadlineKind
    ) async throws -> GitProjectorScope {
        let scope = await nextDeadlineScope(kind: kind)
        try await facts.expectNext(in: scope, .deadlineRegistered(kind))
        return scope
    }
}

private struct DeadlineKey: Hashable {
    let worktreeId: UUID
    let kind: GitProjectorDeadlineKind
}

private struct DeadlineScopeState {
    var pending: [DeadlineKey: [GitProjectorScope]] = [:]
    var waiters: [DeadlineKey: CheckedContinuation<GitProjectorScope, Never>] = [:]
    var anyWorktreePending: [GitProjectorDeadlineKind: [GitProjectorScope]] = [:]
    var anyWorktreeWaiters: [GitProjectorDeadlineKind: CheckedContinuation<GitProjectorScope, Never>] = [:]
}
