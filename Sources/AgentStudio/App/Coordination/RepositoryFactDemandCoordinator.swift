import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

struct RepositoryFactDemandInput: Equatable, Sendable {
    let activePaneWorktreeId: UUID?
    let sidebarAttendedWorktreeIds: Set<UUID>
    let visibleActiveTabWorktreeIds: Set<UUID>
    let openWorktreeIds: Set<UUID>
    let repositoryIdByWorktreeId: [UUID: UUID]
    let activityTopology: [RepositoryActivityTopology]
    let localActivityHydrationDisposition: RepositoryLocalActivityHydrationDisposition
    let repositoryLocalActivityByStableKey: [String: RepositoryLocalActivity]

    init(
        activePaneWorktreeId: UUID?,
        sidebarAttendedWorktreeIds: Set<UUID>,
        visibleActiveTabWorktreeIds: Set<UUID>,
        openWorktreeIds: Set<UUID>,
        repositoryIdByWorktreeId: [UUID: UUID],
        activityTopology: [RepositoryActivityTopology],
        localActivityHydrationDisposition: RepositoryLocalActivityHydrationDisposition = .pending,
        repositoryLocalActivityByStableKey: [String: RepositoryLocalActivity] = [:]
    ) {
        self.activePaneWorktreeId = activePaneWorktreeId
        self.sidebarAttendedWorktreeIds = sidebarAttendedWorktreeIds
        self.visibleActiveTabWorktreeIds = visibleActiveTabWorktreeIds
        self.openWorktreeIds = openWorktreeIds
        self.repositoryIdByWorktreeId = repositoryIdByWorktreeId
        self.activityTopology = activityTopology
        self.localActivityHydrationDisposition = localActivityHydrationDisposition
        self.repositoryLocalActivityByStableKey = repositoryLocalActivityByStableKey
    }

    static let empty = Self(
        activePaneWorktreeId: nil,
        sidebarAttendedWorktreeIds: [],
        visibleActiveTabWorktreeIds: [],
        openWorktreeIds: [],
        repositoryIdByWorktreeId: [:],
        activityTopology: [],
        localActivityHydrationDisposition: .pending,
        repositoryLocalActivityByStableKey: [:]
    )
}

struct RepositoryFactDemandSnapshot: Equatable, Sendable {
    let activePaneWorktreeId: UUID?
    let sidebarAttendedWorktreeIds: Set<UUID>
    let visibleActiveTabWorktreeIds: Set<UUID>
    let openWorktreeIds: Set<UUID>
    let repositoryIdByWorktreeId: [UUID: UUID]
    let warmRepositoryIds: Set<UUID>
    let locallyInactiveRepositoryIds: Set<UUID>
    let warmAutomaticWorktreeIds: Set<UUID>
    let locallyInactiveWorktreeIds: Set<UUID>

    static let empty = Self(
        activePaneWorktreeId: nil,
        sidebarAttendedWorktreeIds: [],
        visibleActiveTabWorktreeIds: [],
        openWorktreeIds: [],
        repositoryIdByWorktreeId: [:],
        warmRepositoryIds: [],
        locallyInactiveRepositoryIds: [],
        warmAutomaticWorktreeIds: [],
        locallyInactiveWorktreeIds: []
    )

    var forgeDemandedWorktreeIds: Set<UUID> {
        sidebarAttendedWorktreeIds
            .union(visibleActiveTabWorktreeIds)
            .intersection(warmAutomaticWorktreeIds)
    }

    var demandedRepositoryIds: Set<UUID> {
        Set(forgeDemandedWorktreeIds.compactMap { repositoryIdByWorktreeId[$0] })
            .intersection(warmRepositoryIds)
    }

    var localGitAttentionWorktreeIds: Set<UUID> {
        var worktreeIds = openWorktreeIds
        worktreeIds.formUnion(sidebarAttendedWorktreeIds)
        worktreeIds.formUnion(visibleActiveTabWorktreeIds)
        if let activePaneWorktreeId {
            worktreeIds.insert(activePaneWorktreeId)
        }
        return worktreeIds.intersection(warmAutomaticWorktreeIds)
    }
}

private struct RepositoryFactDemandDeadlineClock: Sendable {
    private let nowValue: @Sendable () -> Duration
    private let sleepUntilValue: @Sendable (Duration) async throws -> Void

    init<SourceClock: Clock & Sendable>(_ sourceClock: SourceClock)
    where SourceClock.Duration == Duration {
        let origin = sourceClock.now
        nowValue = {
            origin.duration(to: sourceClock.now)
        }
        sleepUntilValue = { deadline in
            try await sourceClock.sleep(until: origin.advanced(by: deadline), tolerance: nil)
        }
    }

    var now: Duration {
        nowValue()
    }

    func sleep(until deadline: Duration) async throws {
        try await sleepUntilValue(deadline)
    }
}

@MainActor
final class RepositoryFactDemandCoordinator {
    typealias Delivery = @Sendable (RepositoryFactDemandSnapshot) async -> Void

    private let delivery: Delivery
    private let performanceRecorder: (any RepositoryFactDemandPerformanceRecording)?
    private let wallClockNow: @MainActor @Sendable () -> Date
    private let deadlineClock: RepositoryFactDemandDeadlineClock
    private var performanceSnapshot = RepositoryFactDemandPerformanceSnapshot()
    private var pendingInput: RepositoryFactDemandInput?
    private var pendingInputMustDeliver = false
    private var inFlightInput: RepositoryFactDemandInput?
    private var lastClassifiedInput: RepositoryFactDemandInput?
    private var lastDeliveredSnapshot: RepositoryFactDemandSnapshot?
    private var deliveryTask: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?
    private var deadlineGeneration: UInt64 = 0
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private var acceptsInputs = true
    private var didStartShutdown = false

    init(
        performanceRecorder: (any RepositoryFactDemandPerformanceRecording)? = nil,
        wallClockNow: @escaping @MainActor @Sendable () -> Date = Date.init,
        sleepClock: any Clock<Duration> & Sendable = ContinuousClock(),
        delivery: @escaping Delivery
    ) {
        self.performanceRecorder = performanceRecorder
        self.wallClockNow = wallClockNow
        deadlineClock = RepositoryFactDemandDeadlineClock(sleepClock)
        self.delivery = delivery
    }

    func accept(_ input: RepositoryFactDemandInput) {
        guard acceptsInputs else {
            increment(\.rejectedAfterShutdown)
            flushPerformanceSnapshotIfNeeded()
            return
        }
        increment(\.projected)
        guard pendingInput != input else {
            increment(\.contentEqual)
            flushPerformanceSnapshotIfNeeded()
            return
        }
        if pendingInput == nil, inFlightInput == input {
            increment(\.contentEqual)
            flushPerformanceSnapshotIfNeeded()
            return
        }
        if deliveryTask == nil, lastClassifiedInput == input {
            increment(\.contentEqual)
            flushPerformanceSnapshotIfNeeded()
            return
        }
        cancelDeadlineTask()
        pendingInput = input
        pendingInputMustDeliver = false
        startDeliveryTaskIfNeeded()
    }

    func waitUntilIdle() async {
        guard deliveryTask != nil else {
            flushPerformanceSnapshot()
            return
        }
        await withCheckedContinuation { continuation in
            idleWaiters.append(continuation)
        }
    }

    func shutdown() async {
        guard !didStartShutdown else {
            await waitUntilIdle()
            return
        }
        didStartShutdown = true
        acceptsInputs = false
        cancelDeadlineTask()
        pendingInput = .empty
        pendingInputMustDeliver = true
        startDeliveryTaskIfNeeded()
        await waitUntilIdle()
    }

    private func startDeliveryTaskIfNeeded() {
        guard deliveryTask == nil else { return }
        deliveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while let nextInput = self.pendingInput {
                let mustDeliver = self.pendingInputMustDeliver
                self.pendingInput = nil
                self.pendingInputMustDeliver = false
                self.inFlightInput = nextInput
                let classified = await Self.classify(
                    nextInput,
                    referenceDate: self.wallClockNow()
                )
                self.inFlightInput = nil
                guard self.pendingInput == nil else { continue }

                self.recordActivityPerformance(
                    classified.snapshot,
                    input: nextInput,
                    previousInput: self.lastClassifiedInput,
                    previousSnapshot: self.lastDeliveredSnapshot
                )

                if !mustDeliver, classified.snapshot == self.lastDeliveredSnapshot {
                    self.lastClassifiedInput = nextInput
                    self.rescheduleDeadline(at: classified.nextTransitionAt)
                    continue
                }

                await self.delivery(classified.snapshot)
                self.increment(\.delivered)
                if classified.snapshot == .empty {
                    self.increment(\.cleared)
                }
                guard !Task.isCancelled else {
                    self.finishDeliveryTask()
                    return
                }
                self.lastClassifiedInput = nextInput
                self.lastDeliveredSnapshot = classified.snapshot
                if self.pendingInput == nil {
                    self.rescheduleDeadline(at: classified.nextTransitionAt)
                }
            }
            self.finishDeliveryTask()
        }
    }

    @concurrent nonisolated private static func classify(
        _ input: RepositoryFactDemandInput,
        referenceDate: Date
    ) async -> (snapshot: RepositoryFactDemandSnapshot, nextTransitionAt: Date?) {
        let activity = RepositoryActivityClassifier.classify(
            RepositoryActivityClassificationInput(
                repositories: input.activityTopology,
                openWorktreeIDs: input.openWorktreeIds,
                localActivityHydrationDisposition: input.localActivityHydrationDisposition,
                repositoryLocalActivityByStableKey: input.repositoryLocalActivityByStableKey,
                referenceDate: referenceDate,
                inactivityHorizon: AppPolicies.EntityRecency.applicationActivityHorizon
            )
        )
        return (
            RepositoryFactDemandSnapshot(
                activePaneWorktreeId: input.activePaneWorktreeId,
                sidebarAttendedWorktreeIds: input.sidebarAttendedWorktreeIds,
                visibleActiveTabWorktreeIds: input.visibleActiveTabWorktreeIds,
                openWorktreeIds: input.openWorktreeIds,
                repositoryIdByWorktreeId: input.repositoryIdByWorktreeId,
                warmRepositoryIds: activity.warmRepositoryIDs,
                locallyInactiveRepositoryIds: activity.locallyInactiveRepositoryIDs,
                warmAutomaticWorktreeIds: activity.warmWorktreeIDs,
                locallyInactiveWorktreeIds: activity.locallyInactiveWorktreeIDs
            ),
            activity.nextTransitionAt
        )
    }

    private func rescheduleDeadline(at transitionDate: Date?) {
        cancelDeadlineTask()
        guard acceptsInputs, let transitionDate else { return }
        let delaySeconds = max(0, transitionDate.timeIntervalSince(wallClockNow()))
        let deadline = deadlineClock.now + .seconds(delaySeconds)
        let generation = deadlineGeneration
        let deadlineClock = self.deadlineClock
        deadlineTask = Task { @MainActor [weak self, deadlineClock] in
            do {
                try await Self.waitForDeadline(deadline, clock: deadlineClock)
            } catch is CancellationError {
                return
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.handleDeadlineWake(generation: generation)
        }
    }

    @concurrent nonisolated private static func waitForDeadline(
        _ deadline: Duration,
        clock: RepositoryFactDemandDeadlineClock
    ) async throws {
        try await clock.sleep(until: deadline)
    }

    private func handleDeadlineWake(generation: UInt64) {
        guard generation == deadlineGeneration,
            acceptsInputs,
            let lastClassifiedInput
        else { return }
        increment(\.boundaryReclassified)
        deadlineTask = nil
        pendingInput = lastClassifiedInput
        pendingInputMustDeliver = false
        startDeliveryTaskIfNeeded()
    }

    private func cancelDeadlineTask() {
        deadlineGeneration &+= 1
        deadlineTask?.cancel()
        deadlineTask = nil
    }

    private func finishDeliveryTask() {
        deliveryTask = nil
        flushPerformanceSnapshot()
        let waiters = idleWaiters
        idleWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func increment(_ keyPath: WritableKeyPath<RepositoryFactDemandPerformanceSnapshot, UInt64>) {
        if performanceSnapshot[keyPath: keyPath] < .max {
            performanceSnapshot[keyPath: keyPath] += 1
        }
    }

    private func recordActivityPerformance(
        _ snapshot: RepositoryFactDemandSnapshot,
        input: RepositoryFactDemandInput,
        previousInput: RepositoryFactDemandInput?,
        previousSnapshot: RepositoryFactDemandSnapshot?
    ) {
        performanceSnapshot.hydrationUnclassifiedCurrent =
            input.localActivityHydrationDisposition == .authoritative ? 0 : 1
        performanceSnapshot.warmRepositoryCurrent = UInt64(snapshot.warmRepositoryIds.count)
        performanceSnapshot.inactiveRepositoryCurrent = UInt64(
            snapshot.locallyInactiveRepositoryIds.count)
        performanceSnapshot.warmWorktreeCurrent = UInt64(snapshot.warmAutomaticWorktreeIds.count)
        performanceSnapshot.inactiveWorktreeCurrent = UInt64(
            snapshot.locallyInactiveWorktreeIds.count)
        performanceSnapshot.inactiveRemoteSuppressedCurrent = UInt64(
            Set(
                snapshot.sidebarAttendedWorktreeIds.compactMap {
                    snapshot.repositoryIdByWorktreeId[$0]
                }
            ).intersection(snapshot.locallyInactiveRepositoryIds).count
        )
        performanceSnapshot.inactiveForgeSuppressedCurrent = UInt64(
            snapshot.sidebarAttendedWorktreeIds.union(snapshot.visibleActiveTabWorktreeIds)
                .intersection(snapshot.locallyInactiveWorktreeIds).count
        )
        guard let previousInput, let previousSnapshot else { return }
        let reactivatedRepositories = previousSnapshot.locallyInactiveRepositoryIds
            .intersection(snapshot.warmRepositoryIds)
        guard !reactivatedRepositories.isEmpty else { return }
        if input.openWorktreeIds != previousInput.openWorktreeIds {
            increment(\.paneReactivated)
        } else if input.repositoryLocalActivityByStableKey
            != previousInput.repositoryLocalActivityByStableKey
        {
            increment(\.recencyReactivated)
        }
    }

    private func flushPerformanceSnapshotIfNeeded() {
        guard performanceSnapshot.inputCount >= AppPolicies.RepositoryFactDemand.telemetryFlushInputCount else {
            return
        }
        flushPerformanceSnapshot()
    }

    private func flushPerformanceSnapshot() {
        guard !performanceSnapshot.isEmpty else { return }
        performanceRecorder?.recordRepositoryFactDemandPerformanceSnapshot(performanceSnapshot)
        performanceSnapshot = RepositoryFactDemandPerformanceSnapshot()
    }
}
