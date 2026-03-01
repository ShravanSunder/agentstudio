import Foundation
import Testing

@testable import AgentStudio

@Suite("GitWorkingDirectoryProjector")
struct GitWorkingDirectoryProjectorTests {
    @Test("worktreeRegistered triggers eager initial git snapshot")
    func worktreeRegisteredTriggersEagerInitialGitSnapshot() async throws {
        let bus = EventBus<PaneEventEnvelope>()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
                branch: "main"
            )
        }
        let actor = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: provider,
            coalescingWindow: .zero
        )

        let observed = ObservedGitEvents()
        let collectionTask = await startCollection(on: bus, observed: observed)
        await actor.start()

        let worktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/eager-\(UUID().uuidString)")
        await bus.post(
            makeEnvelope(
                seq: 1,
                worktreeId: worktreeId,
                event: .worktreeRegistered(worktreeId: worktreeId, repoId: worktreeId, rootPath: rootPath)
            )
        )

        let didReceiveSnapshot = await waitUntil {
            await observed.snapshotCount(for: worktreeId) >= 1
        }
        #expect(didReceiveSnapshot)
        let snapshot = await observed.latestSnapshot(for: worktreeId)
        #expect(snapshot?.rootPath == rootPath)
        #expect(snapshot?.branch == "main")

        await actor.shutdown()
        collectionTask.cancel()
    }

    @Test("filesChanged triggers git snapshot fact")
    func filesChangedTriggersGitSnapshotFact() async throws {
        let bus = EventBus<PaneEventEnvelope>()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 3, staged: 1, untracked: 2),
                branch: "feature/projector"
            )
        }
        let actor = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: provider,
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

    @Test("projector emits derived git facts with dedicated system source tag")
    func projectorEmitsWithDedicatedSystemSource() async throws {
        let bus = EventBus<PaneEventEnvelope>()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                branch: "main"
            )
        }
        let actor = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: provider,
            coalescingWindow: .zero
        )
        await actor.start()

        let stream = await bus.subscribe()
        var iterator = stream.makeAsyncIterator()

        let worktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/source-tag-\(UUID().uuidString)")
        await bus.post(makeFilesChangedEnvelope(seq: 1, worktreeId: worktreeId, rootPath: rootPath, batchSeq: 1))

        var observedDerivedSource: EventSource?
        for _ in 0..<20 {
            guard let envelope = await iterator.next() else { break }
            guard case .filesystem(.gitSnapshotChanged) = envelope.event else { continue }
            observedDerivedSource = envelope.source
            break
        }

        #expect(observedDerivedSource == .system(.builtin(.gitWorkingDirectoryProjector)))
        await actor.shutdown()
    }

    @Test("provider nil status emits no git snapshot facts")
    func providerNilStatusEmitsNoGitSnapshotFacts() async throws {
        let bus = EventBus<PaneEventEnvelope>()
        let provider = StubGitWorkingTreeStatusProvider { _ in nil }
        let actor = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: provider,
            coalescingWindow: .zero
        )

        let observed = ObservedGitEvents()
        let collectionTask = await startCollection(on: bus, observed: observed)
        await actor.start()

        let worktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/provider-nil-\(UUID().uuidString)")
        await bus.post(makeFilesChangedEnvelope(seq: 1, worktreeId: worktreeId, rootPath: rootPath, batchSeq: 1))

        // Give the projector enough turns to process the request path.
        for _ in 0..<300 {
            await Task.yield()
        }

        #expect(await observed.snapshotCount(for: worktreeId) == 0)
        #expect(await observed.branchEventCount(for: worktreeId) == 0)

        await actor.shutdown()
        collectionTask.cancel()
    }

    @Test("coalesces same worktree to latest while compute in-flight")
    func coalescesSameWorktreeToLatest() async throws {
        let bus = EventBus<PaneEventEnvelope>()
        let gate = AsyncGate()
        let calls = CallCounter()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            _ = await calls.increment()
            await gate.waitUntilOpen()
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                branch: "main"
            )
        }
        let actor = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: provider,
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

    @Test("non-zero coalescing window merges rapid same-worktree bursts into one compute")
    func nonZeroCoalescingWindowMergesRapidBursts() async throws {
        let bus = EventBus<PaneEventEnvelope>()
        let calls = CallCounter()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            _ = await calls.increment()
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                branch: "main"
            )
        }
        let actor = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: provider,
            coalescingWindow: .milliseconds(60)
        )

        let observed = ObservedGitEvents()
        let collectionTask = await startCollection(on: bus, observed: observed)
        await actor.start()

        let worktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/window-\(UUID().uuidString)")
        await bus.post(makeFilesChangedEnvelope(seq: 1, worktreeId: worktreeId, rootPath: rootPath, batchSeq: 1))
        try await Task.sleep(for: .milliseconds(10))
        await bus.post(makeFilesChangedEnvelope(seq: 2, worktreeId: worktreeId, rootPath: rootPath, batchSeq: 2))

        let didEmitSnapshot = await waitUntil {
            await observed.snapshotCount(for: worktreeId) >= 1
        }
        #expect(didEmitSnapshot)
        try await Task.sleep(for: .milliseconds(90))
        #expect(await calls.value() == 1)
        #expect(await observed.snapshotCount(for: worktreeId) == 1)

        await actor.shutdown()
        collectionTask.cancel()
    }

    @Test("independent worktrees run independently")
    func independentWorktreesRunIndependently() async throws {
        let bus = EventBus<PaneEventEnvelope>()
        let gate = AsyncGate()
        let calls = CallCounter()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            _ = await calls.increment()
            await gate.waitUntilOpen()
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 2, staged: 1, untracked: 0),
                branch: "main"
            )
        }
        let actor = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: provider,
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
        let provider = StubGitWorkingTreeStatusProvider { _ in
            _ = await calls.increment()
            await gate.waitUntilOpen()
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 4, staged: 0, untracked: 1),
                branch: "cleanup"
            )
        }
        let actor = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: provider,
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
                event: .worktreeUnregistered(worktreeId: worktreeId, repoId: worktreeId)
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

    @Test("shutdown while provider is in-flight does not emit stale snapshot")
    func shutdownWhileProviderIsInFlightDoesNotEmitStaleSnapshot() async throws {
        let bus = EventBus<PaneEventEnvelope>()
        let gate = AsyncGate()
        let calls = CallCounter()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            _ = await calls.increment()
            await gate.waitUntilOpen()
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                branch: "main"
            )
        }
        let actor = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: provider,
            coalescingWindow: .zero
        )

        let observed = ObservedGitEvents()
        let collectionTask = await startCollection(on: bus, observed: observed)
        await actor.start()

        let worktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/shutdown-inflight-\(UUID().uuidString)")
        await bus.post(makeFilesChangedEnvelope(seq: 1, worktreeId: worktreeId, rootPath: rootPath, batchSeq: 1))
        let started = await waitUntil { await calls.value() >= 1 }
        #expect(started)

        let shutdownTask = Task {
            await actor.shutdown()
        }
        await gate.open()
        await shutdownTask.value

        for _ in 0..<300 {
            await Task.yield()
        }
        #expect(await observed.snapshotCount(for: worktreeId) == 0)
        #expect(await observed.branchEventCount(for: worktreeId) == 0)

        collectionTask.cancel()
    }

    @Test("branchChanged emits when consecutive snapshots change branch")
    func branchChangedEmitsWhenConsecutiveSnapshotsChangeBranch() async throws {
        let bus = EventBus<PaneEventEnvelope>()
        let calls = CallCounter()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            let callNumber = await calls.increment()
            let branch = callNumber == 1 ? "main" : "feature/split"
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: callNumber, staged: 0, untracked: 0),
                branch: branch
            )
        }
        let actor = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: provider,
            coalescingWindow: .zero
        )

        let observed = ObservedGitEvents()
        let collectionTask = await startCollection(on: bus, observed: observed)
        await actor.start()

        let worktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/branch-change-\(UUID().uuidString)")
        await bus.post(makeFilesChangedEnvelope(seq: 1, worktreeId: worktreeId, rootPath: rootPath, batchSeq: 1))

        let firstSnapshotObserved = await waitUntil {
            await observed.snapshotCount(for: worktreeId) >= 1
        }
        #expect(firstSnapshotObserved)

        await bus.post(makeFilesChangedEnvelope(seq: 2, worktreeId: worktreeId, rootPath: rootPath, batchSeq: 2))

        let observedBranchChange = await waitUntil {
            await observed.branchEventCount(for: worktreeId) >= 1
        }
        #expect(observedBranchChange)

        let branchEvent = await observed.latestBranchEvent(for: worktreeId)
        #expect(branchEvent?.0 == "main")
        #expect(branchEvent?.1 == "feature/split")

        await actor.shutdown()
        collectionTask.cancel()
    }

    @Test("git internal-only filesChanged event still triggers git snapshot projection")
    func gitInternalOnlyFilesChangedEventStillTriggersSnapshot() async throws {
        let bus = EventBus<PaneEventEnvelope>()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                branch: "main"
            )
        }
        let actor = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: provider,
            coalescingWindow: .zero
        )

        let observed = ObservedGitEvents()
        let collectionTask = await startCollection(on: bus, observed: observed)
        await actor.start()

        let worktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/git-internal-only-\(UUID().uuidString)")
        await bus.post(
            makeFilesChangedEnvelope(
                seq: 1,
                worktreeId: worktreeId,
                rootPath: rootPath,
                batchSeq: 1,
                paths: [],
                containsGitInternalChanges: true,
                suppressedGitInternalPathCount: 2
            )
        )

        let didReceiveSnapshot = await waitUntil {
            await observed.snapshotCount(for: worktreeId) >= 1
        }
        #expect(didReceiveSnapshot)
        let snapshot = await observed.latestSnapshot(for: worktreeId)
        #expect(snapshot?.worktreeId == worktreeId)
        #expect(snapshot?.branch == "main")

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
        batchSeq: UInt64,
        paths: [String] = ["Sources/File.swift"],
        containsGitInternalChanges: Bool = false,
        suppressedIgnoredPathCount: Int = 0,
        suppressedGitInternalPathCount: Int = 0
    ) -> PaneEventEnvelope {
        makeEnvelope(
            seq: seq,
            worktreeId: worktreeId,
            event: .filesChanged(
                changeset: FileChangeset(
                    worktreeId: worktreeId,
                    rootPath: rootPath,
                    paths: paths,
                    containsGitInternalChanges: containsGitInternalChanges,
                    suppressedIgnoredPathCount: suppressedIgnoredPathCount,
                    suppressedGitInternalPathCount: suppressedGitInternalPathCount,
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
        timeout: Duration = .seconds(2),
        pollInterval: Duration = .milliseconds(1),
        condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(for: pollInterval)
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
        case .branchChanged(let eventWorktreeId, _, let from, let to):
            guard eventWorktreeId == worktreeId else { return }
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

    func latestBranchEvent(for worktreeId: UUID) -> (String, String)? {
        branchEventsByWorktreeId[worktreeId]?.last
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
