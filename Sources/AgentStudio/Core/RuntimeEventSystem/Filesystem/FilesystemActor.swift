import Foundation
import os

/// App-wide filesystem ingress actor keyed by worktree registration.
///
/// The actor owns filesystem path ingestion, deepest-root ownership routing for nested roots,
/// priority-aware flush ordering, and envelope emission onto `EventBus`.
actor FilesystemActor {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "FilesystemActor")
    static let maxPathsPerFilesChangedEvent = 256

    private struct SchedulingClock: Sendable {
        let now: @Sendable () -> Duration
        let sleep: @Sendable (Duration) async throws -> Void

        static func continuous() -> Self {
            let clock = ContinuousClock()
            let origin = clock.now
            return Self(
                now: { origin.duration(to: clock.now) },
                sleep: { duration in
                    try await AsyncDelay.taskSleep.wait(duration)
                }
            )
        }

        static func make<C: Clock>(clock: C) -> Self where C.Duration == Duration, C: Sendable {
            let origin = clock.now
            let delay = AsyncDelay.clock(clock)
            return Self(
                now: { origin.duration(to: clock.now) },
                sleep: { duration in
                    try await delay.wait(duration)
                }
            )
        }
    }

    private struct RootState: Sendable {
        let repoId: UUID
        let rootPath: URL
        let canonicalRootPath: String
        var isActiveInApp: Bool
        var nextBatchSeq: UInt64
        var pathFilter: FilesystemPathFilter
    }

    private struct PendingWorktreeChanges: Sendable {
        var projectedPaths: Set<String> = []
        var containsGitInternalChanges = false
        var suppressedIgnoredPathCount = 0
        var suppressedGitInternalPathCount = 0
        var firstPendingTimestamp: Duration?
        var lastPendingTimestamp: Duration?

        var hasPendingChanges: Bool {
            !projectedPaths.isEmpty
                || containsGitInternalChanges
                || suppressedGitInternalPathCount > 0
        }

        mutating func recordPendingChange(at timestamp: Duration) {
            if firstPendingTimestamp == nil {
                firstPendingTimestamp = timestamp
            }
            lastPendingTimestamp = timestamp
        }
    }

    let runtimeBus: EventBus<RuntimeEnvelope>
    let fseventStreamClient: any FSEventStreamClient
    let envelopeClock = ContinuousClock()
    private let schedulingClock: SchedulingClock
    let watchedFolderScanScheduler: WatchedFolderScanScheduler
    private let debounceWindow: Duration
    private let maxFlushLatency: Duration
    let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?

    private var roots: [UUID: RootState] = [:]
    private var pendingChangesByWorktreeId: [UUID: PendingWorktreeChanges] = [:]
    private var activePaneWorktreeId: UUID?
    var nextEnvelopeSequence: UInt64 = 0

    var watchedFolderScanState = FilesystemWatchedFolderScanState()

    private var ingressTask: Task<Void, Never>?
    private var drainTask: Task<Void, Never>?
    var lastRecordedLogicalDebtSnapshot: FilesystemLogicalDebtSnapshot?
    var logicalDebtSnapshotPublicationRevision: UInt64 = 0
    private var hasShutdown = false

    init(
        bus: EventBus<RuntimeEnvelope> = PaneRuntimeEventBus.shared,
        fseventStreamClient: any FSEventStreamClient = DarwinFSEventStreamClient(),
        watchedFolderScanScheduler: WatchedFolderScanScheduler = .production(),
        debounceWindow: Duration = .milliseconds(500),
        maxFlushLatency: Duration = .seconds(2),
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder? = nil
    ) {
        self.runtimeBus = bus
        self.fseventStreamClient = fseventStreamClient
        self.watchedFolderScanScheduler = watchedFolderScanScheduler
        schedulingClock = .continuous()
        self.debounceWindow = debounceWindow
        self.maxFlushLatency = maxFlushLatency
        self.performanceTraceRecorder = performanceTraceRecorder
    }

    init<C: Clock>(
        bus: EventBus<RuntimeEnvelope> = PaneRuntimeEventBus.shared,
        fseventStreamClient: any FSEventStreamClient = DarwinFSEventStreamClient(),
        watchedFolderScanScheduler: WatchedFolderScanScheduler = .production(),
        sleepClock: C,
        debounceWindow: Duration = .milliseconds(500),
        maxFlushLatency: Duration = .seconds(2),
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder? = nil
    ) where C.Duration == Duration, C: Sendable {
        self.runtimeBus = bus
        self.fseventStreamClient = fseventStreamClient
        self.watchedFolderScanScheduler = watchedFolderScanScheduler
        schedulingClock = .make(clock: sleepClock)
        self.debounceWindow = debounceWindow
        self.maxFlushLatency = maxFlushLatency
        self.performanceTraceRecorder = performanceTraceRecorder
    }

    isolated deinit {
        ingressTask?.cancel()
        drainTask?.cancel()
        watchedFolderScanState.resultDrainState.task?.cancel()
        watchedFolderScanState.fallbackTask?.cancel()
        watchedFolderScanState.manualRefreshState.task?.cancel()
        if !hasShutdown {
            Self.logger.warning("FilesystemActor deinitialized without explicit shutdown()")
        }
    }

    func register(worktreeId: UUID, repoId: UUID, rootPath: URL) async {
        startIngressTaskIfNeeded()

        let canonicalRootPath = FilesystemRootOwnership.canonicalRootPath(for: rootPath)
        let pathFilter = await FilesystemPathFilter.loadOffExecutor(forRootPath: rootPath)

        let existing = roots[worktreeId]
        roots[worktreeId] = RootState(
            repoId: repoId,
            rootPath: rootPath,
            canonicalRootPath: canonicalRootPath,
            isActiveInApp: existing?.isActiveInApp ?? false,
            nextBatchSeq: existing?.nextBatchSeq ?? 0,
            pathFilter: pathFilter
        )
        pendingChangesByWorktreeId[worktreeId] = pendingChangesByWorktreeId[worktreeId] ?? PendingWorktreeChanges()
        fseventStreamClient.register(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)
        await emitFilesystemEvent(
            worktreeId: worktreeId,
            repoId: repoId,
            timestamp: envelopeClock.now,
            rootPathHint: rootPath,
            event: .worktreeRegistered(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)
        )
    }

    func unregister(worktreeId: UUID) async {
        let removedRoot = roots.removeValue(forKey: worktreeId)
        pendingChangesByWorktreeId.removeValue(forKey: worktreeId)
        if activePaneWorktreeId == worktreeId {
            activePaneWorktreeId = nil
        }
        fseventStreamClient.unregister(worktreeId: worktreeId)
        guard let removedRoot else { return }
        await emitFilesystemEvent(
            worktreeId: worktreeId,
            repoId: removedRoot.repoId,
            timestamp: envelopeClock.now,
            rootPathHint: removedRoot.rootPath,
            event: .worktreeUnregistered(worktreeId: worktreeId, repoId: removedRoot.repoId)
        )
    }

    func assertTopology(_ assertion: FilesystemTopologyAssertion) async {
        let desiredWorktreeIds = Set(assertion.contextsByWorktreeId.keys)
        let removedWorktreeIds = Set(roots.keys).subtracting(desiredWorktreeIds)
        for worktreeId in removedWorktreeIds.sorted(by: Self.sortWorktreeIds) {
            await unregister(worktreeId: worktreeId)
        }

        for (worktreeId, context) in assertion.contextsByWorktreeId.sorted(by: { lhs, rhs in
            Self.sortWorktreeIds(lhs.key, rhs.key)
        }) {
            guard
                roots[worktreeId]?.repoId != context.repoId
                    || roots[worktreeId]?.rootPath != context.rootPath
            else {
                continue
            }
            await register(worktreeId: worktreeId, repoId: context.repoId, rootPath: context.rootPath)
        }
    }

    /// Test seam for deterministic ingress without OS-level FSEvents.
    func enqueueRawPaths(worktreeId: UUID, paths: [String]) async {
        await ingestRawPaths(worktreeId: worktreeId, paths: paths)
    }

    func setActivity(worktreeId: UUID, isActiveInApp: Bool) {
        guard var root = roots[worktreeId] else {
            Self.logger.debug(
                "Ignored setActivity for unregistered worktree \(worktreeId.uuidString, privacy: .public)"
            )
            return
        }
        root.isActiveInApp = isActiveInApp
        roots[worktreeId] = root
    }

    func setActivePaneWorktree(worktreeId: UUID?) {
        activePaneWorktreeId = worktreeId
    }

    func start() async {
        // Ingress/drain tasks are initialized during actor init; start is explicit for
        // lifecycle parity with other filesystem source conformers.
    }

    func shutdown() async {
        guard !hasShutdown else { return }
        watchedFolderScanState.isShuttingDown = true
        let activeIngressTask = ingressTask
        let activeDrainTask = drainTask
        let activeWatchedFolderResultDrainTask = watchedFolderScanState.resultDrainState.task
        let activeFallbackTask = watchedFolderScanState.fallbackTask
        let activeManualWatchedFolderRefreshTask = watchedFolderScanState.manualRefreshState.task

        ingressTask?.cancel()
        ingressTask = nil
        drainTask?.cancel()
        drainTask = nil
        watchedFolderScanState.fallbackTask?.cancel()
        watchedFolderScanState.fallbackTask = nil
        cancelManualWatchedFolderRefreshForShutdown()

        // Keep the sole result consumer alive while scheduler shutdown drains
        // running, pending, and leased result custody.
        await watchedFolderScanScheduler.shutdown()

        if let activeIngressTask {
            await activeIngressTask.value
        }
        if let activeDrainTask {
            await activeDrainTask.value
        }
        if let activeWatchedFolderResultDrainTask {
            await activeWatchedFolderResultDrainTask.value
        }
        watchedFolderScanState.resultDrainState = .idle
        if let activeFallbackTask {
            await activeFallbackTask.value
        }
        if let activeManualWatchedFolderRefreshTask {
            _ = await activeManualWatchedFolderRefreshTask.value
        }

        roots.removeAll(keepingCapacity: false)
        pendingChangesByWorktreeId.removeAll(keepingCapacity: false)
        watchedFolderScanState = FilesystemWatchedFolderScanState()
        watchedFolderScanState.isShuttingDown = true
        activePaneWorktreeId = nil
        fseventStreamClient.shutdown()
        hasShutdown = true
    }

    private func ingestRawPaths(worktreeId: UUID, paths: [String]) async {
        guard roots[worktreeId] != nil else {
            Self.logger.debug(
                "Dropped filesystem path batch for unregistered worktree \(worktreeId.uuidString, privacy: .public)"
            )
            return
        }
        guard !paths.isEmpty else { return }

        let ownership = FilesystemRootOwnership(
            canonicalRootsByWorktree: roots.mapValues(\.canonicalRootPath)
        )

        for rawPath in paths {
            guard let ownedPath = ownership.route(sourceWorktreeId: worktreeId, rawPath: rawPath) else {
                Self.logger.debug(
                    "Dropped unroutable filesystem path for source worktree \(worktreeId.uuidString, privacy: .public): \(rawPath, privacy: .public)"
                )
                continue
            }

            guard let root = roots[ownedPath.worktreeId] else { continue }

            if Self.isGitIgnoreReloadPath(rawPath: rawPath, relativePath: ownedPath.relativePath) {
                let pathFilter = await FilesystemPathFilter.loadOffExecutor(forRootPath: root.rootPath)
                guard var latestRoot = roots[ownedPath.worktreeId] else { continue }
                latestRoot.pathFilter = pathFilter
                roots[ownedPath.worktreeId] = latestRoot

                var pendingChanges = pendingChangesByWorktreeId[ownedPath.worktreeId] ?? PendingWorktreeChanges()
                pendingChanges.containsGitInternalChanges = true
                pendingChanges.recordPendingChange(at: schedulingClock.now())
                pendingChangesByWorktreeId[ownedPath.worktreeId] = pendingChanges
                continue
            }

            var pendingChanges = pendingChangesByWorktreeId[ownedPath.worktreeId] ?? PendingWorktreeChanges()
            switch root.pathFilter.classify(relativePath: ownedPath.relativePath) {
            case .projected:
                pendingChanges.projectedPaths.insert(ownedPath.relativePath)
            case .gitInternal:
                pendingChanges.containsGitInternalChanges = true
                pendingChanges.suppressedGitInternalPathCount += 1
            case .ignoredByPolicy:
                pendingChanges.suppressedIgnoredPathCount += 1
            }
            pendingChanges.recordPendingChange(at: schedulingClock.now())
            pendingChangesByWorktreeId[ownedPath.worktreeId] = pendingChanges
        }

        scheduleDrainIfNeeded()
        await recordLogicalDebtSnapshotIfChanged()
    }

    func startIngressTaskIfNeeded() {
        guard ingressTask == nil else { return }
        let stream = fseventStreamClient.events()
        ingressTask = Task { [weak self] in
            for await batch in stream {
                guard !Task.isCancelled else { break }
                guard let self else { break }
                if await self.isWatchedFolderBatch(batch.worktreeId) {
                    await self.handleWatchedFolderFSEvent(batch)
                } else {
                    await self.enqueueRawPaths(worktreeId: batch.worktreeId, paths: batch.paths)
                }
            }
        }
    }

    private func scheduleDrainIfNeeded() {
        guard drainTask == nil else { return }
        guard hasPendingPaths else { return }

        drainTask = Task { [weak self] in
            guard let self else { return }
            await self.drainPendingChanges()
            await self.recordLogicalDebtSnapshotIfChanged()
        }
    }

    private func drainPendingChanges() async {
        defer {
            drainTask = nil
            if hasPendingPaths {
                scheduleDrainIfNeeded()
            }
        }

        while !Task.isCancelled {
            let now = schedulingClock.now()
            if let worktreeId = nextWorktreeToFlush(now: now) {
                await flush(worktreeId: worktreeId)
                continue
            }

            guard hasPendingPaths else {
                return
            }

            guard let nextDeadline = nextFlushDeadline(now: now) else {
                await Task.yield()
                continue
            }

            let sleepDuration = nextDeadline - now
            if sleepDuration > .zero {
                do {
                    try await schedulingClock.sleep(sleepDuration)
                } catch is CancellationError {
                    return
                } catch {
                    Self.logger.warning(
                        "Unexpected filesystem drain sleep failure: \(String(describing: error), privacy: .public)"
                    )
                    continue
                }
                guard !Task.isCancelled else { return }
            } else {
                await Task.yield()
            }
        }
    }

    private var hasPendingPaths: Bool {
        pendingChangesByWorktreeId.values.contains(where: \.hasPendingChanges)
    }

    var pendingWorktreeLogicalDebtCount: Int {
        pendingChangesByWorktreeId.values.count(where: \.hasPendingChanges)
    }

    var drainTaskLogicalDebtCount: Int {
        drainTask == nil ? 0 : 1
    }

    nonisolated private static func isGitIgnoreReloadPath(rawPath: String, relativePath: String) -> Bool {
        if relativePath == ".gitignore" {
            return true
        }

        guard relativePath == "." else {
            return false
        }

        let normalizedRawPath =
            rawPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        return normalizedRawPath == ".gitignore" || normalizedRawPath.hasSuffix("/.gitignore")
    }

    private func nextWorktreeToFlush(now: Duration) -> UUID? {
        let candidates =
            pendingChangesByWorktreeId
            .compactMap { worktreeId, pendingChanges -> UUID? in
                guard pendingChanges.hasPendingChanges else { return nil }
                guard roots[worktreeId] != nil else { return nil }
                guard isFlushDue(pendingChanges, now: now) else { return nil }
                return worktreeId
            }

        return candidates.min { lhs, rhs in
            let lhsPriority = priorityKey(for: lhs)
            let rhsPriority = priorityKey(for: rhs)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }

            let lhsRoot = roots[lhs]?.canonicalRootPath ?? ""
            let rhsRoot = roots[rhs]?.canonicalRootPath ?? ""
            if lhsRoot != rhsRoot {
                return lhsRoot < rhsRoot
            }
            return lhs.uuidString < rhs.uuidString
        }
    }

    private func nextFlushDeadline(now: Duration) -> Duration? {
        pendingChangesByWorktreeId
            .compactMap { worktreeId, pendingChanges -> Duration? in
                guard pendingChanges.hasPendingChanges else { return nil }
                guard roots[worktreeId] != nil else { return nil }
                guard let deadline = flushDeadline(for: pendingChanges) else { return nil }
                return deadline > now ? deadline : now
            }
            .min()
    }

    private func priorityKey(for worktreeId: UUID) -> Int {
        guard let root = roots[worktreeId] else { return Int.max }
        if root.isActiveInApp {
            if activePaneWorktreeId == worktreeId {
                return 0
            }
            return 1
        }
        return 2
    }

    private func isFlushDue(_ pendingChanges: PendingWorktreeChanges, now: Duration) -> Bool {
        guard let firstPendingTimestamp = pendingChanges.firstPendingTimestamp,
            let lastPendingTimestamp = pendingChanges.lastPendingTimestamp
        else {
            return true
        }

        let debounceDeadline = lastPendingTimestamp + debounceWindow
        let maxLatencyDeadline = firstPendingTimestamp + maxFlushLatency
        return now >= debounceDeadline || now >= maxLatencyDeadline
    }

    private func flushDeadline(for pendingChanges: PendingWorktreeChanges) -> Duration? {
        guard let firstPendingTimestamp = pendingChanges.firstPendingTimestamp,
            let lastPendingTimestamp = pendingChanges.lastPendingTimestamp
        else {
            return nil
        }
        let debounceDeadline = lastPendingTimestamp + debounceWindow
        let maxLatencyDeadline = firstPendingTimestamp + maxFlushLatency
        return min(debounceDeadline, maxLatencyDeadline)
    }

    private func flush(worktreeId: UUID) async {
        guard var root = roots[worktreeId] else {
            pendingChangesByWorktreeId.removeValue(forKey: worktreeId)
            return
        }
        guard let pendingChanges = pendingChangesByWorktreeId[worktreeId], pendingChanges.hasPendingChanges else {
            return
        }

        pendingChangesByWorktreeId[worktreeId] = PendingWorktreeChanges()

        let orderedPaths = pendingChanges.projectedPaths.sorted()
        let pathChunks =
            orderedPaths.isEmpty
            ? [[]]
            : Self.chunkPaths(
                orderedPaths,
                maxChunkSize: Self.maxPathsPerFilesChangedEvent
            )
        for pathChunk in pathChunks {
            root.nextBatchSeq += 1
            let batchSeq = root.nextBatchSeq
            let timestamp = envelopeClock.now
            let changeset = FileChangeset(
                worktreeId: worktreeId,
                repoId: root.repoId,
                rootPath: root.rootPath,
                paths: pathChunk,
                containsGitInternalChanges: pendingChanges.containsGitInternalChanges,
                suppressedIgnoredPathCount: pendingChanges.suppressedIgnoredPathCount,
                suppressedGitInternalPathCount: pendingChanges.suppressedGitInternalPathCount,
                timestamp: timestamp,
                batchSeq: batchSeq
            )

            await emitFilesystemEvent(
                worktreeId: worktreeId,
                repoId: root.repoId,
                timestamp: timestamp,
                rootPathHint: root.rootPath,
                event: .filesChanged(changeset: changeset)
            )
        }
        roots[worktreeId] = root
    }

    nonisolated private static func chunkPaths(
        _ paths: [String],
        maxChunkSize: Int
    ) -> [[String]] {
        guard !paths.isEmpty else { return [] }
        guard maxChunkSize > 0 else { return [paths] }

        var chunks: [[String]] = []
        chunks.reserveCapacity((paths.count + maxChunkSize - 1) / maxChunkSize)

        var index = 0
        while index < paths.count {
            let upperBound = min(index + maxChunkSize, paths.count)
            chunks.append(Array(paths[index..<upperBound]))
            index = upperBound
        }

        return chunks
    }

    private func emitFilesystemEvent(
        worktreeId: UUID,
        repoId: UUID,
        timestamp: ContinuousClock.Instant,
        rootPathHint: URL? = nil,
        event: FilesystemEvent
    ) async {
        nextEnvelopeSequence += 1
        let runtimeEnvelope: RuntimeEnvelope
        switch event {
        case .worktreeRegistered(let registeredWorktreeId, let registeredRepoId, let rootPath):
            runtimeEnvelope = .system(
                SystemEnvelope(
                    source: .builtin(.filesystemWatcher),
                    seq: nextEnvelopeSequence,
                    timestamp: timestamp,
                    event: .topology(
                        .worktreeRegistered(
                            worktreeId: registeredWorktreeId,
                            repoId: registeredRepoId,
                            rootPath: rootPath
                        )
                    )
                )
            )
        case .worktreeUnregistered(let unregisteredWorktreeId, let unregisteredRepoId):
            runtimeEnvelope = .system(
                SystemEnvelope(
                    source: .builtin(.filesystemWatcher),
                    seq: nextEnvelopeSequence,
                    timestamp: timestamp,
                    event: .topology(
                        .worktreeUnregistered(
                            worktreeId: unregisteredWorktreeId,
                            repoId: unregisteredRepoId
                        )
                    )
                )
            )
        case .filesChanged:
            runtimeEnvelope = .worktree(
                WorktreeEnvelope(
                    source: .system(.builtin(.filesystemWatcher)),
                    seq: nextEnvelopeSequence,
                    timestamp: timestamp,
                    repoId: repoId,
                    worktreeId: worktreeId,
                    event: .filesystem(event)
                )
            )
        case .gitSnapshotChanged, .diffAvailable, .branchChanged:
            runtimeEnvelope = .worktree(
                WorktreeEnvelope(
                    source: .system(.builtin(.filesystemWatcher)),
                    seq: nextEnvelopeSequence,
                    timestamp: timestamp,
                    repoId: repoId,
                    worktreeId: worktreeId,
                    event: .gitWorkingDirectory(gitWorkingDirectoryEvent(from: event))
                )
            )
        }

        let droppedCount = (await runtimeBus.post(runtimeEnvelope)).droppedCount
        if droppedCount > 0 {
            Self.logger.warning(
                "Filesystem event delivery dropped for \(droppedCount, privacy: .public) subscriber(s); seq=\(self.nextEnvelopeSequence, privacy: .public)"
            )
        }
        Self.logger.debug(
            """
            Posted filesystem event for worktree \(worktreeId.uuidString, privacy: .public); \
            event=\(String(describing: event), privacy: .public)
            """
        )
        _ = rootPathHint
    }

    // MARK: - Watched Folder Scanning

    private func emitRepoDiscovered(
        repoPath: URL,
        parentPath: URL,
        linkedWorktrees: LinkedWorktreeInfo = .notScanned
    ) async {
        nextEnvelopeSequence += 1
        let envelope = RuntimeEnvelope.system(
            SystemEnvelope(
                source: .builtin(.filesystemWatcher),
                seq: nextEnvelopeSequence,
                timestamp: envelopeClock.now,
                event: .topology(
                    .repoDiscovered(
                        repoPath: repoPath,
                        parentPath: parentPath,
                        linkedWorktrees: linkedWorktrees
                    )
                )
            )
        )
        let droppedCount = (await runtimeBus.post(envelope)).droppedCount
        if droppedCount > 0 {
            Self.logger.warning(
                "Repo discovered event delivery dropped for \(droppedCount, privacy: .public) subscriber(s); repoPath=\(repoPath.path, privacy: .public)"
            )
        }
    }

    func emitReposDiscovered(
        parentPath: URL,
        repositories: [DiscoveredRepoTopologyInfo]
    ) async {
        guard !repositories.isEmpty else { return }
        nextEnvelopeSequence += 1
        let envelope = RuntimeEnvelope.system(
            SystemEnvelope(
                source: .builtin(.filesystemWatcher),
                seq: nextEnvelopeSequence,
                timestamp: envelopeClock.now,
                event: .topology(
                    .reposDiscovered(
                        parentPath: parentPath,
                        repositories: repositories
                    )
                )
            )
        )
        let droppedCount = (await runtimeBus.post(envelope)).droppedCount
        if droppedCount > 0 {
            Self.logger.warning(
                "Repos discovered event delivery dropped for \(droppedCount, privacy: .public) subscriber(s); parentPath=\(parentPath.path, privacy: .public)"
            )
        }
    }

    func emitRemovedClones(noLongerReferencedByAnyWatchedFolder clonePaths: Set<URL>) async {
        for repoPath in clonePaths.sorted(by: Self.sortByPath) {
            guard !isReferencedByAnyWatchedFolder(repoPath) else { continue }
            await emitRepoRemoved(repoPath: repoPath)
        }
    }

    private func emitRepoRemoved(repoPath: URL) async {
        nextEnvelopeSequence += 1
        let envelope = RuntimeEnvelope.system(
            SystemEnvelope(
                source: .builtin(.filesystemWatcher),
                seq: nextEnvelopeSequence,
                timestamp: envelopeClock.now,
                event: .topology(.repoRemoved(repoPath: repoPath))
            )
        )
        let droppedCount = (await runtimeBus.post(envelope)).droppedCount
        if droppedCount > 0 {
            Self.logger.warning(
                "Repo removed event delivery dropped for \(droppedCount, privacy: .public) subscriber(s); repoPath=\(repoPath.path, privacy: .public)"
            )
        }
    }

    func isReferencedByAnyWatchedFolder(_ repoPath: URL) -> Bool {
        watchedFolderScanState.inventoryBySourceID.values.contains { inventory in
            inventory.repoGroups.contains { $0.clonePath == repoPath }
        }
    }

    static func normalizeRepoScanGroups(
        _ groups: [RepoScanner.RepoScanGroup]
    ) -> [RepoScanner.RepoScanGroup] {
        groups
            .map { group in
                RepoScanner.RepoScanGroup(
                    clonePath: group.clonePath.standardizedFileURL,
                    linkedWorktreePaths: group.linkedWorktreePaths
                        .map(\.standardizedFileURL)
                        .sorted(by: Self.sortByPath)
                )
            }
            .sorted(by: Self.sortByClonePath)
    }

    static func sortByClonePath(
        _ lhs: RepoScanner.RepoScanGroup,
        _ rhs: RepoScanner.RepoScanGroup
    ) -> Bool {
        sortByPath(lhs.clonePath, rhs.clonePath)
    }

    static func sortByPath(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
    }

    private static func sortWorktreeIds(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }

    // MARK: - Git Event Projection

    private func gitWorkingDirectoryEvent(from event: FilesystemEvent) -> GitWorkingDirectoryEvent {
        switch event {
        case .gitSnapshotChanged(let snapshot):
            return .snapshotChanged(snapshot: snapshot)
        case .branchChanged(let worktreeId, let repoId, let from, let to):
            return .branchChanged(worktreeId: worktreeId, repoId: repoId, from: from, to: to)
        case .diffAvailable(let diffId, let worktreeId, let repoId):
            return .diffAvailable(diffId: diffId, worktreeId: worktreeId, repoId: repoId)
        case .worktreeRegistered, .worktreeUnregistered, .filesChanged:
            preconditionFailure("Unsupported filesystem event for git working directory projection")
        }
    }
}
