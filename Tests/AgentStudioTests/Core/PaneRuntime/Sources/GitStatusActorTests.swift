import Foundation
import Testing

@testable import AgentStudio

@Suite("GitStatusActor")
struct GitStatusActorTests {
    @Test("filesChanged triggers git snapshot fact")
    func filesChangedTriggersGitSnapshotFact() async throws {
        let bus = EventBus<PaneEventEnvelope>()
        let provider = StubGitStatusProvider { _ in
            GitStatusSnapshot(
                summary: GitStatusSummary(changed: 3, staged: 1, untracked: 2),
                branch: "feature/projector"
            )
        }
        let actor = GitStatusActor(
            bus: bus,
            gitStatusProvider: provider,
            coalescingWindow: .zero
        )

        let observed = ObservedGitEvents()
        let collectionTask = await startCollection(on: bus, observed: observed)
        await actor.start()

        let worktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/git-status-actor-\(UUID().uuidString)")
        await bus.post(makeFilesChangedEnvelope(seq: 1, worktreeId: worktreeId, rootPath: rootPath, batchSeq: 1))

        let didReceiveSnapshot = await waitUntil {
            await observed.snapshotCount(for: worktreeId) >= 1
        }
        #expect(didReceiveSnapshot)

        let latestSnapshot = await observed.latestSnapshot(for: worktreeId)
        #expect(latestSnapshot?.summary.changed == 3)
        #expect(latestSnapshot?.summary.staged == 1)
        #expect(latestSnapshot?.summary.untracked == 2)
        #expect(latestSnapshot?.branch == "feature/projector")

        await actor.shutdown()
        collectionTask.cancel()
    }

    @Test("coalesces same worktree to latest while compute in-flight")
    func coalescesSameWorktreeToLatest() async throws {
        let bus = EventBus<PaneEventEnvelope>()
        let gate = AsyncGate()
        let calls = CallCounter()
        let provider = StubGitStatusProvider { _ in
            _ = await calls.increment()
            await gate.waitUntilOpen()
            return GitStatusSnapshot(
                summary: GitStatusSummary(changed: 1, staged: 0, untracked: 0),
                branch: "main"
            )
        }
        let actor = GitStatusActor(
            bus: bus,
            gitStatusProvider: provider,
            coalescingWindow: .zero
        )

        let observed = ObservedGitEvents()
        let collectionTask = await startCollection(on: bus, observed: observed)
        await actor.start()

        let worktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/coalesce-\(UUID().uuidString)")

        await bus.post(makeFilesChangedEnvelope(seq: 1, worktreeId: worktreeId, rootPath: rootPath, batchSeq: 1))
        let firstStarted = await waitUntil { await calls.value() >= 1 }
        #expect(firstStarted)

        await bus.post(makeFilesChangedEnvelope(seq: 2, worktreeId: worktreeId, rootPath: rootPath, batchSeq: 2))
        await bus.post(makeFilesChangedEnvelope(seq: 3, worktreeId: worktreeId, rootPath: rootPath, batchSeq: 3))

        await gate.open()

        let reachedTwoCalls = await waitUntil { await calls.value() >= 2 }
        #expect(reachedTwoCalls)
        for _ in 0..<200 {
            await Task.yield()
        }
        #expect(await calls.value() == 2)
        #expect(await observed.snapshotCount(for: worktreeId) == 2)

        await actor.shutdown()
        collectionTask.cancel()
    }

    @Test("independent worktrees run independently")
    func independentWorktreesRunIndependently() async throws {
        let bus = EventBus<PaneEventEnvelope>()
        let gate = AsyncGate()
        let calls = CallCounter()
        let provider = StubGitStatusProvider { _ in
            _ = await calls.increment()
            await gate.waitUntilOpen()
            return GitStatusSnapshot(
                summary: GitStatusSummary(changed: 2, staged: 1, untracked: 0),
                branch: "main"
            )
        }
        let actor = GitStatusActor(
            bus: bus,
            gitStatusProvider: provider,
            coalescingWindow: .zero
        )

        let observed = ObservedGitEvents()
        let collectionTask = await startCollection(on: bus, observed: observed)
        await actor.start()

        let firstWorktreeId = UUID()
        let secondWorktreeId = UUID()
        await bus.post(
            makeFilesChangedEnvelope(
                seq: 1,
                worktreeId: firstWorktreeId,
                rootPath: URL(fileURLWithPath: "/tmp/parallel-a-\(UUID().uuidString)"),
                batchSeq: 1
            )
        )
        await bus.post(
            makeFilesChangedEnvelope(
                seq: 2,
                worktreeId: secondWorktreeId,
                rootPath: URL(fileURLWithPath: "/tmp/parallel-b-\(UUID().uuidString)"),
                batchSeq: 1
            )
        )

        let bothStarted = await waitUntil { await calls.value() >= 2 }
        #expect(bothStarted)

        await gate.open()
        let bothProducedSnapshots = await waitUntil {
            let firstCount = await observed.snapshotCount(for: firstWorktreeId)
            let secondCount = await observed.snapshotCount(for: secondWorktreeId)
            return firstCount >= 1 && secondCount >= 1
        }
        #expect(bothProducedSnapshots)

        await actor.shutdown()
        collectionTask.cancel()
    }

    @Test("worktree unregistration cancels and clears state")
    func worktreeUnregistrationCancelsAndClearsState() async throws {
        let bus = EventBus<PaneEventEnvelope>()
        let gate = AsyncGate()
        let calls = CallCounter()
        let provider = StubGitStatusProvider { _ in
            _ = await calls.increment()
            await gate.waitUntilOpen()
            return GitStatusSnapshot(
                summary: GitStatusSummary(changed: 4, staged: 0, untracked: 1),
                branch: "cleanup"
            )
        }
        let actor = GitStatusActor(
            bus: bus,
            gitStatusProvider: provider,
            coalescingWindow: .zero
        )

        let observed = ObservedGitEvents()
        let collectionTask = await startCollection(on: bus, observed: observed)
        await actor.start()

        let worktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/cleanup-\(UUID().uuidString)")
        await bus.post(makeFilesChangedEnvelope(seq: 1, worktreeId: worktreeId, rootPath: rootPath, batchSeq: 1))
        let started = await waitUntil { await calls.value() >= 1 }
        #expect(started)

        await bus.post(
            makeEnvelope(
                seq: 2,
                worktreeId: worktreeId,
                event: .worktreeUnregistered(worktreeId: worktreeId)
            )
        )
        await bus.post(makeFilesChangedEnvelope(seq: 3, worktreeId: worktreeId, rootPath: rootPath, batchSeq: 2))

        await gate.open()
        for _ in 0..<300 {
            await Task.yield()
        }

        #expect(await calls.value() == 1)
        #expect(await observed.snapshotCount(for: worktreeId) == 0)
        #expect(await observed.branchEventCount(for: worktreeId) == 0)

        await actor.shutdown()
        collectionTask.cancel()
    }

    private func startCollection(
        on bus: EventBus<PaneEventEnvelope>,
        observed: ObservedGitEvents
    ) async -> Task<Void, Never> {
        let stream = await bus.subscribe()
        return Task {
            for await envelope in stream {
                await observed.record(envelope)
            }
        }
    }

    private func makeFilesChangedEnvelope(
        seq: UInt64,
        worktreeId: UUID,
        rootPath: URL,
        batchSeq: UInt64
    ) -> PaneEventEnvelope {
        makeEnvelope(
            seq: seq,
            worktreeId: worktreeId,
            event: .filesChanged(
                changeset: FileChangeset(
                    worktreeId: worktreeId,
                    rootPath: rootPath,
                    paths: ["Sources/File.swift"],
                    timestamp: ContinuousClock().now,
                    batchSeq: batchSeq
                )
            )
        )
    }

    private func makeEnvelope(
        seq: UInt64,
        worktreeId: UUID,
        event: FilesystemEvent
    ) -> PaneEventEnvelope {
        PaneEventEnvelope(
            source: .system(.builtin(.filesystemWatcher)),
            sourceFacets: PaneContextFacets(worktreeId: worktreeId),
            paneKind: nil,
            seq: seq,
            commandId: nil,
            correlationId: nil,
            timestamp: ContinuousClock().now,
            epoch: 0,
            event: .filesystem(event)
        )
    }

    private func waitUntil(
        maxYields: Int = 2_000,
        condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        for _ in 0..<maxYields {
            if await condition() {
                return true
            }
            await Task.yield()
        }
        return await condition()
    }
}

private actor ObservedGitEvents {
    private var snapshotsByWorktreeId: [UUID: [GitWorkingTreeSnapshot]] = [:]
    private var branchEventsByWorktreeId: [UUID: [(String, String)]] = [:]

    func record(_ envelope: PaneEventEnvelope) {
        guard case .filesystem(let filesystemEvent) = envelope.event else { return }
        guard let worktreeId = envelope.sourceFacets.worktreeId else { return }

        switch filesystemEvent {
        case .gitSnapshotChanged(let snapshot):
            snapshotsByWorktreeId[worktreeId, default: []].append(snapshot)
        case .branchChanged(let from, let to):
            branchEventsByWorktreeId[worktreeId, default: []].append((from, to))
        case .worktreeRegistered, .worktreeUnregistered, .filesChanged, .diffAvailable:
            return
        }
    }

    func snapshotCount(for worktreeId: UUID) -> Int {
        snapshotsByWorktreeId[worktreeId]?.count ?? 0
    }

    func latestSnapshot(for worktreeId: UUID) -> GitWorkingTreeSnapshot? {
        snapshotsByWorktreeId[worktreeId]?.last
    }

    func branchEventCount(for worktreeId: UUID) -> Int {
        branchEventsByWorktreeId[worktreeId]?.count ?? 0
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func waitUntilOpen() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let continuations = waiters
        waiters.removeAll(keepingCapacity: false)
        for continuation in continuations {
            continuation.resume()
        }
    }
}

private actor CallCounter {
    private var count = 0

    func increment() -> Int {
        count += 1
        return count
    }

    func value() -> Int {
        count
    }
}
