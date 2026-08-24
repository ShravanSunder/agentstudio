import AgentStudioInfrastructure
import Foundation
import os

/// Event-driven projector that derives local git state from filesystem facts.
///
/// Input:
/// - `.filesystem(.worktreeRegistered)`
/// - `.filesystem(.worktreeUnregistered)`
/// - `.filesystem(.filesChanged)`
///
/// Output:
/// - `.filesystem(.gitSnapshotChanged)`
/// - `.filesystem(.branchChanged)` (optional derivative fact)
package actor GitWorkingDirectoryProjector {
    static let logger = Logger(subsystem: "com.agentstudio", category: "GitWorkingDirectoryProjector")

    let runtimeBus: EventBus<RuntimeEnvelope>
    /// Not `private` so the pathspec-status extension can dispatch scoped and full
    /// status reads (see `GitWorkingDirectoryProjector+PathspecStatus`).
    let gitWorkingTreeProvider: any GitWorkingTreeStatusProvider
    let envelopeClock: ContinuousClock
    let deadlineClock: GitRefreshDeadlineClock
    let coalescingWindow: Duration
    let delay: AsyncDelay
    let refreshPolicy: AppPolicies.GitRefresh.Policy
    private let subscriptionBufferLimit: Int
    let performanceTraceRecorder: (any GitProjectorPerformanceRecording)?
    /// Cheap filesystem existence check used to quarantine dead-path worktrees at
    /// admission (see `GitWorkingDirectoryProjector+PathQuarantine`). Injected so
    /// the projector stays inert in unit tests that register synthetic paths; the
    /// production composition root wires the live `FileManager` probe.
    let pathExistenceProbe: @Sendable (URL) -> Bool

    private var subscriptionTask: Task<Void, Never>?
    var deadlineTask: Task<Void, Never>?
    var deadlineTaskGeneration: UInt64 = 0
    var deadlineQueue = GitRefreshDeadlineQueue()
    var capacityCompletionTask: Task<Void, Never>?
    var worktreeTasks: [UUID: Task<Void, Never>] = [:]
    private var worktreeTaskGenerationByWorktreeId: [UUID: UInt64] = [:]
    private var nextWorktreeTaskGeneration: UInt64 = 0
    var immediateRefreshWorktreeIds: Set<UUID> = []
    var explicitRefreshWorktreeIds: Set<UUID> = []
    var tierEligibleWorktreeIds: Set<UUID> = []
    var admittedDemandTierByWorktreeId: [UUID: GitDemandTier] = [:]
    var admissionStartedAtByWorktreeId: [UUID: ContinuousClock.Instant] = [:]
    var visibleSidebarStripeCursor: Int = 0
    var visibilityAdmissionTask: Task<Void, Never>?
    var lastProcessedSidebarVisibleWorktreeIds: Set<UUID> = []
    var pendingVisibilityDeltaWorktreeIds: Set<UUID> = []
    var coalescingWorktreeIds: Set<UUID> = []
    var pendingByWorktreeId: [UUID: FileChangeset] = [:]
    var refreshAttribution = GitRefreshAttributionState()
    var capacityRetryWorktreeIds: Set<UUID> = []
    var capacityFallbackDeadlineByWorktreeId: [UUID: Duration] = [:]
    var suppressedWorktreeIds: Set<UUID> = []
    private var suppressedWorktreeOrder: [UUID] = []
    var rootPathByWorktreeId: [UUID: URL] = [:]
    private var latestTopologyAssertion: FilesystemTopologyAssertion?
    var activeWorktreeIds: Set<UUID> = []
    var activePaneWorktreeId: UUID?
    var sidebarVisibleWorktreeIds: Set<UUID> = []
    var repoIdByWorktreeId: [UUID: UUID] = [:]
    private var lastKnownOriginByRepoId: [UUID: String] = [:]
    private var originResolutionByRepoId: [UUID: GitOriginResolution] = [:]
    var lastEmittedSnapshotByWorktreeId: [UUID: GitWorkingTreeSnapshot] = [:]
    /// Last successful full status entry set per worktree. Its presence marks a
    /// fold-capable cache: a scoped compute folds into it (see
    /// `GitWorkingDirectoryProjector+PathspecStatus`). Not `private` so that
    /// extension can read it.
    var lastStatusEntriesByWorktreeId: [UUID: [GitWorkingTreeStatusEntry]] = [:]
    var lastAcceptedStatusFactsByWorktreeId: [UUID: GitWorkingTreeStatusFacts] = [:]
    var lastAcceptedLineDetailByWorktreeId: [UUID: GitWorkingTreeLineDetail] = [:]
    var lastAcceptedLineDetailAtByWorktreeId: [UUID: Duration] = [:]
    var lastAcceptedStatusAtByWorktreeId: [UUID: Duration] = [:]
    var automaticRefreshDeadlineByWorktreeId: [UUID: Duration] = [:]
    var lastAutomaticStartAtByWorktreeId: [UUID: Duration] = [:]
    var lastAutomaticCompletionAtByWorktreeId: [UUID: Duration] = [:]
    var lastAutomaticDutyByWorktreeId: [UUID: Duration] = [:]
    var nextPeriodicBatchSeqByWorktreeId: [UUID: UInt64] = [:]
    var statusBackoffFailureCountByWorktreeId: [UUID: Int] = [:]
    var openStatusBackoffWorktreeIds: Set<UUID> = []
    var deferredStatusBackoffChangesetByWorktreeId: [UUID: FileChangeset] = [:]
    var statusFailureDeadlineByWorktreeId: [UUID: Duration] = [:]
    var consecutiveStatusFailureCountByWorktreeId: [UUID: Int] = [:]
    /// Registered worktrees whose root path has vanished from disk. They are
    /// skipped at admission and periodic re-enqueue without further stat calls
    /// until an event-driven re-arm clears the mark
    /// (see `GitWorkingDirectoryProjector+PathQuarantine`).
    var quarantinedWorktreeIds: Set<UUID> = []
    var unchangedStatusResultCountByWorktreeId: [UUID: Int] = [:]
    var nextEnvelopeSequence: UInt64 = 0
    var lastRecordedLogicalDebtSnapshot: GitLogicalDebtSnapshot?
    var isShuttingDown = false

    var queuedLogicalDebtCount: Int {
        pendingByWorktreeId.count
    }

    var retryPendingLogicalDebtCount: Int {
        capacityRetryWorktreeIds.count + openStatusBackoffWorktreeIds.count
    }

    var runningLogicalDebtCount: Int {
        worktreeTasks.count
    }

    package init(
        bus: EventBus<RuntimeEnvelope> = PaneRuntimeEventBus.shared,
        gitWorkingTreeProvider: any GitWorkingTreeStatusProvider,
        envelopeClock: ContinuousClock = ContinuousClock(),
        coalescingWindow: Duration,
        sleepClock: (any Clock<Duration> & Sendable)? = nil,
        refreshPolicy: AppPolicies.GitRefresh.Policy = AppPolicies.GitRefresh.defaultPolicy,
        subscriptionBufferLimit: Int = 256,
        performanceTraceRecorder: (any GitProjectorPerformanceRecording)? = nil,
        pathExistenceProbe: @escaping @Sendable (URL) -> Bool = { _ in true }
    ) {
        self.runtimeBus = bus
        self.gitWorkingTreeProvider = gitWorkingTreeProvider
        self.envelopeClock = envelopeClock
        if let sleepClock {
            self.deadlineClock = GitRefreshDeadlineClock(sleepClock)
        } else {
            self.deadlineClock = GitRefreshDeadlineClock(ContinuousClock())
        }
        self.coalescingWindow = coalescingWindow
        delay = sleepClock.map(AsyncDelay.clock) ?? .taskSleep
        self.refreshPolicy = refreshPolicy
        self.subscriptionBufferLimit = subscriptionBufferLimit
        self.performanceTraceRecorder = performanceTraceRecorder
        self.pathExistenceProbe = pathExistenceProbe
    }

    isolated deinit {
        subscriptionTask?.cancel()
        deadlineTask?.cancel()
        capacityCompletionTask?.cancel()
        visibilityAdmissionTask?.cancel()
        for task in worktreeTasks.values {
            task.cancel()
        }
        worktreeTasks.removeAll(keepingCapacity: false)
        worktreeTaskGenerationByWorktreeId.removeAll(keepingCapacity: false)
        consecutiveStatusFailureCountByWorktreeId.removeAll(keepingCapacity: false)
    }

    package func start() async {
        guard subscriptionTask == nil else { return }
        isShuttingDown = false
        let stream = await runtimeBus.subscribe(
            policy: .lossyNewest(subscriptionBufferLimit),
            subscriberName: "GitWorkingDirectoryProjector",
            factInterest: .matching([.systemTopology, .worktreeFilesystem])
        )
        subscriptionTask = Task { [weak self] in
            for await runtimeEnvelope in stream {
                guard !Task.isCancelled else { break }
                guard let self else { return }
                await self.handleIncomingRuntimeEnvelope(runtimeEnvelope)
            }
        }

        rescheduleDeadlineTask()
    }

    package func shutdown() async {
        isShuttingDown = true
        let subscription = subscriptionTask
        subscriptionTask?.cancel()
        subscriptionTask = nil
        let deadline = deadlineTask
        deadlineTask?.cancel()
        deadlineTask = nil
        let capacityCompletion = capacityCompletionTask
        capacityCompletionTask?.cancel()
        capacityCompletionTask = nil
        let visibilityAdmission = visibilityAdmissionTask
        visibilityAdmissionTask?.cancel()
        visibilityAdmissionTask = nil

        var tasksToAwait: [Task<Void, Never>] = []
        for task in worktreeTasks.values {
            task.cancel()
            tasksToAwait.append(task)
        }
        worktreeTasks.removeAll(keepingCapacity: false)
        worktreeTaskGenerationByWorktreeId.removeAll(keepingCapacity: false)

        if let subscription {
            await subscription.value
        }
        if let deadline {
            await deadline.value
        }
        if let capacityCompletion {
            await capacityCompletion.value
        }
        if let visibilityAdmission {
            await visibilityAdmission.value
        }
        for task in tasksToAwait {
            await task.value
        }
        capacityRetryWorktreeIds.removeAll(keepingCapacity: false)
        capacityFallbackDeadlineByWorktreeId.removeAll(keepingCapacity: false)
        statusBackoffFailureCountByWorktreeId.removeAll(keepingCapacity: false)
        openStatusBackoffWorktreeIds.removeAll(keepingCapacity: false)
        statusFailureDeadlineByWorktreeId.removeAll(keepingCapacity: false)
        deadlineQueue = GitRefreshDeadlineQueue()
        deferredStatusBackoffChangesetByWorktreeId.removeAll(keepingCapacity: false)
        quarantinedWorktreeIds.removeAll(keepingCapacity: false)
        unchangedStatusResultCountByWorktreeId.removeAll(keepingCapacity: false)
        automaticRefreshDeadlineByWorktreeId.removeAll(keepingCapacity: false)
        lastAutomaticStartAtByWorktreeId.removeAll(keepingCapacity: false)
        lastAutomaticCompletionAtByWorktreeId.removeAll(keepingCapacity: false)
        lastAutomaticDutyByWorktreeId.removeAll(keepingCapacity: false)
        pendingByWorktreeId.removeAll(keepingCapacity: false)
        immediateRefreshWorktreeIds.removeAll(keepingCapacity: false)
        explicitRefreshWorktreeIds.removeAll(keepingCapacity: false)
        tierEligibleWorktreeIds.removeAll(keepingCapacity: false)
        admittedDemandTierByWorktreeId.removeAll(keepingCapacity: false)
        admissionStartedAtByWorktreeId.removeAll(keepingCapacity: false)
        visibleSidebarStripeCursor = 0
        lastProcessedSidebarVisibleWorktreeIds.removeAll(keepingCapacity: false)
        pendingVisibilityDeltaWorktreeIds.removeAll(keepingCapacity: false)
        coalescingWorktreeIds.removeAll(keepingCapacity: false)
        suppressedWorktreeIds.removeAll(keepingCapacity: false)
        suppressedWorktreeOrder.removeAll(keepingCapacity: false)
        rootPathByWorktreeId.removeAll(keepingCapacity: false)
        latestTopologyAssertion = nil
        activeWorktreeIds.removeAll(keepingCapacity: false)
        activePaneWorktreeId = nil
        sidebarVisibleWorktreeIds.removeAll(keepingCapacity: false)
        repoIdByWorktreeId.removeAll(keepingCapacity: false)
        lastKnownOriginByRepoId.removeAll(keepingCapacity: false)
        originResolutionByRepoId.removeAll(keepingCapacity: false)
        lastEmittedSnapshotByWorktreeId.removeAll(keepingCapacity: false)
        lastStatusEntriesByWorktreeId.removeAll(keepingCapacity: false)
        lastAcceptedStatusFactsByWorktreeId.removeAll(keepingCapacity: false)
        lastAcceptedLineDetailByWorktreeId.removeAll(keepingCapacity: false)
        lastAcceptedLineDetailAtByWorktreeId.removeAll(keepingCapacity: false)
        lastAcceptedStatusAtByWorktreeId.removeAll(keepingCapacity: false)
        consecutiveStatusFailureCountByWorktreeId.removeAll(keepingCapacity: false)
        nextPeriodicBatchSeqByWorktreeId.removeAll(keepingCapacity: false)
        nextWorktreeTaskGeneration = 0
    }

    private func handleIncomingRuntimeEnvelope(_ envelope: RuntimeEnvelope) async {
        switch envelope {
        case .system(let systemEnvelope):
            guard systemEnvelope.source == .builtin(.filesystemWatcher) else { return }
            guard case .topology(let topologyEvent) = systemEnvelope.event else { return }
            switch topologyEvent {
            case .worktreeRegistered(let worktreeId, let repoId, let rootPath):
                let context = WorktreeFilesystemContext(repoId: repoId, rootPath: rootPath)
                guard acceptsLifecycleRegistration(worktreeId: worktreeId, context: context) else { return }
                applyRegistration(
                    worktreeId: worktreeId,
                    context: context,
                    timestamp: systemEnvelope.timestamp
                )
            case .worktreeUnregistered(let worktreeId, let repoId):
                applyUnregistration(worktreeId: worktreeId, repoId: repoId)
            case .repoDiscovered, .reposDiscovered, .repoRemoved:
                return
            }
        case .worktree(let worktreeEnvelope):
            guard worktreeEnvelope.source == .system(.builtin(.filesystemWatcher)) else { return }
            guard case .filesystem(.filesChanged(let changeset)) = worktreeEnvelope.event else { return }
            let worktreeId = changeset.worktreeId
            guard !suppressedWorktreeIds.contains(worktreeId) else { return }
            guard acceptsFilesystemChanges(changeset) else { return }
            guard Self.shouldRefresh(for: changeset) else {
                performanceTraceRecorder?.record(
                    .gitSuppressedInputSkipped,
                    attributes: [
                        "agentstudio.worktree.id": .string(worktreeId.uuidString),
                        "agentstudio.performance.git.input_path.count": .int(changeset.paths.count),
                        "agentstudio.performance.git.suppressed_ignored_path.count": .int(
                            changeset.suppressedIgnoredPathCount
                        ),
                        "agentstudio.performance.git.suppressed_git_internal_path.count": .int(
                            changeset.suppressedGitInternalPathCount
                        ),
                    ]
                )
                return
            }
            guard admitFileChangeAfterQuarantine(worktreeId: worktreeId, rootPath: changeset.rootPath) else { return }
            repoIdByWorktreeId[worktreeId] = changeset.repoId
            resetAdaptiveCadence(worktreeId: worktreeId)
            guard !deferChangesetIfStatusBackoffOpen(changeset) else { return }
            guard !deferChangesetIfCapacityRetryPending(changeset) else { return }
            if !immediateRefreshWorktreeIds.contains(worktreeId) {
                pendingByWorktreeId[worktreeId] = Self.mergeChangesets(
                    pendingByWorktreeId[worktreeId],
                    with: changeset
                )
                refreshAttribution.triggerSourceByWorktreeId[worktreeId] = .filesystemChange
            }
            grantDemandEligibility(worktreeId: worktreeId)
            admitPendingWorktrees()
        case .pane:
            return
        }
    }

    package func assertTopology(_ assertion: FilesystemTopologyAssertion) {
        guard shouldApplyTopologyAssertion(assertion) else { return }

        latestTopologyAssertion = assertion

        let desiredWorktreeIds = Set(assertion.contextsByWorktreeId.keys)
        let removedWorktreeIds = Set(rootPathByWorktreeId.keys).subtracting(desiredWorktreeIds)
        for worktreeId in removedWorktreeIds.sorted(by: { $0.uuidString < $1.uuidString }) {
            applyUnregistration(
                worktreeId: worktreeId,
                repoId: repoIdByWorktreeId[worktreeId] ?? worktreeId
            )
        }

        for (worktreeId, context) in assertion.contextsByWorktreeId.sorted(by: { lhs, rhs in
            lhs.key.uuidString < rhs.key.uuidString
        }) {
            let currentContext = registeredContext(for: worktreeId)
            guard currentContext != context else { continue }
            applyRegistration(
                worktreeId: worktreeId,
                context: context,
                timestamp: envelopeClock.now
            )
        }
    }

    package func setActivity(worktreeId: UUID, isActiveInApp: Bool) {
        if isActiveInApp {
            activeWorktreeIds.insert(worktreeId)
            scheduleAutomaticRefresh(worktreeId: worktreeId, allowsPromptMissingBaseline: true)
        } else {
            activeWorktreeIds.remove(worktreeId)
            if activePaneWorktreeId != worktreeId, !sidebarVisibleWorktreeIds.contains(worktreeId) {
                tierEligibleWorktreeIds.remove(worktreeId)
            }
        }
    }

    package func setActivePaneWorktree(worktreeId: UUID?) {
        let previousActivePaneWorktreeId = activePaneWorktreeId
        activePaneWorktreeId = worktreeId
        if let previousActivePaneWorktreeId,
            previousActivePaneWorktreeId != worktreeId,
            !sidebarVisibleWorktreeIds.contains(previousActivePaneWorktreeId),
            !activeWorktreeIds.contains(previousActivePaneWorktreeId)
        {
            tierEligibleWorktreeIds.remove(previousActivePaneWorktreeId)
        }
        guard let worktreeId else { return }
        scheduleAutomaticRefresh(worktreeId: worktreeId, allowsPromptMissingBaseline: true)
    }

    package func setSidebarVisibleWorktrees(_ worktreeIds: Set<UUID>) {
        guard worktreeIds != sidebarVisibleWorktreeIds else { return }
        let noLongerVisibleWorktreeIds = sidebarVisibleWorktreeIds.subtracting(worktreeIds)
        sidebarVisibleWorktreeIds = worktreeIds
        for worktreeId in noLongerVisibleWorktreeIds
        where activePaneWorktreeId != worktreeId && !activeWorktreeIds.contains(worktreeId) {
            tierEligibleWorktreeIds.remove(worktreeId)
        }
        scheduleCoalescedVisibilityAdmission()
    }

    package func refreshRegisteredWorktreesImmediately() {
        for worktreeId in rootPathByWorktreeId.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            enqueueImmediateRefreshIfRegistered(
                worktreeId: worktreeId,
                triggerSource: .visibilityChange,
                isExplicit: true
            )
        }
    }

    package func refreshRegisteredWorktreesIntersecting(_ watchedPaths: [URL]) {
        let canonicalWatchedPaths = watchedPaths.map { watchedPath in
            FilesystemRootOwnership.canonicalRootPath(for: watchedPath)
        }
        for (worktreeId, rootPath) in rootPathByWorktreeId.sorted(by: { lhs, rhs in
            lhs.key.uuidString < rhs.key.uuidString
        }) {
            let canonicalRootPath = FilesystemRootOwnership.canonicalRootPath(for: rootPath)
            guard
                canonicalWatchedPaths.contains(where: { watchedPath in
                    Self.pathsIntersect(canonicalRootPath, watchedPath)
                })
            else { continue }
            enqueueImmediateRefreshIfRegistered(
                worktreeId: worktreeId,
                triggerSource: .visibilityChange,
                isExplicit: true
            )
        }
    }

    func startDrainTask(worktreeId: UUID) {
        nextWorktreeTaskGeneration &+= 1
        let taskGeneration = nextWorktreeTaskGeneration
        worktreeTaskGenerationByWorktreeId[worktreeId] = taskGeneration
        worktreeTasks[worktreeId] = Task { [weak self] in
            guard let self else { return }
            await self.drainWorktree(worktreeId: worktreeId, taskGeneration: taskGeneration)
        }
        recordLogicalDebtSnapshotIfChanged()
    }

    private func shouldApplyTopologyAssertion(_ assertion: FilesystemTopologyAssertion) -> Bool {
        guard let latestTopologyAssertion else { return true }
        guard assertion.generation >= latestTopologyAssertion.generation else { return false }
        guard
            assertion.generation != latestTopologyAssertion.generation
                || assertion.contextsByWorktreeId != latestTopologyAssertion.contextsByWorktreeId
        else {
            return false
        }
        return true
    }

    private func acceptsLifecycleRegistration(
        worktreeId: UUID,
        context: WorktreeFilesystemContext
    ) -> Bool {
        guard let latestTopologyAssertion else { return true }
        return latestTopologyAssertion.contextsByWorktreeId[worktreeId] == context
    }

    private func acceptsFilesystemChanges(_ changeset: FileChangeset) -> Bool {
        guard let latestTopologyAssertion else { return true }
        let context = WorktreeFilesystemContext(repoId: changeset.repoId, rootPath: changeset.rootPath)
        return latestTopologyAssertion.contextsByWorktreeId[changeset.worktreeId] == context
    }

    private func applyRegistration(
        worktreeId: UUID,
        context: WorktreeFilesystemContext,
        timestamp: ContinuousClock.Instant
    ) {
        let previousContext = registeredContext(for: worktreeId)
        guard previousContext != context else {
            removeSuppressedWorktree(worktreeId)
            return
        }
        if previousContext != nil, previousContext != context {
            lastEmittedSnapshotByWorktreeId.removeValue(forKey: worktreeId)
            lastStatusEntriesByWorktreeId.removeValue(forKey: worktreeId)
            lastAcceptedStatusFactsByWorktreeId.removeValue(forKey: worktreeId)
            lastAcceptedLineDetailByWorktreeId.removeValue(forKey: worktreeId)
            lastAcceptedLineDetailAtByWorktreeId.removeValue(forKey: worktreeId)
            lastAcceptedStatusAtByWorktreeId.removeValue(forKey: worktreeId)
            automaticRefreshDeadlineByWorktreeId.removeValue(forKey: worktreeId)
            lastAutomaticStartAtByWorktreeId.removeValue(forKey: worktreeId)
            lastAutomaticCompletionAtByWorktreeId.removeValue(forKey: worktreeId)
            lastAutomaticDutyByWorktreeId.removeValue(forKey: worktreeId)
            consecutiveStatusFailureCountByWorktreeId.removeValue(forKey: worktreeId)
            clearCapacityRetryState(worktreeId: worktreeId)
            clearStatusBackoffState(worktreeId: worktreeId)
            clearQuarantineState(worktreeId: worktreeId)
            resetAdaptiveCadence(worktreeId: worktreeId)
            worktreeTasks.removeValue(forKey: worktreeId)?.cancel()
            worktreeTaskGenerationByWorktreeId.removeValue(forKey: worktreeId)
            immediateRefreshWorktreeIds.remove(worktreeId)
            coalescingWorktreeIds.remove(worktreeId)
        }

        removeSuppressedWorktree(worktreeId)
        repoIdByWorktreeId[worktreeId] = context.repoId
        rootPathByWorktreeId[worktreeId] = context.rootPath
        nextPeriodicBatchSeqByWorktreeId[worktreeId] = nextPeriodicBatchSeqByWorktreeId[worktreeId] ?? 0
        let registrationChangeset = FileChangeset(
            worktreeId: worktreeId,
            repoId: context.repoId,
            rootPath: context.rootPath,
            paths: [],
            containsGitInternalChanges: true,
            timestamp: timestamp,
            batchSeq: 0
        )
        pendingByWorktreeId[worktreeId] = registrationChangeset
        refreshAttribution.triggerSourceByWorktreeId[worktreeId] = .registration
        scheduleAutomaticRefresh(
            worktreeId: worktreeId,
            missingBaseline: true,
            allowsPromptMissingBaseline: demandTier(for: worktreeId) != .background
        )
    }

    private func applyUnregistration(worktreeId: UUID, repoId: UUID) {
        addSuppressedWorktree(worktreeId)
        pendingByWorktreeId.removeValue(forKey: worktreeId)
        immediateRefreshWorktreeIds.remove(worktreeId)
        explicitRefreshWorktreeIds.remove(worktreeId)
        tierEligibleWorktreeIds.remove(worktreeId)
        admittedDemandTierByWorktreeId.removeValue(forKey: worktreeId)
        admissionStartedAtByWorktreeId.removeValue(forKey: worktreeId)
        coalescingWorktreeIds.remove(worktreeId)
        activeWorktreeIds.remove(worktreeId)
        sidebarVisibleWorktreeIds.remove(worktreeId)
        lastProcessedSidebarVisibleWorktreeIds.remove(worktreeId)
        pendingVisibilityDeltaWorktreeIds.remove(worktreeId)
        if activePaneWorktreeId == worktreeId {
            activePaneWorktreeId = nil
        }
        repoIdByWorktreeId.removeValue(forKey: worktreeId)
        rootPathByWorktreeId.removeValue(forKey: worktreeId)
        lastEmittedSnapshotByWorktreeId.removeValue(forKey: worktreeId)
        lastStatusEntriesByWorktreeId.removeValue(forKey: worktreeId)
        lastAcceptedStatusFactsByWorktreeId.removeValue(forKey: worktreeId)
        lastAcceptedLineDetailByWorktreeId.removeValue(forKey: worktreeId)
        lastAcceptedLineDetailAtByWorktreeId.removeValue(forKey: worktreeId)
        lastAcceptedStatusAtByWorktreeId.removeValue(forKey: worktreeId)
        automaticRefreshDeadlineByWorktreeId.removeValue(forKey: worktreeId)
        lastAutomaticStartAtByWorktreeId.removeValue(forKey: worktreeId)
        lastAutomaticCompletionAtByWorktreeId.removeValue(forKey: worktreeId)
        lastAutomaticDutyByWorktreeId.removeValue(forKey: worktreeId)
        consecutiveStatusFailureCountByWorktreeId.removeValue(forKey: worktreeId)
        clearCapacityRetryState(worktreeId: worktreeId)
        clearStatusBackoffState(worktreeId: worktreeId)
        clearQuarantineState(worktreeId: worktreeId)
        resetAdaptiveCadence(worktreeId: worktreeId)
        nextPeriodicBatchSeqByWorktreeId.removeValue(forKey: worktreeId)
        if !repoIdByWorktreeId.values.contains(repoId) {
            lastKnownOriginByRepoId.removeValue(forKey: repoId)
            originResolutionByRepoId.removeValue(forKey: repoId)
        }
        if let task = worktreeTasks.removeValue(forKey: worktreeId) {
            task.cancel()
        }
        worktreeTaskGenerationByWorktreeId.removeValue(forKey: worktreeId)
        rescheduleDeadlineTask()
        recordLogicalDebtSnapshotIfChanged()
    }

    private func addSuppressedWorktree(_ worktreeId: UUID) {
        guard suppressedWorktreeIds.insert(worktreeId).inserted else { return }
        suppressedWorktreeOrder.append(worktreeId)
        while suppressedWorktreeOrder.count > refreshPolicy.suppressedWorktreeTombstoneLimit {
            let evictedWorktreeId = suppressedWorktreeOrder.removeFirst()
            suppressedWorktreeIds.remove(evictedWorktreeId)
        }
    }

    private func removeSuppressedWorktree(_ worktreeId: UUID) {
        guard suppressedWorktreeIds.remove(worktreeId) != nil else { return }
        suppressedWorktreeOrder.removeAll { $0 == worktreeId }
    }

    func clearImmediateRefreshIntent(worktreeId: UUID) {
        immediateRefreshWorktreeIds.remove(worktreeId)
        explicitRefreshWorktreeIds.remove(worktreeId)
    }

    private func drainWorktree(worktreeId: UUID, taskGeneration: UInt64) async {
        defer {
            if worktreeTaskGenerationByWorktreeId[worktreeId] == taskGeneration {
                worktreeTasks.removeValue(forKey: worktreeId)
                worktreeTaskGenerationByWorktreeId.removeValue(forKey: worktreeId)
                admittedDemandTierByWorktreeId.removeValue(forKey: worktreeId)
                admitPendingWorktrees()
                recordLogicalDebtSnapshotIfChanged()
            }
        }

        guard !Task.isCancelled else { return }
        guard !capacityRetryWorktreeIds.contains(worktreeId) else { return }
        guard var nextChangeset = pendingByWorktreeId.removeValue(forKey: worktreeId) else {
            return
        }
        recordLogicalDebtSnapshotIfChanged()
        let shouldCoalesce = immediateRefreshWorktreeIds.remove(worktreeId) == nil && coalescingWindow > .zero
        if shouldCoalesce {
            coalescingWorktreeIds.insert(worktreeId)
            do {
                try await delay.wait(coalescingWindow)
            } catch is CancellationError {
                coalescingWorktreeIds.remove(worktreeId)
                return
            } catch {
                coalescingWorktreeIds.remove(worktreeId)
                Self.logger.warning(
                    "Unexpected projector sleep failure for worktree \(worktreeId.uuidString, privacy: .public): \(String(describing: error), privacy: .public)"
                )
                return
            }
            coalescingWorktreeIds.remove(worktreeId)
            guard !Task.isCancelled else { return }
            if let newer = pendingByWorktreeId.removeValue(forKey: worktreeId) {
                recordLogicalDebtSnapshotIfChanged()
                nextChangeset = Self.mergeChangesets(nextChangeset, with: newer)
                _ = immediateRefreshWorktreeIds.remove(worktreeId)
            }
        }

        await computeAndEmit(changeset: nextChangeset)
    }

    private func computeAndEmit(changeset: FileChangeset) async {
        guard !Task.isCancelled else { return }
        guard !suppressedWorktreeIds.contains(changeset.worktreeId) else { return }

        // Provider contract: expensive git compute must run off actor isolation.
        // A file-change batch with a cached snapshot is scoped to just the changed
        // paths and folded into the cache; everything else is a full status.
        let computeStart = envelopeClock.now
        let physicalCompletionGeneration = gitWorkingTreeProvider.physicalCompletionGeneration()
        let resolved = await resolveStatusResult(for: changeset)
        guard !Task.isCancelled else { return }
        guard !suppressedWorktreeIds.contains(changeset.worktreeId) else { return }
        guard isCurrentForPublication(changeset) else { return }
        guard case .available(let statusFacts) = resolved.result else {
            await handleUnavailableStatusResult(
                resolved.result.statusResult,
                physicalCompletionGeneration: physicalCompletionGeneration,
                changeset: changeset,
                computeStart: computeStart,
                scope: resolved.scope,
                pathspecCount: resolved.pathspecCount
            )
            return
        }
        let materialized = await materializeCompleteStatus(facts: statusFacts, changeset: changeset)
        guard !Task.isCancelled, !isShuttingDown, isCurrentForPublication(changeset) else { return }
        guard case .available(let statusSnapshot) = materialized.result else {
            await handleUnavailableStatusResult(
                materialized.result,
                physicalCompletionGeneration: materialized.capacityCompletionGeneration,
                changeset: changeset,
                computeStart: computeStart,
                scope: resolved.scope,
                pathspecCount: resolved.pathspecCount
            )
            return
        }
        await handleAvailableStatusResult(
            statusSnapshot,
            materialized: materialized,
            changeset: changeset,
            computeStart: computeStart,
            scope: resolved.scope,
            pathspecCount: resolved.pathspecCount
        )
    }

    func emitOriginResolutionIfChanged(
        changeset: FileChangeset,
        statusSnapshot: GitWorkingTreeStatus
    ) async {
        let nextOriginResolution = statusSnapshot.originResolution
        let previousOriginResolution = originResolutionByRepoId[changeset.repoId]

        switch nextOriginResolution {
        case .awaitingResolution:
            originResolutionByRepoId[changeset.repoId] = .awaitingResolution
            return
        case .confirmedAbsent:
            guard previousOriginResolution != .confirmedAbsent else { return }
            originResolutionByRepoId[changeset.repoId] = .confirmedAbsent
            lastKnownOriginByRepoId.removeValue(forKey: changeset.repoId)
            await emitGitWorkingDirectoryEvent(
                worktreeId: changeset.worktreeId,
                repoId: changeset.repoId,
                event: .originUnavailable(repoId: changeset.repoId)
            )
        case .resolved(let currentOrigin):
            let trimmedOrigin = currentOrigin.trimmingCharacters(in: .whitespacesAndNewlines)
            let previousOrigin = lastKnownOriginByRepoId[changeset.repoId]
            guard previousOrigin != trimmedOrigin else {
                originResolutionByRepoId[changeset.repoId] = .resolved(trimmedOrigin)
                return
            }
            originResolutionByRepoId[changeset.repoId] = .resolved(trimmedOrigin)
            lastKnownOriginByRepoId[changeset.repoId] = trimmedOrigin
            await emitGitWorkingDirectoryEvent(
                worktreeId: changeset.worktreeId,
                repoId: changeset.repoId,
                event: .originChanged(
                    repoId: changeset.repoId,
                    from: previousOrigin ?? "",
                    to: trimmedOrigin
                )
            )
        }
    }

    private func handleUnavailableStatusResult(
        _ statusResult: GitWorkingTreeStatusResult,
        physicalCompletionGeneration: UInt64?,
        changeset: FileChangeset,
        computeStart: ContinuousClock.Instant,
        scope: GitStatusScope,
        pathspecCount: Int
    ) async {
        guard isCurrentForPublication(changeset) else { return }
        guard case .unavailable(let unavailable) = statusResult else { return }
        if unavailable.reason == .readCapacityExceeded || unavailable.reason == .readAlreadyInFlight {
            admissionStartedAtByWorktreeId.removeValue(forKey: changeset.worktreeId)
            scheduleCapacityRetry(
                for: changeset,
                afterPhysicalCompletionGeneration: physicalCompletionGeneration
            )
            return
        }

        let statusCompletion = envelopeClock.now
        let statusDuration = computeStart.duration(to: statusCompletion)
        let statusOutcome: GitStatusOutcome
        let previousFailureCount = consecutiveStatusFailureCountByWorktreeId[changeset.worktreeId] ?? 0
        let consecutiveFailureCount = min(
            previousFailureCount + 1,
            AppPolicies.GitRefresh.statusUnavailableConsecutiveFailureThreshold
        )
        consecutiveStatusFailureCountByWorktreeId[changeset.worktreeId] = consecutiveFailureCount
        statusOutcome = unavailable.reason == .timeout ? .timeout : .unavailable
        performanceTraceRecorder?.recordDuration(
            .gitStatusUnavailable,
            duration: statusDuration,
            attributes: gitStatusCompletionTraceAttributes(
                for: changeset,
                unavailable: unavailable,
                context: GitStatusCompletionTraceContext(
                    scope: scope,
                    pathspecCount: pathspecCount,
                    statusCompletion: statusCompletion,
                    outcome: statusOutcome,
                    consecutiveFailureCount: consecutiveFailureCount,
                    statusDuration: statusDuration
                )
            )
        )
        guard !Task.isCancelled, !isShuttingDown else { return }
        guard !suppressedWorktreeIds.contains(changeset.worktreeId) else { return }
        guard isCurrentForPublication(changeset) else { return }
        admissionStartedAtByWorktreeId.removeValue(forKey: changeset.worktreeId)
        openOrAdvanceStatusBackoff(for: changeset, reason: unavailable.reason)
        await emitGitWorkingDirectoryEvent(
            worktreeId: changeset.worktreeId,
            repoId: changeset.repoId,
            event: .statusOutcome(
                GitStatusOutcomeFact(
                    worktreeId: changeset.worktreeId,
                    repoId: changeset.repoId,
                    outcome: statusOutcome,
                    reason: unavailable.reason,
                    consecutiveFailureCount: consecutiveFailureCount
                ))
        )
    }

    func isCurrent(_ changeset: FileChangeset) -> Bool {
        let changesetContext = WorktreeFilesystemContext(repoId: changeset.repoId, rootPath: changeset.rootPath)
        guard let registeredContext = registeredContext(for: changeset.worktreeId) else {
            guard let latestTopologyAssertion else { return true }
            return latestTopologyAssertion.contextsByWorktreeId[changeset.worktreeId] == changesetContext
        }
        return registeredContext == changesetContext
    }

    func isCurrentForPublication(_ changeset: FileChangeset) -> Bool {
        guard isCurrent(changeset) else { return false }
        guard let pending = pendingByWorktreeId[changeset.worktreeId] else { return true }
        return pending.batchSeq <= changeset.batchSeq
    }

    func shouldCheckOrigin(for changeset: FileChangeset) -> Bool {
        if changeset.paths.isEmpty {
            return true
        }
        return changeset.paths.contains(where: Self.isGitConfigPath)
    }

    nonisolated private static func shouldRefresh(for changeset: FileChangeset) -> Bool {
        !changeset.paths.isEmpty
            || changeset.containsGitInternalChanges
            || changeset.suppressedGitInternalPathCount > 0
    }

    nonisolated private static func isGitConfigPath(_ relativePath: String) -> Bool {
        let normalizedPath =
            relativePath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return normalizedPath == ".git/config" || normalizedPath.hasSuffix("/.git/config")
    }

}
