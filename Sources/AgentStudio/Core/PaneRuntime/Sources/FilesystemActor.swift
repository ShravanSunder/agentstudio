import Foundation
import os

/// App-wide filesystem ingress actor keyed by worktree registration.
///
/// The actor owns filesystem path ingestion, deepest-root ownership routing for nested roots,
/// priority-aware flush ordering, and envelope emission onto `EventBus`.
actor FilesystemActor {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "FilesystemActor")
    static let maxPathsPerFilesChangedEvent = 256

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
        var requiresPathFilterReload = false
        var firstPendingTimestamp: ContinuousClock.Instant?
        var lastPendingTimestamp: ContinuousClock.Instant?

        var hasPendingChanges: Bool {
            !projectedPaths.isEmpty || suppressedIgnoredPathCount > 0 || suppressedGitInternalPathCount > 0
        }

        mutating func recordPendingChange(at timestamp: ContinuousClock.Instant) {
            if firstPendingTimestamp == nil {
                firstPendingTimestamp = timestamp
            }
            lastPendingTimestamp = timestamp
        }
    }

    private let runtimeBus: EventBus<RuntimeEnvelope>?
    private let legacyBus: EventBus<PaneEventEnvelope>?
    private let fseventStreamClient: any FSEventStreamClient
    private let envelopeClock = ContinuousClock()
    private let sleepClock: any Clock<Duration>
    private let debounceWindow: Duration
    private let maxFlushLatency: Duration

    private var roots: [UUID: RootState] = [:]
    private var pendingChangesByWorktreeId: [UUID: PendingWorktreeChanges] = [:]
    private var activePaneWorktreeId: UUID?
    private var nextEnvelopeSequence: UInt64 = 0

    private var ingressTask: Task<Void, Never>?
    private var drainTask: Task<Void, Never>?
    private var hasShutdown = false

    init(
        bus: EventBus<RuntimeEnvelope> = PaneRuntimeEventBus.shared,
        fseventStreamClient: any FSEventStreamClient = NoopFSEventStreamClient(),
        sleepClock: any Clock<Duration> = ContinuousClock(),
        debounceWindow: Duration = .milliseconds(500),
        maxFlushLatency: Duration = .seconds(2)
    ) {
        self.runtimeBus = bus
        self.legacyBus = nil
        self.fseventStreamClient = fseventStreamClient
        self.sleepClock = sleepClock
        self.debounceWindow = debounceWindow
        self.maxFlushLatency = maxFlushLatency
        if fseventStreamClient is NoopFSEventStreamClient {
            Self.logger.warning(
                """
                FilesystemActor initialized with NoopFSEventStreamClient; OS filesystem events are disabled. \
                TODO(LUNA-349): wire concrete FSEventStreamClient in production composition root.
                """
            )
        }
    }

    init(
        bus: EventBus<PaneEventEnvelope>,
        fseventStreamClient: any FSEventStreamClient = NoopFSEventStreamClient(),
        sleepClock: any Clock<Duration> = ContinuousClock(),
        debounceWindow: Duration = .milliseconds(500),
        maxFlushLatency: Duration = .seconds(2)
    ) {
        self.runtimeBus = nil
        self.legacyBus = bus
        self.fseventStreamClient = fseventStreamClient
        self.sleepClock = sleepClock
        self.debounceWindow = debounceWindow
        self.maxFlushLatency = maxFlushLatency
        if fseventStreamClient is NoopFSEventStreamClient {
            Self.logger.warning(
                """
                FilesystemActor initialized with NoopFSEventStreamClient; OS filesystem events are disabled. \
                TODO(LUNA-349): wire concrete FSEventStreamClient in production composition root.
                """
            )
        }
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
        await fseventStreamClient.register(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)
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
        await fseventStreamClient.unregister(worktreeId: worktreeId)
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

        ingressTask?.cancel()
        ingressTask = nil
        drainTask?.cancel()
        drainTask = nil

        if let activeIngressTask {
            await activeIngressTask.value
        }
        if let activeDrainTask {
            await activeDrainTask.value
        }

        roots.removeAll(keepingCapacity: false)
        pendingChangesByWorktreeId.removeAll(keepingCapacity: false)
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

            guard let root = roots[ownedPath.worktreeId] else { continue }

            var pendingChanges = pendingChangesByWorktreeId[ownedPath.worktreeId] ?? PendingWorktreeChanges()
            switch root.pathFilter.classify(relativePath: ownedPath.relativePath) {
            case .projected:
                pendingChanges.projectedPaths.insert(ownedPath.relativePath)
                if ownedPath.relativePath == ".gitignore" {
                    pendingChanges.requiresPathFilterReload = true
                }
            case .gitInternal:
                pendingChanges.containsGitInternalChanges = true
                pendingChanges.suppressedGitInternalPathCount += 1
            case .ignoredByPolicy:
                pendingChanges.suppressedIgnoredPathCount += 1
            }
            pendingChanges.recordPendingChange(at: envelopeClock.now)
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
                await self?.enqueueRawPaths(worktreeId: batch.worktreeId, paths: batch.paths)
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
            let now = envelopeClock.now
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

            let sleepDuration = now.duration(to: nextDeadline)
            if sleepDuration > .zero {
                do {
                    try await sleepClock.sleep(for: sleepDuration)
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

    private func nextWorktreeToFlush(now: ContinuousClock.Instant) -> UUID? {
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

    private func nextFlushDeadline(now: ContinuousClock.Instant) -> ContinuousClock.Instant? {
        pendingChangesByWorktreeId
            .compactMap { worktreeId, pendingChanges -> ContinuousClock.Instant? in
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

    private func isFlushDue(_ pendingChanges: PendingWorktreeChanges, now: ContinuousClock.Instant) -> Bool {
        guard let firstPendingTimestamp = pendingChanges.firstPendingTimestamp,
            let lastPendingTimestamp = pendingChanges.lastPendingTimestamp
        else {
            return true
        }

        let debounceDeadline = lastPendingTimestamp.advanced(by: debounceWindow)
        let maxLatencyDeadline = firstPendingTimestamp.advanced(by: maxFlushLatency)
        return now >= debounceDeadline || now >= maxLatencyDeadline
    }

    private func flushDeadline(for pendingChanges: PendingWorktreeChanges) -> ContinuousClock.Instant? {
        guard let firstPendingTimestamp = pendingChanges.firstPendingTimestamp,
            let lastPendingTimestamp = pendingChanges.lastPendingTimestamp
        else {
            return nil
        }
        let debounceDeadline = lastPendingTimestamp.advanced(by: debounceWindow)
        let maxLatencyDeadline = firstPendingTimestamp.advanced(by: maxFlushLatency)
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

        if pendingChanges.requiresPathFilterReload {
            root.pathFilter = FilesystemPathFilter.load(forRootPath: root.rootPath)
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
        // Task 2 compatibility-only bridge: keep legacy payloads, expose explicit
        // old -> new namespace mapping for future RuntimeEnvelope bus migration.
        let compatibilityScope = event.compatibilityScope
        nextEnvelopeSequence += 1
        let envelope = PaneEventEnvelope(
            source: .system(.builtin(.filesystemWatcher)),
            sourceFacets: PaneContextFacets(repoId: repoId, worktreeId: worktreeId, cwd: rootPathHint),
            paneKind: nil,
            seq: nextEnvelopeSequence,
            commandId: nil,
            correlationId: nil,
            timestamp: timestamp,
            epoch: 0,
            event: .filesystem(event)
        )
        let runtimeEnvelope = RuntimeEnvelope.fromLegacy(envelope)
        let droppedCount: Int
        if let runtimeBus {
            droppedCount = (await runtimeBus.post(runtimeEnvelope)).droppedCount
        } else if let legacyBus, let legacyEnvelope = runtimeEnvelope.toLegacy() {
            droppedCount = (await legacyBus.post(legacyEnvelope)).droppedCount
        } else {
            Self.logger.warning(
                """
                Filesystem event dropped after runtime-envelope adaptation; \
                event=\(String(describing: event), privacy: .public)
                """
            )
            droppedCount = 0
        }
        if droppedCount > 0 {
            Self.logger.warning(
                "Filesystem event delivery dropped for \(droppedCount, privacy: .public) subscriber(s); seq=\(self.nextEnvelopeSequence, privacy: .public)"
            )
        }
        Self.logger.debug(
            """
            Posted filesystem event for worktree \(worktreeId.uuidString, privacy: .public); \
            scope=\(compatibilityScope.description, privacy: .public)
            """
        )
    }
}
