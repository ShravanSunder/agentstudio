import Foundation
import os

/// App-wide filesystem ingress actor keyed by worktree registration.
///
/// The actor owns filesystem path ingestion, deepest-root ownership routing for nested roots,
/// priority-aware flush ordering, and envelope emission onto `EventBus`.
actor FilesystemActor {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "FilesystemActor")
    static let maxPathsPerFilesChangedEvent = 256
    static let shared = FilesystemActor()

    private struct RootState: Sendable {
        let rootPath: URL
        let canonicalRootPath: String
        var isActiveInApp: Bool
        var nextBatchSeq: UInt64
        var lastKnownBranch: String?
    }

    private let bus: EventBus<PaneEventEnvelope>
    private let gitStatusProvider: any GitStatusProvider
    private let fseventStreamClient: any FSEventStreamClient
    private let envelopeClock = ContinuousClock()

    private var roots: [UUID: RootState] = [:]
    private var pendingRelativePathsByWorktreeId: [UUID: Set<String>] = [:]
    private var activePaneWorktreeId: UUID?
    private var nextEnvelopeSequence: UInt64 = 0

    private var ingressTask: Task<Void, Never>?
    private var drainTask: Task<Void, Never>?

    init(
        bus: EventBus<PaneEventEnvelope> = PaneRuntimeEventBus.shared,
        clock _: any Clock<Duration> = ContinuousClock(),
        gitStatusProvider: any GitStatusProvider = ShellGitStatusProvider(),
        fseventStreamClient: any FSEventStreamClient = NoopFSEventStreamClient()
    ) {
        self.bus = bus
        self.gitStatusProvider = gitStatusProvider
        self.fseventStreamClient = fseventStreamClient
    }

    isolated deinit {
        ingressTask?.cancel()
        drainTask?.cancel()
        Task { [fseventStreamClient] in
            await fseventStreamClient.shutdown()
        }
    }

    func register(worktreeId: UUID, rootPath: URL) async {
        startIngressTaskIfNeeded()

        let canonicalRootPath = FilesystemRootOwnership.canonicalRootPath(for: rootPath)

        let existing = roots[worktreeId]
        roots[worktreeId] = RootState(
            rootPath: rootPath,
            canonicalRootPath: canonicalRootPath,
            isActiveInApp: existing?.isActiveInApp ?? false,
            nextBatchSeq: existing?.nextBatchSeq ?? 0,
            lastKnownBranch: existing?.lastKnownBranch
        )
        pendingRelativePathsByWorktreeId[worktreeId] = pendingRelativePathsByWorktreeId[worktreeId] ?? []
        await fseventStreamClient.register(worktreeId: worktreeId, rootPath: rootPath)
    }

    func unregister(worktreeId: UUID) async {
        roots.removeValue(forKey: worktreeId)
        pendingRelativePathsByWorktreeId.removeValue(forKey: worktreeId)
        if activePaneWorktreeId == worktreeId {
            activePaneWorktreeId = nil
        }
        await fseventStreamClient.unregister(worktreeId: worktreeId)
    }

    /// Test seam for deterministic ingress without OS-level FSEvents.
    func enqueueRawPaths(worktreeId: UUID, paths: [String]) {
        ingestRawPaths(worktreeId: worktreeId, paths: paths)
    }

    func setActivity(worktreeId: UUID, isActiveInApp: Bool) {
        guard var root = roots[worktreeId] else { return }
        root.isActiveInApp = isActiveInApp
        roots[worktreeId] = root
    }

    func setActivePaneWorktree(worktreeId: UUID?) {
        activePaneWorktreeId = worktreeId
    }

    func shutdown() async {
        ingressTask?.cancel()
        ingressTask = nil
        drainTask?.cancel()
        drainTask = nil
        roots.removeAll(keepingCapacity: false)
        pendingRelativePathsByWorktreeId.removeAll(keepingCapacity: false)
        activePaneWorktreeId = nil
        await fseventStreamClient.shutdown()
    }

    private func ingestRawPaths(worktreeId: UUID, paths: [String]) {
        guard roots[worktreeId] != nil else { return }
        guard !paths.isEmpty else { return }

        let ownership = FilesystemRootOwnership(
            rootsByWorktree: roots.mapValues(\.rootPath)
        )

        for rawPath in paths {
            guard let ownedPath = ownership.route(sourceWorktreeId: worktreeId, rawPath: rawPath) else {
                continue
            }
            pendingRelativePathsByWorktreeId[ownedPath.worktreeId, default: []].insert(ownedPath.relativePath)
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
            await Task.yield()
            guard let worktreeId = nextWorktreeToFlush() else {
                return
            }
            await flush(worktreeId: worktreeId)
        }
    }

    private var hasPendingPaths: Bool {
        pendingRelativePathsByWorktreeId.values.contains(where: { !$0.isEmpty })
    }

    private func nextWorktreeToFlush() -> UUID? {
        let candidates =
            pendingRelativePathsByWorktreeId
            .compactMap { worktreeId, paths -> UUID? in
                guard !paths.isEmpty else { return nil }
                guard roots[worktreeId] != nil else { return nil }
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

    private func flush(worktreeId: UUID) async {
        guard var root = roots[worktreeId] else {
            pendingRelativePathsByWorktreeId.removeValue(forKey: worktreeId)
            return
        }
        guard let pendingPaths = pendingRelativePathsByWorktreeId[worktreeId], !pendingPaths.isEmpty else {
            return
        }

        pendingRelativePathsByWorktreeId[worktreeId] = []

        let orderedPaths = pendingPaths.sorted()
        let pathChunks = Self.chunkPaths(
            orderedPaths,
            maxChunkSize: Self.maxPathsPerFilesChangedEvent
        )
        for pathChunk in pathChunks {
            root.nextBatchSeq += 1
            let batchSeq = root.nextBatchSeq
            let timestamp = envelopeClock.now
            let changeset = FileChangeset(
                worktreeId: worktreeId,
                rootPath: root.rootPath,
                paths: pathChunk,
                timestamp: timestamp,
                batchSeq: batchSeq
            )

            await emitFilesystemEvent(
                worktreeId: worktreeId,
                timestamp: timestamp,
                event: .filesChanged(changeset: changeset)
            )
        }
        roots[worktreeId] = root

        guard let statusSnapshot = await gitStatusProvider.status(for: root.rootPath) else {
            return
        }
        guard var currentRoot = roots[worktreeId] else {
            return
        }

        await emitFilesystemEvent(
            worktreeId: worktreeId,
            timestamp: envelopeClock.now,
            event: .gitSnapshotChanged(
                snapshot: GitWorkingTreeSnapshot(
                    worktreeId: worktreeId,
                    rootPath: root.rootPath,
                    summary: statusSnapshot.summary,
                    branch: statusSnapshot.branch
                )
            )
        )

        if let previousBranch = currentRoot.lastKnownBranch,
            let nextBranch = statusSnapshot.branch,
            previousBranch != nextBranch
        {
            await emitFilesystemEvent(
                worktreeId: worktreeId,
                timestamp: envelopeClock.now,
                event: .branchChanged(from: previousBranch, to: nextBranch)
            )
        }
        currentRoot.lastKnownBranch = statusSnapshot.branch
        roots[worktreeId] = currentRoot
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
        timestamp: ContinuousClock.Instant,
        event: FilesystemEvent
    ) async {
        nextEnvelopeSequence += 1
        let envelope = PaneEventEnvelope(
            source: .system(.builtin(.filesystemWatcher)),
            sourceFacets: PaneContextFacets(worktreeId: worktreeId),
            paneKind: nil,
            seq: nextEnvelopeSequence,
            commandId: nil,
            correlationId: nil,
            timestamp: timestamp,
            epoch: 0,
            event: .filesystem(event)
        )
        await bus.post(envelope)
        Self.logger.debug("Posted filesystem event for worktree \(worktreeId.uuidString, privacy: .public)")
    }
}
