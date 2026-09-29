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
                preconditionFailure("Only lifetime facts belong to a lifetime scope")
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

/// Retains emitted operation identities. Tests still consume and verify their
/// facts through FactRecorder without reading projector scheduler state.
final class GitProjectorFactSource: Sendable {
    private let localSource = LocalFactSource(
        vocabulary: FactVocabulary<GitProjectorScope, GitProjectorFact>.gitProjector)
    private let deadlineScopes = Mutex(DeadlineScopeState())
    private let refreshScopes = Mutex(RefreshScopeState())

    var sink: GitProjectorFactSink {
        { [self] scope, fact in
            self.localSource.sink(scope, fact)
            if case .refreshAdmitted = fact, case .refresh(let worktreeId, _) = scope {
                let waiter = self.refreshScopes.withLock { state -> CheckedContinuation<GitProjectorScope, Never>? in
                    if let waiter = state.waiters.removeValue(forKey: worktreeId) { return waiter }
                    state.pending[worktreeId, default: []].append(scope)
                    return nil
                }
                waiter?.resume(returning: scope)
            }
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

    func nextRefreshScope(worktreeId: UUID) async -> GitProjectorScope {
        await withCheckedContinuation { continuation in
            let pending = refreshScopes.withLock { state -> GitProjectorScope? in
                if var scopes = state.pending[worktreeId], !scopes.isEmpty {
                    let scope = scopes.removeFirst()
                    state.pending[worktreeId] = scopes
                    return scope
                }
                precondition(state.waiters[worktreeId] == nil, "One refresh scope consumer per worktree")
                state.waiters[worktreeId] = continuation
                return nil
            }
            if let pending { continuation.resume(returning: pending) }
        }
    }

    func expectNextRefreshClosed(
        facts: FactRecorder<GitProjectorScope, GitProjectorFact>,
        worktreeId: UUID
    ) async throws -> GitProjectorRefreshOutcome {
        let scope = await nextRefreshScope(worktreeId: worktreeId)
        guard case .refresh(_, let requestSequence) = scope else {
            preconditionFailure("Refresh admission must have a refresh scope")
        }
        return try await facts.expectRefreshClosed(worktreeId: worktreeId, requestSequence: requestSequence)
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

private struct RefreshScopeState {
    var pending: [UUID: [GitProjectorScope]] = [:]
    var waiters: [UUID: CheckedContinuation<GitProjectorScope, Never>] = [:]
}
