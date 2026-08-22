import Observation
import Synchronization

@MainActor
@Observable
package final class EagerDerivedAtom<
    Intent: Sendable,
    IntentIdentity: Equatable & Sendable,
    Work: Sendable,
    Candidate: Sendable,
    Value: Sendable
> {
    package enum Freshness: Equatable, Sendable {
        case idle
        case running(IntentIdentity)
        case invalidated(IntentIdentity)
        case current(IntentIdentity)
        case stopped
    }

    package enum ProjectionCompletion: Equatable, Sendable {
        case published(IntentIdentity)
        case equal(IntentIdentity)
        case rejected(IntentIdentity)
        case superseded(IntentIdentity)
        case cancelled(IntentIdentity)
    }

    package enum PreparationDisposition: Sendable {
        case prepared(Work)
        case rejected
    }

    package enum CandidateDisposition: Sendable {
        case equalCurrent(Value)
        case immediateAccepted(Value)
        case changedAwaitingOwner(Value)
        case rejected
    }

    package enum SettlementDisposition: Sendable {
        case accepted(Value)
        case rejected
    }

    package struct CandidateToken: Hashable, Sendable {
        fileprivate let rawValue: UInt64
    }

    package private(set) var value: Value?
    package private(set) var freshness: Freshness = .idle
    package private(set) var revision = 0
    @ObservationIgnored package private(set) var latestAcceptedValue: Value?

    @ObservationIgnored private let revocationEpoch = Mutex<UInt64>(0)
    @ObservationIgnored private let intentIdentity: @Sendable (Intent) -> IntentIdentity
    @ObservationIgnored private let combinePendingIntents: @Sendable (Intent, Intent) -> Intent
    @ObservationIgnored private let prepare: @MainActor @Sendable (Intent, UInt64) -> PreparationDisposition
    @ObservationIgnored private let project: @Sendable (Work) throws(CancellationError) -> Candidate
    @ObservationIgnored private let classify: @MainActor @Sendable (Candidate, Value?) -> CandidateDisposition
    @ObservationIgnored private let onAwaitingOwner: @MainActor @Sendable (CandidateToken, Candidate, Value) -> Void
    @ObservationIgnored private let onProjectionCompletion: @MainActor @Sendable (ProjectionCompletion) -> Void
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var nextCandidateToken: UInt64 = 0
    @ObservationIgnored private var admittedIdentity: IntentIdentity?
    @ObservationIgnored private var admittedEpoch: UInt64?
    @ObservationIgnored private var activeIntent: AcceptedIntent?
    @ObservationIgnored private var pendingIntent: AcceptedIntent?
    @ObservationIgnored private var awaitingCandidate: AwaitingCandidate?
    @ObservationIgnored private var retainedTask: Task<Void, Never>?
    @ObservationIgnored private var unsettledAttemptCount = 0
    @ObservationIgnored private var hasStopped = false

    private struct AcceptedIntent {
        let intent: Intent
        let identity: IntentIdentity
        let generation: UInt64
        let epoch: UInt64
    }

    private struct AwaitingCandidate {
        let token: CandidateToken
        let candidate: Candidate
        let proposedValue: Value
        let generation: UInt64
        let identity: IntentIdentity
        let epoch: UInt64
    }

    package init(
        intentIdentity: @escaping @Sendable (Intent) -> IntentIdentity,
        combinePendingIntents: @escaping @Sendable (Intent, Intent) -> Intent,
        prepare: @escaping @MainActor @Sendable (Intent, UInt64) -> PreparationDisposition,
        project: @escaping @Sendable (Work) throws(CancellationError) -> Candidate,
        classify: @escaping @MainActor @Sendable (Candidate, Value?) -> CandidateDisposition,
        onAwaitingOwner:
            @escaping @MainActor @Sendable (CandidateToken, Candidate, Value) -> Void = { _, _, _ in },
        onProjectionCompletion:
            @escaping @MainActor @Sendable (ProjectionCompletion) -> Void = { _ in }
    ) {
        self.intentIdentity = intentIdentity
        self.combinePendingIntents = combinePendingIntents
        self.prepare = prepare
        self.project = project
        self.classify = classify
        self.onAwaitingOwner = onAwaitingOwner
        self.onProjectionCompletion = onProjectionCompletion
    }

    package nonisolated func sourceDidInvalidate() {
        let invalidatedEpoch = revocationEpoch.withLock { epoch in
            epoch &+= 1
            return epoch
        }
        Task { @MainActor [weak self] in
            self?.applySourceInvalidation(invalidatedEpoch: invalidatedEpoch)
        }
    }

    package func admit(_ intent: Intent) {
        guard !hasStopped else { return }

        let identity = intentIdentity(intent)
        let epoch = revocationEpoch.withLock { $0 }
        if admittedIdentity == identity, admittedEpoch == epoch {
            return
        }

        generation &+= 1
        admittedIdentity = identity
        admittedEpoch = epoch
        freshness = .running(identity)

        let acceptedIntent = AcceptedIntent(
            intent: intent,
            identity: identity,
            generation: generation,
            epoch: epoch
        )
        guard let activeIntent else {
            start(acceptedIntent)
            return
        }

        let intentToCombine = pendingIntent?.intent ?? activeIntent.intent
        let combinedIntent = combinePendingIntents(intentToCombine, intent)
        precondition(
            intentIdentity(combinedIntent) == identity,
            "The combined pending intent must retain the latest admitted identity"
        )
        let replacedPendingIntent = pendingIntent
        pendingIntent = AcceptedIntent(
            intent: combinedIntent,
            identity: identity,
            generation: generation,
            epoch: epoch
        )
        retainedTask?.cancel()
        if let replacedPendingIntent, replacedPendingIntent.identity != identity {
            onProjectionCompletion(.superseded(replacedPendingIntent.identity))
        }
        revokeAwaitingCandidateIfNeeded()
    }

    package func settle(
        _ token: CandidateToken,
        _ disposition: SettlementDisposition
    ) -> Bool {
        guard !hasStopped, let awaitingCandidate, awaitingCandidate.token == token else {
            return false
        }
        guard generation == awaitingCandidate.generation,
            admittedIdentity == awaitingCandidate.identity,
            admittedEpoch == awaitingCandidate.epoch,
            revocationEpoch.withLock({ $0 }) == awaitingCandidate.epoch
        else {
            freshness = .invalidated(awaitingCandidate.identity)
            revokeAwaitingCandidateIfNeeded()
            return false
        }
        self.awaitingCandidate = nil

        let completion: ProjectionCompletion
        switch disposition {
        case .accepted(let acceptedValue):
            commitChangedValue(acceptedValue, identity: awaitingCandidate.identity)
            completion = .published(awaitingCandidate.identity)
        case .rejected:
            freshness = .invalidated(awaitingCandidate.identity)
            completion = .rejected(awaitingCandidate.identity)
        }
        attemptDidSettle()
        finishActiveIntent(awaitingCandidate.generation, completion: completion)
        return true
    }

    package func isCurrent(_ identity: IntentIdentity) -> Bool {
        guard !hasStopped,
            admittedIdentity == identity,
            admittedEpoch == revocationEpoch.withLock({ $0 }),
            freshness == .current(identity)
        else {
            return false
        }
        return true
    }

    package var hasUnsettledProjectionTasks: Bool {
        unsettledAttemptCount > 0
    }

    package func stop() {
        guard !hasStopped else { return }
        hasStopped = true
        generation &+= 1
        retainedTask?.cancel()
        let cancelledPendingIntent = pendingIntent
        pendingIntent = nil
        admittedIdentity = nil
        admittedEpoch = nil
        freshness = .stopped
        if let cancelledPendingIntent {
            onProjectionCompletion(.cancelled(cancelledPendingIntent.identity))
        }
        if let awaitingCandidate {
            self.awaitingCandidate = nil
            attemptDidSettle()
            finishActiveIntent(
                awaitingCandidate.generation,
                completion: .cancelled(awaitingCandidate.identity)
            )
        }
    }

    private func start(_ acceptedIntent: AcceptedIntent) {
        guard !hasStopped else { return }
        activeIntent = acceptedIntent

        switch prepare(acceptedIntent.intent, acceptedIntent.epoch) {
        case .rejected:
            freshness = .invalidated(acceptedIntent.identity)
            finishActiveIntent(
                acceptedIntent.generation,
                completion: .rejected(acceptedIntent.identity)
            )
        case .prepared(let work):
            startProjection(work, for: acceptedIntent)
        }
    }

    private func startProjection(_ work: Work, for acceptedIntent: AcceptedIntent) {
        let project = self.project
        unsettledAttemptCount += 1
        // Detached execution is the primitive's off-MainActor projection guarantee.
        // swiftlint:disable:next no_task_detached
        retainedTask = Task.detached(priority: .userInitiated) { [self] in
            do {
                let candidate = try project(work)
                let wasCancelled = Task.isCancelled
                await receiveCandidate(
                    candidate,
                    wasCancelled: wasCancelled,
                    generation: acceptedIntent.generation,
                    identity: acceptedIntent.identity,
                    epoch: acceptedIntent.epoch
                )
            } catch {
                await finishCancelledProjection(
                    generation: acceptedIntent.generation,
                    identity: acceptedIntent.identity,
                    epoch: acceptedIntent.epoch
                )
            }
        }
    }

    private func receiveCandidate(
        _ candidate: Candidate,
        wasCancelled: Bool,
        generation completedGeneration: UInt64,
        identity completedIdentity: IntentIdentity,
        epoch completedEpoch: UInt64
    ) {
        guard
            isCurrentAttempt(
                wasCancelled: wasCancelled,
                generation: completedGeneration,
                identity: completedIdentity,
                epoch: completedEpoch
            )
        else {
            attemptDidSettle()
            let completion: ProjectionCompletion =
                hasStopped
                ? .cancelled(completedIdentity)
                : .superseded(completedIdentity)
            finishActiveIntent(completedGeneration, completion: completion)
            return
        }

        switch classify(candidate, value) {
        case .equalCurrent(let acceptedValue):
            latestAcceptedValue = acceptedValue
            freshness = .current(completedIdentity)
            attemptDidSettle()
            finishActiveIntent(completedGeneration, completion: .equal(completedIdentity))
        case .immediateAccepted(let acceptedValue):
            commitChangedValue(acceptedValue, identity: completedIdentity)
            attemptDidSettle()
            finishActiveIntent(completedGeneration, completion: .published(completedIdentity))
        case .changedAwaitingOwner(let proposedValue):
            nextCandidateToken &+= 1
            let token = CandidateToken(rawValue: nextCandidateToken)
            awaitingCandidate = AwaitingCandidate(
                token: token,
                candidate: candidate,
                proposedValue: proposedValue,
                generation: completedGeneration,
                identity: completedIdentity,
                epoch: completedEpoch
            )
            retainedTask = nil
            onAwaitingOwner(token, candidate, proposedValue)
        case .rejected:
            freshness = .invalidated(completedIdentity)
            attemptDidSettle()
            finishActiveIntent(completedGeneration, completion: .rejected(completedIdentity))
        }
    }

    private func finishCancelledProjection(
        generation completedGeneration: UInt64,
        identity completedIdentity: IntentIdentity,
        epoch completedEpoch: UInt64
    ) {
        attemptDidSettle()
        let completion: ProjectionCompletion
        if hasStopped {
            completion = .cancelled(completedIdentity)
        } else if generation == completedGeneration,
            admittedIdentity == completedIdentity,
            admittedEpoch == completedEpoch,
            revocationEpoch.withLock({ $0 }) == completedEpoch
        {
            freshness = .invalidated(completedIdentity)
            completion = .cancelled(completedIdentity)
        } else {
            completion = .superseded(completedIdentity)
        }
        finishActiveIntent(completedGeneration, completion: completion)
    }

    private func isCurrentAttempt(
        wasCancelled: Bool,
        generation completedGeneration: UInt64,
        identity completedIdentity: IntentIdentity,
        epoch completedEpoch: UInt64
    ) -> Bool {
        !hasStopped
            && !wasCancelled
            && generation == completedGeneration
            && admittedIdentity == completedIdentity
            && admittedEpoch == completedEpoch
            && revocationEpoch.withLock({ $0 }) == completedEpoch
    }

    private func commitChangedValue(_ acceptedValue: Value, identity: IntentIdentity) {
        latestAcceptedValue = acceptedValue
        freshness = .current(identity)
        if value != nil {
            revision += 1
        }
        value = acceptedValue
    }

    private func applySourceInvalidation(invalidatedEpoch: UInt64) {
        guard !hasStopped, invalidatedEpoch == revocationEpoch.withLock({ $0 }) else { return }
        retainedTask?.cancel()
        let supersededPendingIntent = pendingIntent
        pendingIntent = nil
        if let supersededPendingIntent {
            onProjectionCompletion(.superseded(supersededPendingIntent.identity))
        }
        if let admittedIdentity {
            freshness = .invalidated(admittedIdentity)
        }
        revokeAwaitingCandidateIfNeeded()
    }

    private func revokeAwaitingCandidateIfNeeded() {
        guard let awaitingCandidate else { return }
        self.awaitingCandidate = nil
        attemptDidSettle()
        finishActiveIntent(
            awaitingCandidate.generation,
            completion: .superseded(awaitingCandidate.identity)
        )
    }

    private func finishActiveIntent(
        _ completedGeneration: UInt64,
        completion: ProjectionCompletion
    ) {
        onProjectionCompletion(completion)
        guard activeIntent?.generation == completedGeneration else { return }
        activeIntent = nil
        retainedTask = nil
        awaitingCandidate = nil
        guard !hasStopped, let pendingIntent else { return }
        self.pendingIntent = nil
        guard pendingIntent.epoch == revocationEpoch.withLock({ $0 }) else {
            onProjectionCompletion(.superseded(pendingIntent.identity))
            return
        }
        start(pendingIntent)
    }

    private func attemptDidSettle() {
        precondition(unsettledAttemptCount > 0)
        unsettledAttemptCount -= 1
    }
}
