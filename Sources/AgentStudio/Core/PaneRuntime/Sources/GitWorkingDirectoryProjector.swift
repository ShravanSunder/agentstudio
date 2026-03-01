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

    private let runtimeBus: EventBus<RuntimeEnvelope>?
    private let legacyBus: EventBus<PaneEventEnvelope>?
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
        self.legacyBus = nil
        self.gitWorkingTreeProvider = gitWorkingTreeProvider
        self.envelopeClock = envelopeClock
        self.coalescingWindow = coalescingWindow
        self.sleepClock = sleepClock
        self.subscriptionBufferLimit = subscriptionBufferLimit
    }

    init(
        bus: EventBus<PaneEventEnvelope>,
        gitWorkingTreeProvider: any GitWorkingTreeStatusProvider = ShellGitWorkingTreeStatusProvider(),
        envelopeClock: ContinuousClock = ContinuousClock(),
        coalescingWindow: Duration = .zero,
        sleepClock: any Clock<Duration> = ContinuousClock(),
        subscriptionBufferLimit: Int = 256
    ) {
        self.runtimeBus = nil
        self.legacyBus = bus
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
        if let runtimeBus {
            let stream = await runtimeBus.subscribe(
                bufferingPolicy: .bufferingNewest(subscriptionBufferLimit)
            )

            subscriptionTask = Task { [weak self] in
                for await runtimeEnvelope in stream {
                    guard !Task.isCancelled else { break }
                    guard let self else { return }
                    guard let legacyEnvelope = runtimeEnvelope.toLegacy() else { continue }
                    await self.handleIncomingEnvelope(legacyEnvelope)
                }
            }
            return
        }

        guard let legacyBus else { return }
        let stream = await legacyBus.subscribe(
            bufferingPolicy: .bufferingNewest(subscriptionBufferLimit)
        )
        subscriptionTask = Task { [weak self] in
            for await envelope in stream {
                guard !Task.isCancelled else { break }
                guard let self else { return }
                await self.handleIncomingEnvelope(envelope)
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
    }

    private func handleIncomingEnvelope(_ envelope: PaneEventEnvelope) async {
        guard envelope.source == .system(.builtin(.filesystemWatcher)) else { return }
        guard case .filesystem(let filesystemEvent) = envelope.event else { return }

        switch filesystemEvent.compatibilityScope {
        case .systemTopology:
            switch filesystemEvent {
            case .worktreeRegistered(let worktreeId, let repoId, let rootPath):
                suppressedWorktreeIds.remove(worktreeId)
                // Eager materialization: publish initial snapshot before any path diff events.
                pendingByWorktreeId[worktreeId] = FileChangeset(
                    worktreeId: worktreeId,
                    repoId: repoId,
                    rootPath: rootPath,
                    paths: [],
                    timestamp: envelope.timestamp,
                    batchSeq: 0
                )
                spawnOrCoalesce(worktreeId: worktreeId)
            case .worktreeUnregistered(let worktreeId, _):
                suppressedWorktreeIds.insert(worktreeId)
                pendingByWorktreeId.removeValue(forKey: worktreeId)
                lastKnownBranchByWorktree.removeValue(forKey: worktreeId)
                if let task = worktreeTasks.removeValue(forKey: worktreeId) {
                    task.cancel()
                }
            case .filesChanged, .gitSnapshotChanged, .branchChanged, .diffAvailable:
                return
            }
        case .worktreeFilesystem:
            guard case .filesChanged(let changeset) = filesystemEvent else { return }
            let worktreeId = changeset.worktreeId
            guard !suppressedWorktreeIds.contains(worktreeId) else { return }
            pendingByWorktreeId[worktreeId] = changeset
            spawnOrCoalesce(worktreeId: worktreeId)
        case .worktreeGitWorkingDirectory:
            // Ignore projector output events to prevent feedback loops.
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
                        "Unexpected projector sleep failure for worktree \(worktreeId.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                    return
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

        await emitFilesystemEvent(
            worktreeId: changeset.worktreeId,
            repoId: changeset.repoId,
            event: .gitSnapshotChanged(
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
            await emitFilesystemEvent(
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
    }

    private func emitFilesystemEvent(worktreeId: UUID, repoId: UUID, event: FilesystemEvent) async {
        nextEnvelopeSequence += 1
        let envelope = PaneEventEnvelope(
            source: .system(.builtin(.gitWorkingDirectoryProjector)),
            sourceFacets: PaneContextFacets(repoId: repoId, worktreeId: worktreeId),
            paneKind: nil,
            seq: nextEnvelopeSequence,
            commandId: nil,
            correlationId: nil,
            timestamp: envelopeClock.now,
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
            droppedCount = 0
        }
        if droppedCount > 0 {
            Self.logger.warning(
                "Git projector event delivery dropped for \(droppedCount, privacy: .public) subscriber(s); seq=\(self.nextEnvelopeSequence, privacy: .public)"
            )
        }
        Self.logger.debug("Posted git projector event for worktree \(worktreeId.uuidString, privacy: .public)")
    }
}
