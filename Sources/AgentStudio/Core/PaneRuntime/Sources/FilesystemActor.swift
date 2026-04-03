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
            make(clock: ContinuousClock())
        }

        static func make<C: Clock>(clock: C) -> Self where C.Duration == Duration, C: Sendable {
            let origin = clock.now
            return Self(
                now: { origin.duration(to: clock.now) },
                sleep: { duration in
                    try await clock.sleep(for: duration)
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
            !projectedPaths.isEmpty || suppressedIgnoredPathCount > 0 || suppressedGitInternalPathCount > 0
        }

        mutating func recordPendingChange(at timestamp: Duration) {
            if firstPendingTimestamp == nil {
                firstPendingTimestamp = timestamp
            }
            lastPendingTimestamp = timestamp
        }
    }

    private let runtimeBus: EventBus<RuntimeEnvelope>
    private let fseventStreamClient: any FSEventStreamClient
    private let envelopeClock = ContinuousClock()
    private let schedulingClock: SchedulingClock
    private let groupedWatchedFolderScanner: @Sendable (URL) -> [RepoScanner.RepoScanGroup]
    private let debounceWindow: Duration
    private let maxFlushLatency: Duration

    private var roots: [UUID: RootState] = [:]
    private var pendingChangesByWorktreeId: [UUID: PendingWorktreeChanges] = [:]
    private var activePaneWorktreeId: UUID?
    private var nextEnvelopeSequence: UInt64 = 0

    private var watchedFolderIds: [URL: UUID] = [:]
    private var watchedFolderRepoGroupsByRoot: [URL: [RepoScanner.RepoScanGroup]] = [:]
    private var fallbackRescanTask: Task<Void, Never>?

    private var ingressTask: Task<Void, Never>?
    private var drainTask: Task<Void, Never>?
    private var hasShutdown = false

    init(
        bus: EventBus<RuntimeEnvelope> = PaneRuntimeEventBus.shared,
        fseventStreamClient: any FSEventStreamClient = DarwinFSEventStreamClient(),
        groupedWatchedFolderScanner: @escaping @Sendable (URL) -> [RepoScanner.RepoScanGroup] = {
            RepoScanner().scanForGitReposGrouped(in: $0)
        },
        debounceWindow: Duration = .milliseconds(500),
        maxFlushLatency: Duration = .seconds(2)
    ) {
        self.runtimeBus = bus
        self.fseventStreamClient = fseventStreamClient
        self.groupedWatchedFolderScanner = groupedWatchedFolderScanner
        schedulingClock = .continuous()
        self.debounceWindow = debounceWindow
        self.maxFlushLatency = maxFlushLatency
    }

    init<C: Clock>(
        bus: EventBus<RuntimeEnvelope> = PaneRuntimeEventBus.shared,
        fseventStreamClient: any FSEventStreamClient = DarwinFSEventStreamClient(),
        groupedWatchedFolderScanner: @escaping @Sendable (URL) -> [RepoScanner.RepoScanGroup] = {
            RepoScanner().scanForGitReposGrouped(in: $0)
        },
        sleepClock: C,
        debounceWindow: Duration = .milliseconds(500),
        maxFlushLatency: Duration = .seconds(2)
    ) where C.Duration == Duration, C: Sendable {
        self.runtimeBus = bus
        self.fseventStreamClient = fseventStreamClient
        self.groupedWatchedFolderScanner = groupedWatchedFolderScanner
        schedulingClock = .make(clock: sleepClock)
        self.debounceWindow = debounceWindow
        self.maxFlushLatency = maxFlushLatency
    }

    isolated deinit {
        ingressTask?.cancel()
        drainTask?.cancel()
        if !hasShutdown {
            Self.logger.warning("FilesystemActor deinitialized without explicit shutdown()")
        }
    }

    func register(worktreeId: UUID, repoId: UUID, rootPath: URL) async {
        startIngressTaskIfNeeded()

        let canonicalRootPath = FilesystemRootOwnership.canonicalRootPath(for: rootPath)

        let existing = roots[worktreeId]
        roots[worktreeId] = RootState(
            repoId: repoId,
            rootPath: rootPath,
            canonicalRootPath: canonicalRootPath,
            isActiveInApp: existing?.isActiveInApp ?? false,
            nextBatchSeq: existing?.nextBatchSeq ?? 0,
            pathFilter: FilesystemPathFilter.load(forRootPath: rootPath)
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

    /// Test seam for deterministic ingress without OS-level FSEvents.
    func enqueueRawPaths(worktreeId: UUID, paths: [String]) {
        ingestRawPaths(worktreeId: worktreeId, paths: paths)
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
        let activeIngressTask = ingressTask
        let activeDrainTask = drainTask
        let activeFallbackTask = fallbackRescanTask

        ingressTask?.cancel()
        ingressTask = nil
        drainTask?.cancel()
        drainTask = nil
        fallbackRescanTask?.cancel()
        fallbackRescanTask = nil

        if let activeIngressTask {
            await activeIngressTask.value
        }
        if let activeDrainTask {
            await activeDrainTask.value
        }
        if let activeFallbackTask {
            await activeFallbackTask.value
        }

        roots.removeAll(keepingCapacity: false)
        pendingChangesByWorktreeId.removeAll(keepingCapacity: false)
        watchedFolderIds.removeAll(keepingCapacity: false)
        watchedFolderRepoGroupsByRoot.removeAll(keepingCapacity: false)
        activePaneWorktreeId = nil
        fseventStreamClient.shutdown()
        hasShutdown = true
    }

    private func ingestRawPaths(worktreeId: UUID, paths: [String]) {
        guard roots[worktreeId] != nil else {
            Self.logger.debug(
                "Dropped filesystem path batch for unregistered worktree \(worktreeId.uuidString, privacy: .public)"
            )
            return
        }
        guard !paths.isEmpty else { return }

        let ownership = FilesystemRootOwnership(
            rootsByWorktree: roots.mapValues(\.rootPath)
        )

        for rawPath in paths {
            guard let ownedPath = ownership.route(sourceWorktreeId: worktreeId, rawPath: rawPath) else {
                Self.logger.debug(
                    "Dropped unroutable filesystem path for source worktree \(worktreeId.uuidString, privacy: .public): \(rawPath, privacy: .public)"
                )
                continue
            }

            guard var root = roots[ownedPath.worktreeId] else { continue }

            var pendingChanges = pendingChangesByWorktreeId[ownedPath.worktreeId] ?? PendingWorktreeChanges()
            if Self.isGitIgnoreReloadPath(rawPath: rawPath, relativePath: ownedPath.relativePath) {
                root.pathFilter = FilesystemPathFilter.load(forRootPath: root.rootPath)
                roots[ownedPath.worktreeId] = root
                pendingChanges.recordPendingChange(at: schedulingClock.now())
                pendingChangesByWorktreeId[ownedPath.worktreeId] = pendingChanges
                continue
            }

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
    }

    private func startIngressTaskIfNeeded() {
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
            await self?.drainPendingChanges()
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

    func updateWatchedFolders(_ paths: [URL]) async {
        _ = await refreshWatchedFolders(paths)
    }

    func refreshWatchedFolders(_ paths: [URL]) async -> WatchedFolderRefreshSummary {
        startIngressTaskIfNeeded()

        let newPaths = Set(paths.map { $0.standardizedFileURL })
        let oldPaths = Set(watchedFolderIds.keys)
        var removedClonePaths = Set<URL>()

        for removed in oldPaths.subtracting(newPaths) {
            if let syntheticId = watchedFolderIds.removeValue(forKey: removed) {
                fseventStreamClient.unregister(worktreeId: syntheticId)
            }
            if let removedGroups = watchedFolderRepoGroupsByRoot.removeValue(forKey: removed) {
                removedClonePaths.formUnion(removedGroups.map(\.clonePath))
            }
        }

        for added in newPaths.subtracting(oldPaths) {
            let syntheticId = UUID()
            watchedFolderIds[added] = syntheticId
            fseventStreamClient.register(worktreeId: syntheticId, repoId: syntheticId, rootPath: added)
        }

        let rescanResult = await rescanAllWatchedFolders()
        removedClonePaths.formUnion(rescanResult.removedClonePaths)
        await emitRemovedClones(noLongerReferencedByAnyWatchedFolder: removedClonePaths)
        startFallbackRescan()
        return rescanResult.summary
    }

    private func isWatchedFolderBatch(_ worktreeId: UUID) -> Bool {
        watchedFolderIds.values.contains(worktreeId)
    }

    private func handleWatchedFolderFSEvent(_ batch: FSEventBatch) async {
        let hasGitChange = batch.paths.contains { path in
            path.contains("/.git/") || path.hasSuffix("/.git")
        }
        guard hasGitChange else { return }

        guard let folderPath = watchedFolderIds.first(where: { $0.value == batch.worktreeId })?.key else {
            return
        }

        let result = await refreshWatchedFolder(folderPath)
        await emitRemovedClones(noLongerReferencedByAnyWatchedFolder: result.removedClonePaths)
    }

    /// Blocking filesystem scan — MUST run off the actor's executor.
    /// Under SE-0461, plain nonisolated async inherits actor isolation.
    /// @concurrent ensures this escapes to the global executor.
    @concurrent nonisolated private static func scanFolder(
        _ folderPath: URL,
        using watchedFolderScanner: @escaping @Sendable (URL) -> [RepoScanner.RepoScanGroup]
    ) async -> [RepoScanner.RepoScanGroup] {
        watchedFolderScanner(folderPath)
    }

    private struct WatchedFolderRefreshScanResult {
        let summary: WatchedFolderRefreshSummary
        let removedClonePaths: Set<URL>
    }

    private func rescanAllWatchedFolders() async -> WatchedFolderRefreshScanResult {
        var removedClonePaths = Set<URL>()
        var repoPathsByWatchedFolder: [URL: [URL]] = [:]
        for (folderPath, _) in watchedFolderIds {
            let refreshResult = await refreshWatchedFolder(folderPath)
            repoPathsByWatchedFolder[folderPath] = refreshResult.repoPaths
            removedClonePaths.formUnion(refreshResult.removedClonePaths)
        }
        return WatchedFolderRefreshScanResult(
            summary: WatchedFolderRefreshSummary(repoPathsByWatchedFolder: repoPathsByWatchedFolder),
            removedClonePaths: removedClonePaths
        )
    }

    private struct WatchedFolderRefreshResult {
        let repoPaths: [URL]
        let removedClonePaths: Set<URL>
    }

    private func refreshWatchedFolder(_ folderPath: URL) async -> WatchedFolderRefreshResult {
        let currentRepoGroups = Self.normalizeRepoScanGroups(
            await Self.scanFolder(folderPath, using: groupedWatchedFolderScanner)
        )
        let previousRepoGroups = watchedFolderRepoGroupsByRoot[folderPath, default: []]
        let currentRepoGroupsByClonePath: [URL: RepoScanner.RepoScanGroup] = Dictionary(
            uniqueKeysWithValues: currentRepoGroups.map { ($0.clonePath, $0) }
        )
        let previousRepoGroupsByClonePath: [URL: RepoScanner.RepoScanGroup] = Dictionary(
            uniqueKeysWithValues: previousRepoGroups.map { ($0.clonePath, $0) }
        )

        let currentClonePaths = Set(currentRepoGroupsByClonePath.keys)
        let previousClonePaths = Set(previousRepoGroupsByClonePath.keys)

        let addedRepoPaths = currentClonePaths.subtracting(previousClonePaths)
            .sorted(by: Self.sortByPath)
        let changedRepoPaths = currentClonePaths.intersection(previousClonePaths)
            .sorted(by: Self.sortByPath)
        let removedClonePaths = previousClonePaths.subtracting(currentClonePaths)

        watchedFolderRepoGroupsByRoot[folderPath] = currentRepoGroups

        for repoPath in addedRepoPaths {
            guard let group = currentRepoGroupsByClonePath[repoPath] else { continue }
            await emitRepoDiscovered(
                repoPath: repoPath,
                parentPath: folderPath,
                linkedWorktrees: .scanned(group.linkedWorktreePaths)
            )
        }

        for repoPath in changedRepoPaths {
            guard let currentGroup = currentRepoGroupsByClonePath[repoPath],
                let previousGroup = previousRepoGroupsByClonePath[repoPath]
            else {
                continue
            }
            guard currentGroup.linkedWorktreePaths != previousGroup.linkedWorktreePaths else { continue }
            await emitRepoDiscovered(
                repoPath: repoPath,
                parentPath: folderPath,
                linkedWorktrees: .scanned(currentGroup.linkedWorktreePaths)
            )
        }

        return WatchedFolderRefreshResult(
            repoPaths: currentRepoGroups.map(\.clonePath).sorted(by: Self.sortByPath),
            removedClonePaths: removedClonePaths
        )
    }

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

    private func emitRemovedClones(noLongerReferencedByAnyWatchedFolder clonePaths: Set<URL>) async {
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

    private func isReferencedByAnyWatchedFolder(_ repoPath: URL) -> Bool {
        watchedFolderRepoGroupsByRoot.values.contains { repoGroups in
            repoGroups.contains { $0.clonePath == repoPath }
        }
    }

    private static func normalizeRepoScanGroups(
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

    private static func sortByClonePath(
        _ lhs: RepoScanner.RepoScanGroup,
        _ rhs: RepoScanner.RepoScanGroup
    ) -> Bool {
        sortByPath(lhs.clonePath, rhs.clonePath)
    }

    private static func sortByPath(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
    }

    private func startFallbackRescan() {
        fallbackRescanTask?.cancel()
        guard !watchedFolderIds.isEmpty else { return }
        fallbackRescanTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await self.schedulingClock.sleep(.seconds(300))
                guard !Task.isCancelled else { break }
                let rescanResult = await self.rescanAllWatchedFolders()
                await self.emitRemovedClones(
                    noLongerReferencedByAnyWatchedFolder: rescanResult.removedClonePaths
                )
            }
        }
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
