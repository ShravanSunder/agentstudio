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
actor GitWorkingDirectoryProjector {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "GitWorkingDirectoryProjector")

    private let runtimeBus: EventBus<RuntimeEnvelope>
    private let gitWorkingTreeProvider: any GitWorkingTreeStatusProvider
    private let envelopeClock: ContinuousClock
    private let coalescingWindow: Duration
    private let periodicRefreshInterval: Duration?
    private let delay: AsyncDelay
    private let refreshPolicy: AppPolicies.GitRefresh.Policy
    private let subscriptionBufferLimit: Int
    let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?

    private var subscriptionTask: Task<Void, Never>?
    private var periodicRefreshTask: Task<Void, Never>?
    private var worktreeTasks: [UUID: Task<Void, Never>] = [:]
    private var worktreeTaskGenerationByWorktreeId: [UUID: UInt64] = [:]
    private var nextWorktreeTaskGeneration: UInt64 = 0
    private var nilStatusRetryTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingByWorktreeId: [UUID: FileChangeset] = [:]
    private var suppressedWorktreeIds: Set<UUID> = []
    private var suppressedWorktreeOrder: [UUID] = []
    private var rootPathByWorktreeId: [UUID: URL] = [:]
    private var latestTopologyAssertion: FilesystemTopologyAssertion?
    private var activeWorktreeIds: Set<UUID> = []
    private var activePaneWorktreeId: UUID?
    private var repoIdByWorktreeId: [UUID: UUID] = [:]
    private var lastKnownOriginByRepoId: [UUID: String] = [:]
    private var originResolutionByRepoId: [UUID: GitOriginResolution] = [:]
    private var lastEmittedSnapshotByWorktreeId: [UUID: GitWorkingTreeSnapshot] = [:]
    private var nilStatusRetryCountByWorktreeId: [UUID: Int] = [:]
    private var nextPeriodicBatchSeqByWorktreeId: [UUID: UInt64] = [:]
    private var periodicRefreshTick: UInt64 = 0
    private var nextEnvelopeSequence: UInt64 = 0
    var lastRecordedLogicalDebtSnapshot: GitLogicalDebtSnapshot?
    private var isShuttingDown = false

    var queuedLogicalDebtCount: Int {
        pendingByWorktreeId.count
    }

    var retryPendingLogicalDebtCount: Int {
        nilStatusRetryTasks.count
    }

    var runningLogicalDebtCount: Int {
        worktreeTasks.count
    }

    init(
        bus: EventBus<RuntimeEnvelope> = PaneRuntimeEventBus.shared,
        gitWorkingTreeProvider: any GitWorkingTreeStatusProvider = AgentStudioGitWorkingTreeStatusProvider(),
        envelopeClock: ContinuousClock = ContinuousClock(),
        coalescingWindow: Duration,
        periodicRefreshInterval: Duration? = nil,
        sleepClock: (any Clock<Duration> & Sendable)? = nil,
        refreshPolicy: AppPolicies.GitRefresh.Policy = AppPolicies.GitRefresh.defaultPolicy,
        subscriptionBufferLimit: Int = 256,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder? = nil
    ) {
        self.runtimeBus = bus
        self.gitWorkingTreeProvider = gitWorkingTreeProvider
        self.envelopeClock = envelopeClock
        self.coalescingWindow = coalescingWindow
        self.periodicRefreshInterval = periodicRefreshInterval
        delay = sleepClock.map(AsyncDelay.clock) ?? .taskSleep
        self.refreshPolicy = refreshPolicy
        self.subscriptionBufferLimit = subscriptionBufferLimit
        self.performanceTraceRecorder = performanceTraceRecorder
    }

    isolated deinit {
        subscriptionTask?.cancel()
        periodicRefreshTask?.cancel()
        for task in worktreeTasks.values {
            task.cancel()
        }
        for task in nilStatusRetryTasks.values {
            task.cancel()
        }
        worktreeTasks.removeAll(keepingCapacity: false)
        worktreeTaskGenerationByWorktreeId.removeAll(keepingCapacity: false)
        nilStatusRetryTasks.removeAll(keepingCapacity: false)
    }

    func start() async {
        guard subscriptionTask == nil else { return }
        isShuttingDown = false
        let stream = await runtimeBus.subscribe(
            policy: .lossyNewest(subscriptionBufferLimit),
            subscriberName: "GitWorkingDirectoryProjector"
        )
        subscriptionTask = Task { [weak self] in
            for await runtimeEnvelope in stream {
                guard !Task.isCancelled else { break }
                guard let self else { return }
                await self.handleIncomingRuntimeEnvelope(runtimeEnvelope)
            }
        }

        startPeriodicRefreshLoopIfNeeded()
    }

    func shutdown() async {
        isShuttingDown = true
        let subscription = subscriptionTask
        subscriptionTask?.cancel()
        subscriptionTask = nil
        let periodicRefresh = periodicRefreshTask
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil

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
        if let periodicRefresh {
            await periodicRefresh.value
        }
        for task in tasksToAwait {
            await task.value
        }
        for task in nilStatusRetryTasks.values {
            task.cancel()
        }
        nilStatusRetryTasks.removeAll(keepingCapacity: false)
        pendingByWorktreeId.removeAll(keepingCapacity: false)
        suppressedWorktreeIds.removeAll(keepingCapacity: false)
        suppressedWorktreeOrder.removeAll(keepingCapacity: false)
        rootPathByWorktreeId.removeAll(keepingCapacity: false)
        latestTopologyAssertion = nil
        activeWorktreeIds.removeAll(keepingCapacity: false)
        activePaneWorktreeId = nil
        repoIdByWorktreeId.removeAll(keepingCapacity: false)
        lastKnownOriginByRepoId.removeAll(keepingCapacity: false)
        originResolutionByRepoId.removeAll(keepingCapacity: false)
        lastEmittedSnapshotByWorktreeId.removeAll(keepingCapacity: false)
        nilStatusRetryCountByWorktreeId.removeAll(keepingCapacity: false)
        nextPeriodicBatchSeqByWorktreeId.removeAll(keepingCapacity: false)
        nextWorktreeTaskGeneration = 0
        periodicRefreshTick = 0
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
            repoIdByWorktreeId[worktreeId] = changeset.repoId
            pendingByWorktreeId[worktreeId] = changeset
            admitPendingWorktrees()
        case .pane:
            return
        }
    }

    func assertTopology(_ assertion: FilesystemTopologyAssertion) {
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

    func setActivity(worktreeId: UUID, isActiveInApp: Bool) {
        if isActiveInApp {
            activeWorktreeIds.insert(worktreeId)
            enqueueSyntheticRefreshIfRegistered(worktreeId: worktreeId)
        } else {
            activeWorktreeIds.remove(worktreeId)
        }
    }

    func setActivePaneWorktree(worktreeId: UUID?) {
        activePaneWorktreeId = worktreeId
        guard let worktreeId else { return }
        enqueueSyntheticRefreshIfRegistered(worktreeId: worktreeId)
    }

    private func admitPendingWorktrees() {
        defer { recordLogicalDebtSnapshotIfChanged() }
        guard !isShuttingDown else { return }
        let availableSlots = refreshPolicy.maxConcurrentStatusComputes - worktreeTasks.count
        guard availableSlots > 0 else { return }

        let eligibleWorktreeIds = pendingByWorktreeId.keys.filter { worktreeId in
            worktreeTasks[worktreeId] == nil && !suppressedWorktreeIds.contains(worktreeId)
        }
        guard !eligibleWorktreeIds.isEmpty else { return }

        var admittedWorktreeIds: [UUID] = []
        let reservedSlotCount = min(refreshPolicy.oldestStaleReservedSlots, availableSlots)
        if reservedSlotCount > 0 {
            admittedWorktreeIds.append(
                contentsOf:
                    eligibleWorktreeIds
                    .filter { priorityKey(for: $0) == 2 }
                    .sorted(by: sortPendingWorktreeByStaleness)
                    .prefix(reservedSlotCount)
            )
        }

        let remainingSlotCount = availableSlots - admittedWorktreeIds.count
        if remainingSlotCount > 0 {
            let alreadyAdmitted = Set(admittedWorktreeIds)
            admittedWorktreeIds.append(
                contentsOf:
                    eligibleWorktreeIds
                    .filter { !alreadyAdmitted.contains($0) }
                    .sorted(by: sortPendingWorktreeByPriority)
                    .prefix(remainingSlotCount)
            )
        }

        for worktreeId in admittedWorktreeIds {
            startDrainTask(worktreeId: worktreeId)
        }
        guard !admittedWorktreeIds.isEmpty else { return }
        performanceTraceRecorder?.record(
            .gitAdmission,
            attributes: [
                "agentstudio.performance.git.admitted.count": .int(admittedWorktreeIds.count),
                "agentstudio.performance.git.pending.count": .int(pendingByWorktreeId.count),
                "agentstudio.performance.git.running.count": .int(worktreeTasks.count),
                "agentstudio.performance.git.available_slot.count": .int(availableSlots),
            ]
        )
    }

    private func startDrainTask(worktreeId: UUID) {
        nextWorktreeTaskGeneration &+= 1
        let taskGeneration = nextWorktreeTaskGeneration
        worktreeTaskGenerationByWorktreeId[worktreeId] = taskGeneration
        worktreeTasks[worktreeId] = Task { [weak self] in
            guard let self else { return }
            await self.drainWorktree(worktreeId: worktreeId, taskGeneration: taskGeneration)
        }
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

    private func registeredContext(for worktreeId: UUID) -> WorktreeFilesystemContext? {
        guard let repoId = repoIdByWorktreeId[worktreeId],
            let rootPath = rootPathByWorktreeId[worktreeId]
        else {
            return nil
        }
        return WorktreeFilesystemContext(repoId: repoId, rootPath: rootPath)
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
            nilStatusRetryCountByWorktreeId.removeValue(forKey: worktreeId)
            cancelNilStatusRetry(worktreeId: worktreeId)
            worktreeTasks.removeValue(forKey: worktreeId)?.cancel()
            worktreeTaskGenerationByWorktreeId.removeValue(forKey: worktreeId)
        }

        removeSuppressedWorktree(worktreeId)
        repoIdByWorktreeId[worktreeId] = context.repoId
        rootPathByWorktreeId[worktreeId] = context.rootPath
        nextPeriodicBatchSeqByWorktreeId[worktreeId] = nextPeriodicBatchSeqByWorktreeId[worktreeId] ?? 0
        pendingByWorktreeId[worktreeId] = FileChangeset(
            worktreeId: worktreeId,
            repoId: context.repoId,
            rootPath: context.rootPath,
            paths: [],
            containsGitInternalChanges: true,
            timestamp: timestamp,
            batchSeq: 0
        )
        admitPendingWorktrees()
    }

    private func applyUnregistration(worktreeId: UUID, repoId: UUID) {
        addSuppressedWorktree(worktreeId)
        pendingByWorktreeId.removeValue(forKey: worktreeId)
        activeWorktreeIds.remove(worktreeId)
        if activePaneWorktreeId == worktreeId {
            activePaneWorktreeId = nil
        }
        repoIdByWorktreeId.removeValue(forKey: worktreeId)
        rootPathByWorktreeId.removeValue(forKey: worktreeId)
        lastEmittedSnapshotByWorktreeId.removeValue(forKey: worktreeId)
        nilStatusRetryCountByWorktreeId.removeValue(forKey: worktreeId)
        cancelNilStatusRetry(worktreeId: worktreeId)
        nextPeriodicBatchSeqByWorktreeId.removeValue(forKey: worktreeId)
        if !repoIdByWorktreeId.values.contains(repoId) {
            lastKnownOriginByRepoId.removeValue(forKey: repoId)
            originResolutionByRepoId.removeValue(forKey: repoId)
        }
        if let task = worktreeTasks.removeValue(forKey: worktreeId) {
            task.cancel()
        }
        worktreeTaskGenerationByWorktreeId.removeValue(forKey: worktreeId)
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

    private func cancelNilStatusRetry(worktreeId: UUID) {
        nilStatusRetryTasks.removeValue(forKey: worktreeId)?.cancel()
    }

    private func enqueueSyntheticRefreshIfRegistered(worktreeId: UUID) {
        guard !suppressedWorktreeIds.contains(worktreeId) else { return }
        guard let context = registeredContext(for: worktreeId) else { return }

        let nextBatchSeq = (nextPeriodicBatchSeqByWorktreeId[worktreeId] ?? 0) + 1
        nextPeriodicBatchSeqByWorktreeId[worktreeId] = nextBatchSeq
        pendingByWorktreeId[worktreeId] = FileChangeset(
            worktreeId: worktreeId,
            repoId: context.repoId,
            rootPath: context.rootPath,
            paths: [],
            containsGitInternalChanges: true,
            timestamp: envelopeClock.now,
            batchSeq: nextBatchSeq
        )
        admitPendingWorktrees()
    }

    private func sortPendingWorktreeByPriority(_ lhs: UUID, _ rhs: UUID) -> Bool {
        let lhsPriority = priorityKey(for: lhs)
        let rhsPriority = priorityKey(for: rhs)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }
        return lhs.uuidString < rhs.uuidString
    }

    private func sortPendingWorktreeByStaleness(_ lhs: UUID, _ rhs: UUID) -> Bool {
        guard let lhsChangeset = pendingByWorktreeId[lhs] else { return false }
        guard let rhsChangeset = pendingByWorktreeId[rhs] else { return true }
        if lhsChangeset.timestamp != rhsChangeset.timestamp {
            return lhsChangeset.timestamp < rhsChangeset.timestamp
        }
        if lhsChangeset.batchSeq != rhsChangeset.batchSeq {
            return lhsChangeset.batchSeq < rhsChangeset.batchSeq
        }
        return lhs.uuidString < rhs.uuidString
    }

    private func priorityKey(for worktreeId: UUID) -> Int {
        if activePaneWorktreeId == worktreeId {
            return 0
        }
        if activeWorktreeIds.contains(worktreeId) {
            return 1
        }
        return 2
    }

    private func drainWorktree(worktreeId: UUID, taskGeneration: UInt64) async {
        defer {
            if worktreeTaskGenerationByWorktreeId[worktreeId] == taskGeneration {
                worktreeTasks.removeValue(forKey: worktreeId)
                worktreeTaskGenerationByWorktreeId.removeValue(forKey: worktreeId)
                admitPendingWorktrees()
            }
        }

        while !Task.isCancelled {
            guard var nextChangeset = pendingByWorktreeId.removeValue(forKey: worktreeId) else {
                return
            }
            recordLogicalDebtSnapshotIfChanged()
            if coalescingWindow > .zero {
                do {
                    try await delay.wait(coalescingWindow)
                } catch is CancellationError {
                    return
                } catch {
                    Self.logger.warning(
                        "Unexpected projector sleep failure for worktree \(worktreeId.uuidString, privacy: .public): \(String(describing: error), privacy: .public)"
                    )
                    continue
                }
                guard !Task.isCancelled else { return }
                if let newer = pendingByWorktreeId.removeValue(forKey: worktreeId) {
                    recordLogicalDebtSnapshotIfChanged()
                    nextChangeset = newer
                }
            }

            await computeAndEmit(changeset: nextChangeset)
        }
    }

    private func computeAndEmit(changeset: FileChangeset) async {
        guard !Task.isCancelled else { return }
        guard !suppressedWorktreeIds.contains(changeset.worktreeId) else { return }

        // Provider contract: expensive git compute must run off actor isolation.
        let computeStart = envelopeClock.now
        let statusResult = await gitWorkingTreeProvider.statusResult(for: changeset.rootPath)
        guard case .available(let statusSnapshot) = statusResult else {
            handleUnavailableStatusResult(statusResult, changeset: changeset, computeStart: computeStart)
            return
        }
        performanceTraceRecorder?.recordDuration(
            .gitStatusComputed,
            duration: computeStart.duration(to: envelopeClock.now),
            attributes: gitStatusTraceAttributes(for: changeset, unavailable: nil)
        )
        nilStatusRetryCountByWorktreeId.removeValue(forKey: changeset.worktreeId)
        guard !Task.isCancelled else { return }
        guard !suppressedWorktreeIds.contains(changeset.worktreeId) else { return }
        guard isCurrent(changeset) else { return }

        let nextSnapshot = GitWorkingTreeSnapshot(
            worktreeId: changeset.worktreeId,
            repoId: changeset.repoId,
            rootPath: changeset.rootPath,
            summary: statusSnapshot.summary,
            branch: statusSnapshot.branch
        )
        let previousSnapshot = lastEmittedSnapshotByWorktreeId[changeset.worktreeId]
        if previousSnapshot != nextSnapshot {
            lastEmittedSnapshotByWorktreeId[changeset.worktreeId] = nextSnapshot
            await emitGitWorkingDirectoryEvent(
                worktreeId: changeset.worktreeId,
                repoId: changeset.repoId,
                event: .snapshotChanged(
                    snapshot: nextSnapshot
                )
            )
        } else {
            performanceTraceRecorder?.record(
                .gitSnapshotDedup,
                attributes: [
                    "agentstudio.performance.git.snapshot_dedup.count": .int(1)
                ]
            )
        }

        if let previousSnapshot,
            let nextBranch = statusSnapshot.branch,
            previousSnapshot.branch != nextBranch
        {
            await emitGitWorkingDirectoryEvent(
                worktreeId: changeset.worktreeId,
                repoId: changeset.repoId,
                event: .branchChanged(
                    worktreeId: changeset.worktreeId,
                    repoId: changeset.repoId,
                    from: previousSnapshot.branch ?? "",
                    to: nextBranch
                )
            )
        }
        guard shouldCheckOrigin(for: changeset) else { return }

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
        changeset: FileChangeset,
        computeStart: ContinuousClock.Instant
    ) {
        guard isCurrent(changeset) else { return }
        guard case .unavailable(let unavailable) = statusResult else { return }

        performanceTraceRecorder?.recordDuration(
            .gitStatusUnavailable,
            duration: computeStart.duration(to: envelopeClock.now),
            attributes: gitStatusTraceAttributes(for: changeset, unavailable: unavailable)
        )
        scheduleNilStatusRetry(for: changeset)
    }

    private func scheduleNilStatusRetry(for changeset: FileChangeset) {
        let retryCount = nilStatusRetryCountByWorktreeId[changeset.worktreeId] ?? 0
        guard retryCount < refreshPolicy.maxNilStatusRetries else {
            nilStatusRetryCountByWorktreeId.removeValue(forKey: changeset.worktreeId)
            Self.logger.error(
                """
                Git snapshot unavailable for worktree \(changeset.worktreeId.uuidString, privacy: .public) \
                root=\(changeset.rootPath.path, privacy: .public). \
                See FilesystemGitWorkingTree logs for failure category.
                """
            )
            return
        }

        nilStatusRetryCountByWorktreeId[changeset.worktreeId] = retryCount + 1
        nilStatusRetryTasks[changeset.worktreeId]?.cancel()
        let delay = self.delay
        let nilStatusRetryDelay = refreshPolicy.nilStatusRetryDelay
        nilStatusRetryTasks[changeset.worktreeId] = Task { [weak self, delay, nilStatusRetryDelay] in
            do {
                try await delay.wait(nilStatusRetryDelay)
            } catch is CancellationError {
                return
            } catch {
                Self.logger.warning(
                    "Unexpected nil-status retry sleep failure for worktree \(changeset.worktreeId.uuidString, privacy: .public): \(String(describing: error), privacy: .public)"
                )
                return
            }

            guard !Task.isCancelled else { return }
            await self?.enqueueNilStatusRetry(changeset)
        }
        recordLogicalDebtSnapshotIfChanged()
    }

    private func enqueueNilStatusRetry(_ changeset: FileChangeset) {
        nilStatusRetryTasks.removeValue(forKey: changeset.worktreeId)
        guard !isShuttingDown else { return }
        guard !suppressedWorktreeIds.contains(changeset.worktreeId) else { return }
        guard isCurrent(changeset) else { return }
        if pendingByWorktreeId[changeset.worktreeId] == nil {
            pendingByWorktreeId[changeset.worktreeId] = changeset
            admitPendingWorktrees()
        }
        recordLogicalDebtSnapshotIfChanged()
    }

    private func isCurrent(_ changeset: FileChangeset) -> Bool {
        let changesetContext = WorktreeFilesystemContext(repoId: changeset.repoId, rootPath: changeset.rootPath)
        guard let registeredContext = registeredContext(for: changeset.worktreeId) else {
            guard let latestTopologyAssertion else { return true }
            return latestTopologyAssertion.contextsByWorktreeId[changeset.worktreeId] == changesetContext
        }
        return registeredContext == changesetContext
    }

    private func shouldCheckOrigin(for changeset: FileChangeset) -> Bool {
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

    private func emitGitWorkingDirectoryEvent(
        worktreeId: UUID,
        repoId: UUID,
        event: GitWorkingDirectoryEvent
    ) async {
        nextEnvelopeSequence += 1
        let envelope = RuntimeEnvelope.worktree(
            WorktreeEnvelope(
                source: .system(.builtin(.gitWorkingDirectoryProjector)),
                seq: nextEnvelopeSequence,
                timestamp: envelopeClock.now,
                repoId: repoId,
                worktreeId: worktreeId,
                event: .gitWorkingDirectory(event)
            )
        )

        let droppedCount = (await runtimeBus.post(envelope)).droppedCount
        if droppedCount > 0 {
            Self.logger.warning(
                "Git projector event delivery dropped for \(droppedCount, privacy: .public) subscriber(s); seq=\(self.nextEnvelopeSequence, privacy: .public)"
            )
        }
        performanceTraceRecorder?.record(
            .gitEventPosted,
            attributes: [
                "agentstudio.performance.git.event_posted.count": .int(1),
                "agentstudio.performance.git.dropped_subscriber.count": .int(droppedCount),
            ]
        )
        Self.logger.debug("Posted git projector event for worktree \(worktreeId.uuidString, privacy: .public)")
    }

    private func startPeriodicRefreshLoopIfNeeded() {
        guard let periodicRefreshInterval else { return }
        guard periodicRefreshInterval > .zero else { return }
        guard periodicRefreshTask == nil else { return }

        let delay = self.delay
        periodicRefreshTask = Task { [weak self, delay, periodicRefreshInterval] in
            while !Task.isCancelled {
                do {
                    try await delay.wait(periodicRefreshInterval)
                } catch is CancellationError {
                    return
                } catch {
                    Self.logger.warning(
                        "Unexpected periodic git refresh sleep failure: \(String(describing: error), privacy: .public)"
                    )
                    continue
                }
                guard !Task.isCancelled else { return }
                guard let self else { return }
                await self.enqueuePeriodicRefreshes()
            }
        }
    }

    private func enqueuePeriodicRefreshes() {
        defer { periodicRefreshTick &+= 1 }
        guard !rootPathByWorktreeId.isEmpty else { return }

        var enqueuedCount = 0
        for worktreeId in rootPathByWorktreeId.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard !suppressedWorktreeIds.contains(worktreeId) else { continue }
            guard pendingByWorktreeId[worktreeId] == nil else { continue }
            guard isPeriodicRefreshDue(worktreeId: worktreeId) else { continue }
            guard let repoId = repoIdByWorktreeId[worktreeId] else { continue }
            guard let rootPath = rootPathByWorktreeId[worktreeId] else { continue }

            let nextBatchSeq = (nextPeriodicBatchSeqByWorktreeId[worktreeId] ?? 0) + 1
            nextPeriodicBatchSeqByWorktreeId[worktreeId] = nextBatchSeq

            pendingByWorktreeId[worktreeId] = FileChangeset(
                worktreeId: worktreeId,
                repoId: repoId,
                rootPath: rootPath,
                paths: [],
                containsGitInternalChanges: true,
                suppressedIgnoredPathCount: 0,
                suppressedGitInternalPathCount: 0,
                timestamp: envelopeClock.now,
                batchSeq: nextBatchSeq
            )
            enqueuedCount += 1
        }
        performanceTraceRecorder?.record(
            .gitTick,
            attributes: [
                "agentstudio.performance.git.enqueued.count": .int(enqueuedCount),
                "agentstudio.performance.git.registered.count": .int(rootPathByWorktreeId.count),
                "agentstudio.performance.git.pending.count": .int(pendingByWorktreeId.count),
                "agentstudio.performance.git.tick.count": .int(Int(periodicRefreshTick)),
            ]
        )
        admitPendingWorktrees()
    }

    private func isPeriodicRefreshDue(worktreeId: UUID) -> Bool {
        if activePaneWorktreeId == worktreeId || activeWorktreeIds.contains(worktreeId) {
            return true
        }
        return refreshPolicy.isBackgroundWorktreeDue(worktreeId, tick: periodicRefreshTick)
    }

    private func gitStatusTraceAttributes(
        for changeset: FileChangeset,
        unavailable: GitWorkingTreeStatusUnavailable?
    ) -> [String: AgentStudioTraceValue] {
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.performance.git.input_path.count": .int(changeset.paths.count),
            "agentstudio.performance.git.pending.count": .int(pendingByWorktreeId.count),
            "agentstudio.performance.git.running.count": .int(worktreeTasks.count),
            "agentstudio.performance.git.has_git_internal_changes": .bool(changeset.containsGitInternalChanges),
            "agentstudio.performance.git.suppressed_ignored_path.count": .int(changeset.suppressedIgnoredPathCount),
            "agentstudio.performance.git.suppressed_git_internal_path.count": .int(
                changeset.suppressedGitInternalPathCount
            ),
        ]
        if let unavailable {
            attributes["agentstudio.performance.git.status_unavailable.reason"] = .string(unavailable.reason.rawValue)
        }
        return attributes
    }
}
