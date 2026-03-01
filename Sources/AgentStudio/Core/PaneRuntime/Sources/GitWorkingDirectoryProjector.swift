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

    private let bus: EventBus<PaneEventEnvelope>
    private let gitStatusProvider: any GitStatusProvider
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
        bus: EventBus<PaneEventEnvelope> = PaneRuntimeEventBus.shared,
        gitStatusProvider: any GitStatusProvider = ShellGitStatusProvider(),
        envelopeClock: ContinuousClock = ContinuousClock(),
        coalescingWindow: Duration = .zero,
        sleepClock: any Clock<Duration> = ContinuousClock(),
        subscriptionBufferLimit: Int = 256
    ) {
        self.bus = bus
        self.gitStatusProvider = gitStatusProvider
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
        let stream = await bus.subscribe(
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

    func shutdown() {
        subscriptionTask?.cancel()
        subscriptionTask = nil

        for task in worktreeTasks.values {
            task.cancel()
        }
        worktreeTasks.removeAll(keepingCapacity: false)
        pendingByWorktreeId.removeAll(keepingCapacity: false)
        suppressedWorktreeIds.removeAll(keepingCapacity: false)
        lastKnownBranchByWorktree.removeAll(keepingCapacity: false)
    }

    private func handleIncomingEnvelope(_ envelope: PaneEventEnvelope) async {
        guard case .filesystem(let filesystemEvent) = envelope.event else { return }

        switch filesystemEvent {
        case .worktreeRegistered(let worktreeId, let rootPath):
            suppressedWorktreeIds.remove(worktreeId)
            // Eager materialization: publish initial snapshot before any path diff events.
            pendingByWorktreeId[worktreeId] = FileChangeset(
                worktreeId: worktreeId,
                rootPath: rootPath,
                paths: [],
                timestamp: envelope.timestamp,
                batchSeq: 0
            )
            spawnOrCoalesce(worktreeId: worktreeId)

        case .worktreeUnregistered(let worktreeId):
            suppressedWorktreeIds.insert(worktreeId)
            pendingByWorktreeId.removeValue(forKey: worktreeId)
            lastKnownBranchByWorktree.removeValue(forKey: worktreeId)
            if let task = worktreeTasks.removeValue(forKey: worktreeId) {
                task.cancel()
            }

        case .filesChanged(let changeset):
            let worktreeId = changeset.worktreeId
            guard !suppressedWorktreeIds.contains(worktreeId) else { return }
            pendingByWorktreeId[worktreeId] = changeset
            spawnOrCoalesce(worktreeId: worktreeId)

        case .gitSnapshotChanged, .branchChanged, .diffAvailable:
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
                try? await sleepClock.sleep(for: coalescingWindow)
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
        guard let statusSnapshot = await gitStatusProvider.status(for: changeset.rootPath) else {
            Self.logger.error(
                "Git snapshot unavailable for worktree \(changeset.worktreeId.uuidString, privacy: .public) root=\(changeset.rootPath.path, privacy: .public)"
            )
            return
        }
        guard !Task.isCancelled else { return }
        guard !suppressedWorktreeIds.contains(changeset.worktreeId) else { return }

        await emitFilesystemEvent(
            worktreeId: changeset.worktreeId,
            event: .gitSnapshotChanged(
                snapshot: GitWorkingTreeSnapshot(
                    worktreeId: changeset.worktreeId,
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
                event: .branchChanged(from: previousBranch, to: nextBranch)
            )
        }
        lastKnownBranchByWorktree[changeset.worktreeId] = statusSnapshot.branch
    }

    private func emitFilesystemEvent(worktreeId: UUID, event: FilesystemEvent) async {
        nextEnvelopeSequence += 1
        let envelope = PaneEventEnvelope(
            source: .system(.builtin(.filesystemWatcher)),
            sourceFacets: PaneContextFacets(worktreeId: worktreeId),
            paneKind: nil,
            seq: nextEnvelopeSequence,
            commandId: nil,
            correlationId: nil,
            timestamp: envelopeClock.now,
            epoch: 0,
            event: .filesystem(event)
        )
        await bus.post(envelope)
        Self.logger.debug("Posted git projector event for worktree \(worktreeId.uuidString, privacy: .public)")
    }
}
