import Foundation

enum BridgePaneRefreshLane: String, Codable, Hashable, Sendable {
    case file
    case review
}

enum BridgePaneRefreshCatchUpOutcome: Equatable, Sendable {
    case succeeded
    case failed
    case stale
}

struct BridgePaneRefreshDirtyFact: Sendable {
    let generation: UInt64
    let fileChangeset: FileChangeset?
    let latestFileStatus: GitWorkingTreeStatus?
    let latestBatchSequence: UInt64
    let requiresReviewRefresh: Bool

    var filePaths: [String] {
        fileChangeset?.paths ?? []
    }
}

struct BridgePaneRefreshWorkAdmission: Sendable {
    fileprivate let gate: BridgePaneRefreshWorkAdmissionGate
    fileprivate let token: BridgePaneRefreshWorkAdmissionGate.Token

    func withValidAdmission<MutationResult>(
        _ mutation: () throws -> MutationResult
    ) rethrows -> MutationResult? {
        try gate.withValidAdmission(token, perform: mutation)
    }

    func registerInvalidationHandler(
        _ handler: @escaping @Sendable () -> Void
    ) -> UUID? {
        gate.registerInvalidationHandler(token, handler: handler)
    }

    func removeInvalidationHandler(_ handlerId: UUID) {
        gate.removeInvalidationHandler(handlerId)
    }
}

/// Thread-safe foreground-work admission shared with off-main Bridge producers.
///
/// The MainActor coordinator remains the sole activity writer. Product actors
/// may only acquire and validate tokens through this source; they cannot mint or
/// change pane activity.
struct BridgePaneRefreshWorkAdmissionSource: Sendable {
    fileprivate let gate: BridgePaneRefreshWorkAdmissionGate

    func acquire() -> BridgePaneRefreshWorkAdmission? {
        gate.acquire()
    }
}

struct BridgePaneRefreshCatchUpReservation: Sendable {
    let id: UUID
    let dirtyGeneration: UInt64
    let lanes: Set<BridgePaneRefreshLane>
    let fileChangeset: FileChangeset?
    let latestFileStatus: GitWorkingTreeStatus?
    let latestBatchSequence: UInt64
    let requiresReviewRefresh: Bool
    let foregroundWorkAdmission: BridgePaneRefreshWorkAdmission

    fileprivate let dirtyFact: BridgePaneRefreshDirtyFact

    var filePaths: [String] {
        fileChangeset?.paths ?? []
    }
}

struct BridgePaneRefreshAdmissionSnapshot: Sendable {
    let activity: BridgePaneActivity
    let foregroundWorkEpoch: UInt64
    let dirtyFact: BridgePaneRefreshDirtyFact?
    let activeRefreshPass: BridgePaneRefreshCatchUpReservation?
    let refreshPassCount: Int
}

struct BridgePaneProductPresentationSnapshot: Equatable, Sendable {
    let activityRevision: Int
    let nativeActivity: BridgePaneActivity
    let refreshingLanes: Set<BridgePaneRefreshLane>
}

/// Owns foreground work admission and the one pane-wide hidden freshness fact.
///
/// Activity admission is synchronous and lock-backed so File/Review producer
/// actors can validate their original epoch after suspension without hopping to
/// `MainActor`. Dirty-state and catch-up sequencing remain pane-controller state.
@MainActor
final class BridgePaneRefreshAdmissionCoordinator {
    private let workAdmissionGate: BridgePaneRefreshWorkAdmissionGate
    private var activity: BridgePaneActivity
    private var dirtyFact: BridgePaneRefreshDirtyFact?
    private var activeRefreshPass: BridgePaneRefreshCatchUpReservation?
    private var nextDirtyGeneration: UInt64 = 0
    private var presentationRevision = 1
    private var refreshPassCount = 0

    init(initialActivity: BridgePaneActivity = .dormant) {
        activity = initialActivity
        workAdmissionGate = BridgePaneRefreshWorkAdmissionGate(initialActivity: initialActivity)
    }

    var diagnosticSnapshot: BridgePaneRefreshAdmissionSnapshot {
        BridgePaneRefreshAdmissionSnapshot(
            activity: activity,
            foregroundWorkEpoch: workAdmissionGate.diagnosticSnapshot.epoch,
            dirtyFact: dirtyFact,
            activeRefreshPass: activeRefreshPass,
            refreshPassCount: refreshPassCount
        )
    }

    var workAdmissionSource: BridgePaneRefreshWorkAdmissionSource {
        BridgePaneRefreshWorkAdmissionSource(gate: workAdmissionGate)
    }

    var productPresentationSnapshot: BridgePaneProductPresentationSnapshot {
        BridgePaneProductPresentationSnapshot(
            activityRevision: presentationRevision,
            nativeActivity: activity,
            refreshingLanes: activeRefreshPass?.lanes ?? []
        )
    }

    func recordInvalidation(
        fileChangeset: FileChangeset?,
        latestFileStatus: GitWorkingTreeStatus? = nil,
        requiresReviewRefresh: Bool
    ) {
        guard activity != .closed else { return }
        dirtyFact = mergingInvalidation(
            into: dirtyFact,
            fileChangeset: fileChangeset,
            latestFileStatus: latestFileStatus,
            requiresReviewRefresh: requiresReviewRefresh
        )
    }

    func applyActivity(_ nextActivity: BridgePaneActivity) {
        let previousPresentation = productPresentationSnapshot
        guard activity != .closed, nextActivity != .closed else {
            if nextActivity == .closed { close() }
            return
        }
        let previousActivity = activity
        guard previousActivity != nextActivity else { return }
        activity = nextActivity
        workAdmissionGate.updateActivity(nextActivity)
        if nextActivity != .foreground {
            restoreActiveReservationToDirtyFact()
        }
        advancePresentationRevisionIfNeeded(from: previousPresentation)
    }

    func acquireForegroundWork() -> BridgePaneRefreshWorkAdmission? {
        workAdmissionGate.acquire()
    }

    func completeRefreshPass(
        _ reservation: BridgePaneRefreshCatchUpReservation,
        outcome: BridgePaneRefreshCatchUpOutcome
    ) {
        // Leaving foreground already restores and clears the active reservation.
        // Its later cancelled/stale completion must not merge the same fact twice.
        guard activeRefreshPass?.id == reservation.id else { return }
        let previousPresentation = productPresentationSnapshot
        activeRefreshPass = nil
        guard activity != .closed else { return }
        switch outcome {
        case .succeeded:
            break
        case .failed, .stale:
            restoreDirtyFact(reservation.dirtyFact)
        }
        advancePresentationRevisionIfNeeded(from: previousPresentation)
    }

    func reserveForegroundRefreshPass() -> BridgePaneRefreshCatchUpReservation? {
        guard activity == .foreground else { return nil }
        return reserveCatchUpIfPossible()
    }

    func close() {
        guard activity != .closed else { return }
        let previousPresentation = productPresentationSnapshot
        activity = .closed
        workAdmissionGate.close()
        dirtyFact = nil
        activeRefreshPass = nil
        advancePresentationRevisionIfNeeded(from: previousPresentation)
    }

    private func mergingInvalidation(
        into current: BridgePaneRefreshDirtyFact?,
        fileChangeset: FileChangeset?,
        latestFileStatus: GitWorkingTreeStatus?,
        requiresReviewRefresh: Bool
    ) -> BridgePaneRefreshDirtyFact {
        guard let current else {
            nextDirtyGeneration &+= 1
            return BridgePaneRefreshDirtyFact(
                generation: nextDirtyGeneration,
                fileChangeset: mergedFileChangeset(current: nil, incoming: fileChangeset),
                latestFileStatus: latestFileStatus,
                latestBatchSequence: fileChangeset?.batchSeq ?? 0,
                requiresReviewRefresh: requiresReviewRefresh
            )
        }
        return BridgePaneRefreshDirtyFact(
            generation: current.generation,
            fileChangeset: mergedFileChangeset(current: current.fileChangeset, incoming: fileChangeset),
            latestFileStatus: latestFileStatus ?? current.latestFileStatus,
            latestBatchSequence: max(current.latestBatchSequence, fileChangeset?.batchSeq ?? 0),
            requiresReviewRefresh: current.requiresReviewRefresh || requiresReviewRefresh
        )
    }

    private func reserveCatchUpIfPossible() -> BridgePaneRefreshCatchUpReservation? {
        guard activeRefreshPass == nil,
            let dirtyFact,
            let activityAdmission = workAdmissionGate.acquire()
        else { return nil }
        self.dirtyFact = nil
        let lanes: Set<BridgePaneRefreshLane> =
            dirtyFact.requiresReviewRefresh
            ? [.file, .review]
            : [.file]
        let reservation = BridgePaneRefreshCatchUpReservation(
            id: UUID(),
            dirtyGeneration: dirtyFact.generation,
            lanes: lanes,
            fileChangeset: dirtyFact.fileChangeset,
            latestFileStatus: dirtyFact.latestFileStatus,
            latestBatchSequence: dirtyFact.latestBatchSequence,
            requiresReviewRefresh: dirtyFact.requiresReviewRefresh,
            foregroundWorkAdmission: activityAdmission,
            dirtyFact: dirtyFact
        )
        activeRefreshPass = reservation
        refreshPassCount += 1
        presentationRevision += 1
        return reservation
    }

    private func restoreActiveReservationToDirtyFact() {
        guard let activeRefreshPass else { return }
        self.activeRefreshPass = nil
        restoreDirtyFact(activeRefreshPass.dirtyFact)
    }

    private func restoreDirtyFact(_ restored: BridgePaneRefreshDirtyFact) {
        guard activity != .closed else { return }
        guard let current = dirtyFact else {
            dirtyFact = restored
            return
        }
        dirtyFact = BridgePaneRefreshDirtyFact(
            generation: min(current.generation, restored.generation),
            fileChangeset: mergedFileChangeset(
                current: current.fileChangeset,
                incoming: restored.fileChangeset
            ),
            latestFileStatus: current.latestFileStatus ?? restored.latestFileStatus,
            latestBatchSequence: max(current.latestBatchSequence, restored.latestBatchSequence),
            requiresReviewRefresh: current.requiresReviewRefresh || restored.requiresReviewRefresh
        )
    }

    private func advancePresentationRevisionIfNeeded(
        from previousPresentation: BridgePaneProductPresentationSnapshot
    ) {
        guard
            previousPresentation.nativeActivity != activity
                || previousPresentation.refreshingLanes != (activeRefreshPass?.lanes ?? [])
        else { return }
        presentationRevision += 1
    }

    private func mergedFileChangeset(
        current: FileChangeset?,
        incoming: FileChangeset?
    ) -> FileChangeset? {
        guard let incoming else { return current }
        guard let current else {
            return FileChangeset(
                worktreeId: incoming.worktreeId,
                repoId: incoming.repoId,
                rootPath: incoming.rootPath,
                paths: Array(Set(incoming.paths)).sorted(),
                containsGitInternalChanges: incoming.containsGitInternalChanges,
                suppressedIgnoredPathCount: incoming.suppressedIgnoredPathCount,
                suppressedGitInternalPathCount: incoming.suppressedGitInternalPathCount,
                timestamp: incoming.timestamp,
                batchSeq: incoming.batchSeq
            )
        }
        return FileChangeset(
            worktreeId: incoming.worktreeId,
            repoId: incoming.repoId,
            rootPath: incoming.rootPath,
            paths: Array(Set(current.paths).union(incoming.paths)).sorted(),
            containsGitInternalChanges: current.containsGitInternalChanges
                || incoming.containsGitInternalChanges,
            suppressedIgnoredPathCount: current.suppressedIgnoredPathCount
                + incoming.suppressedIgnoredPathCount,
            suppressedGitInternalPathCount: current.suppressedGitInternalPathCount
                + incoming.suppressedGitInternalPathCount,
            timestamp: incoming.batchSeq >= current.batchSeq ? incoming.timestamp : current.timestamp,
            batchSeq: max(current.batchSeq, incoming.batchSeq)
        )
    }
}

private final class BridgePaneRefreshWorkAdmissionGate: @unchecked Sendable {
    fileprivate final class Identity: Sendable {}

    fileprivate struct Token: Sendable {
        let identity: Identity
        let epoch: UInt64
    }

    struct DiagnosticSnapshot: Sendable {
        let epoch: UInt64
    }

    private let lock = NSLock()
    private let identity = Identity()
    private var activity: BridgePaneActivity
    private var epoch: UInt64 = 0
    private var invalidationHandlerById: [UUID: @Sendable () -> Void] = [:]

    init(initialActivity: BridgePaneActivity) {
        activity = initialActivity
    }

    var diagnosticSnapshot: DiagnosticSnapshot {
        lock.withLock { DiagnosticSnapshot(epoch: epoch) }
    }

    func acquire() -> BridgePaneRefreshWorkAdmission? {
        lock.withLock {
            guard activity == .foreground else { return nil }
            return BridgePaneRefreshWorkAdmission(
                gate: self,
                token: Token(identity: identity, epoch: epoch)
            )
        }
    }

    func updateActivity(_ nextActivity: BridgePaneActivity) {
        let invalidationHandlers: [@Sendable () -> Void] = lock.withLock {
            guard activity != .closed, activity != nextActivity else { return [] }
            activity = nextActivity
            epoch &+= 1
            return takeInvalidationHandlers()
        }
        for invalidationHandler in invalidationHandlers {
            invalidationHandler()
        }
    }

    func close() {
        let invalidationHandlers: [@Sendable () -> Void] = lock.withLock {
            guard activity != .closed else { return [] }
            activity = .closed
            epoch &+= 1
            return takeInvalidationHandlers()
        }
        for invalidationHandler in invalidationHandlers {
            invalidationHandler()
        }
    }

    func withValidAdmission<MutationResult>(
        _ token: Token,
        perform mutation: () throws -> MutationResult
    ) rethrows -> MutationResult? {
        try lock.withLock {
            guard activity == .foreground,
                token.identity === identity,
                token.epoch == epoch
            else { return nil }
            return try mutation()
        }
    }

    func registerInvalidationHandler(
        _ token: Token,
        handler: @escaping @Sendable () -> Void
    ) -> UUID? {
        lock.withLock {
            guard activity == .foreground,
                token.identity === identity,
                token.epoch == epoch
            else { return nil }
            let handlerId = UUID()
            invalidationHandlerById[handlerId] = handler
            return handlerId
        }
    }

    func removeInvalidationHandler(_ handlerId: UUID) {
        _ = lock.withLock {
            invalidationHandlerById.removeValue(forKey: handlerId)
        }
    }

    private func takeInvalidationHandlers() -> [@Sendable () -> Void] {
        let handlers = Array(invalidationHandlerById.values)
        invalidationHandlerById.removeAll(keepingCapacity: false)
        return handlers
    }
}
