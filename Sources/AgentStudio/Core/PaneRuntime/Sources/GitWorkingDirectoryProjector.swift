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
    private let sleepClock: any Clock<Duration>
    private let subscriptionBufferLimit: Int

    private var subscriptionTask: Task<Void, Never>?
    private var worktreeTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingByWorktreeId: [UUID: FileChangeset] = [:]
    private var suppressedWorktreeIds: Set<UUID> = []
    private var lastKnownBranchByWorktree: [UUID: String] = [:]
    private var repoIdByWorktreeId: [UUID: UUID] = [:]
    private var lastKnownOriginByRepoId: [UUID: String] = [:]
    private var nextEnvelopeSequence: UInt64 = 0

    init(
        bus: EventBus<RuntimeEnvelope> = PaneRuntimeEventBus.shared,
        gitWorkingTreeProvider: any GitWorkingTreeStatusProvider = ShellGitWorkingTreeStatusProvider(),
        envelopeClock: ContinuousClock = ContinuousClock(),
        coalescingWindow: Duration = .zero,
        sleepClock: any Clock<Duration> = ContinuousClock(),
        subscriptionBufferLimit: Int = 256
    ) {
        self.runtimeBus = bus
        self.gitWorkingTreeProvider = gitWorkingTreeProvider
        self.envelopeClock = envelopeClock
        self.coalescingWindow = coalescingWindow
        self.sleepClock = sleepClock
        self.subscriptionBufferLimit = subscriptionBufferLimit
    }

    isolated deinit {
        subscriptionTask?.cancel()
        for task in worktreeTasks.values {
            task.cancel()
        }
        worktreeTasks.removeAll(keepingCapacity: false)
    }

    func start() async {
        guard subscriptionTask == nil else { return }
        let stream = await runtimeBus.subscribe(
            bufferingPolicy: .bufferingNewest(subscriptionBufferLimit)
        )
        subscriptionTask = Task { [weak self] in
            for await runtimeEnvelope in stream {
                guard !Task.isCancelled else { break }
                guard let self else { return }
                await self.handleIncomingRuntimeEnvelope(runtimeEnvelope)
            }
        }
    }

    func shutdown() async {
        let subscription = subscriptionTask
        subscriptionTask?.cancel()
        subscriptionTask = nil

        var tasksToAwait: [Task<Void, Never>] = []
        for task in worktreeTasks.values {
            task.cancel()
            tasksToAwait.append(task)
        }
        worktreeTasks.removeAll(keepingCapacity: false)

        if let subscription {
            await subscription.value
        }
        for task in tasksToAwait {
            await task.value
        }
        pendingByWorktreeId.removeAll(keepingCapacity: false)
        suppressedWorktreeIds.removeAll(keepingCapacity: false)
        lastKnownBranchByWorktree.removeAll(keepingCapacity: false)
        repoIdByWorktreeId.removeAll(keepingCapacity: false)
        lastKnownOriginByRepoId.removeAll(keepingCapacity: false)
    }

    private func handleIncomingRuntimeEnvelope(_ envelope: RuntimeEnvelope) async {
        switch envelope {
        case .system(let systemEnvelope):
            guard systemEnvelope.source == .builtin(.filesystemWatcher) else { return }
            guard case .topology(let topologyEvent) = systemEnvelope.event else { return }
            switch topologyEvent {
            case .worktreeRegistered(let worktreeId, let repoId, let rootPath):
                suppressedWorktreeIds.remove(worktreeId)
                repoIdByWorktreeId[worktreeId] = repoId
                pendingByWorktreeId[worktreeId] = FileChangeset(
                    worktreeId: worktreeId,
                    repoId: repoId,
                    rootPath: rootPath,
                    paths: [],
                    timestamp: systemEnvelope.timestamp,
                    batchSeq: 0
                )
                spawnOrCoalesce(worktreeId: worktreeId)
            case .worktreeUnregistered(let worktreeId, let repoId):
                suppressedWorktreeIds.insert(worktreeId)
                pendingByWorktreeId.removeValue(forKey: worktreeId)
                lastKnownBranchByWorktree.removeValue(forKey: worktreeId)
                repoIdByWorktreeId.removeValue(forKey: worktreeId)
                if !repoIdByWorktreeId.values.contains(repoId) {
                    lastKnownOriginByRepoId.removeValue(forKey: repoId)
                }
                if let task = worktreeTasks.removeValue(forKey: worktreeId) {
                    task.cancel()
                }
            case .repoDiscovered, .repoRemoved:
                return
            }
        case .worktree(let worktreeEnvelope):
            guard worktreeEnvelope.source == .system(.builtin(.filesystemWatcher)) else { return }
            guard case .filesystem(.filesChanged(let changeset)) = worktreeEnvelope.event else { return }
            let worktreeId = changeset.worktreeId
            guard !suppressedWorktreeIds.contains(worktreeId) else { return }
            repoIdByWorktreeId[worktreeId] = changeset.repoId
            pendingByWorktreeId[worktreeId] = changeset
            spawnOrCoalesce(worktreeId: worktreeId)
        case .pane:
            return
        }
    }

    private func spawnOrCoalesce(worktreeId: UUID) {
        guard worktreeTasks[worktreeId] == nil else { return }

        worktreeTasks[worktreeId] = Task { [weak self] in
            guard let self else { return }
            await self.drainWorktree(worktreeId: worktreeId)
        }
    }

    private func drainWorktree(worktreeId: UUID) async {
        defer { worktreeTasks.removeValue(forKey: worktreeId) }

        while !Task.isCancelled {
            guard var nextChangeset = pendingByWorktreeId.removeValue(forKey: worktreeId) else {
                return
            }
            if coalescingWindow > .zero {
                do {
                    try await sleepClock.sleep(for: coalescingWindow)
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
        guard let statusSnapshot = await gitWorkingTreeProvider.status(for: changeset.rootPath) else {
            Self.logger.error(
                """
                Git snapshot unavailable for worktree \(changeset.worktreeId.uuidString, privacy: .public) \
                root=\(changeset.rootPath.path, privacy: .public). \
                See FilesystemGitWorkingTree logs for failure category.
                """
            )
            return
        }
        guard !Task.isCancelled else { return }
        guard !suppressedWorktreeIds.contains(changeset.worktreeId) else { return }

        await emitGitWorkingDirectoryEvent(
            worktreeId: changeset.worktreeId,
            repoId: changeset.repoId,
            event: .snapshotChanged(
                snapshot: GitWorkingTreeSnapshot(
                    worktreeId: changeset.worktreeId,
                    repoId: changeset.repoId,
                    rootPath: changeset.rootPath,
                    summary: statusSnapshot.summary,
                    branch: statusSnapshot.branch
                )
            )
        )

        if let previousBranch = lastKnownBranchByWorktree[changeset.worktreeId],
            let nextBranch = statusSnapshot.branch,
            previousBranch != nextBranch
        {
            await emitGitWorkingDirectoryEvent(
                worktreeId: changeset.worktreeId,
                repoId: changeset.repoId,
                event: .branchChanged(
                    worktreeId: changeset.worktreeId,
                    repoId: changeset.repoId,
                    from: previousBranch,
                    to: nextBranch
                )
            )
        }
        lastKnownBranchByWorktree[changeset.worktreeId] = statusSnapshot.branch

        guard shouldCheckOrigin(for: changeset) else { return }

        let currentOrigin = (statusSnapshot.origin ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let previousOrigin = lastKnownOriginByRepoId[changeset.repoId]
        if previousOrigin != currentOrigin {
            await emitGitWorkingDirectoryEvent(
                worktreeId: changeset.worktreeId,
                repoId: changeset.repoId,
                event: .originChanged(
                    repoId: changeset.repoId,
                    from: previousOrigin ?? "",
                    to: currentOrigin
                )
            )
            lastKnownOriginByRepoId[changeset.repoId] = currentOrigin
        }
    }

    private func shouldCheckOrigin(for changeset: FileChangeset) -> Bool {
        if changeset.paths.isEmpty {
            return true
        }
        return changeset.paths.contains(where: Self.isGitConfigPath)
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
        Self.logger.debug("Posted git projector event for worktree \(worktreeId.uuidString, privacy: .public)")
    }
}
