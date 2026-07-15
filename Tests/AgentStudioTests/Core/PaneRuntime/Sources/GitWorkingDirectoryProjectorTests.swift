// swiftlint:disable file_length type_body_length

import Foundation
import Testing

@testable import AgentStudio

@Suite("GitWorkingDirectoryProjector")
struct GitWorkingDirectoryProjectorTests {
    @Test("default provider emits real SDK-backed initial git snapshot")
    func defaultProviderEmitsRealSDKBackedInitialGitSnapshot() async throws {
        let repoURL = try FilesystemTestGitRepo.create(named: "projector-default-sdk-provider")
        defer { FilesystemTestGitRepo.destroy(repoURL) }
        try "initial\n".write(to: repoURL.appending(path: "tracked.txt"), atomically: true, encoding: .utf8)
        try FilesystemTestGitRepo.runGit(at: repoURL, args: ["add", "tracked.txt"])
        try FilesystemTestGitRepo.runGit(at: repoURL, args: ["commit", "-m", "Seed projector default"])
        try "initial\nupdated\n".write(to: repoURL.appending(path: "tracked.txt"), atomically: true, encoding: .utf8)

        let bus = EventBus<RuntimeEnvelope>()
        let actor = GitWorkingDirectoryProjector(
            bus: bus,
            coalescingWindow: .zero
        )
        let observed = ObservedGitEvents()
        let collectionTask = await startCollection(on: bus, observed: observed)
        await actor.start()

        let worktreeId = UUID()
        await bus.post(
            makeEnvelope(
                seq: 1,
                worktreeId: worktreeId,
                event: .worktreeRegistered(worktreeId: worktreeId, repoId: UUID(), rootPath: repoURL)
            )
        )

        let didReceiveSnapshot = await waitUntil(maxTurns: 2_000_000) {
            await observed.snapshotCount(for: worktreeId) >= 1
        }
        #expect(didReceiveSnapshot)
        let snapshot = await observed.latestSnapshot(for: worktreeId)
        #expect(snapshot?.rootPath == repoURL)
        #expect(snapshot?.branch == "main")
        #expect(snapshot?.summary.changed == 1)

        await actor.shutdown()
        collectionTask.cancel()
    }

    @Test("worktreeRegistered triggers eager initial git snapshot")
    func worktreeRegisteredTriggersEagerInitialGitSnapshot() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
                branch: "main",
                origin: nil
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
        let bus = EventBus<RuntimeEnvelope>()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 3, staged: 1, untracked: 2),
                branch: "feature/projector",
                origin: nil
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
        let bus = EventBus<RuntimeEnvelope>()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                branch: "main",
                origin: nil
            )
        }
        let actor = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: provider,
            coalescingWindow: .zero
        )
        await actor.start()

        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        var iterator = stream.makeAsyncIterator()

        let worktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/source-tag-\(UUID().uuidString)")
        await bus.post(makeFilesChangedEnvelope(seq: 1, worktreeId: worktreeId, rootPath: rootPath, batchSeq: 1))

        var observedDerivedSource: EventSource?
        var observedDerivedSnapshot: GitWorkingTreeSnapshot?
        for _ in 0..<20 {
            guard let envelope = await iterator.next() else { break }
            guard case .worktree(let worktreeEnvelope) = envelope else { continue }
            guard case .gitWorkingDirectory(.snapshotChanged(let snapshot)) = worktreeEnvelope.event else { continue }
            observedDerivedSource = worktreeEnvelope.source
            observedDerivedSnapshot = snapshot
            break
        }

        #expect(observedDerivedSource == .system(.builtin(.gitWorkingDirectoryProjector)))
        let derivedSnapshot = try #require(observedDerivedSnapshot)
        #expect(derivedSnapshot.worktreeId == worktreeId)
        #expect(derivedSnapshot.branch == "main")
        await actor.shutdown()
    }

    @Test("provider nil status emits no git snapshot facts")
    func providerNilStatusEmitsNoGitSnapshotFacts() async throws {
        let bus = EventBus<RuntimeEnvelope>()
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

    @Test("provider nil status retries once after bounded backoff")
    func providerNilStatusRetriesOnceAfterBoundedBackoff() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let calls = CallCounter()
        let policy = AppPolicies.GitRefresh.Policy(
            backgroundStripeCount: 1,
            maxNilStatusRetries: 1,
            nilStatusRetryDelay: .milliseconds(50)
        )
        let provider = StubGitWorkingTreeStatusProvider { _ in
            let callNumber = await calls.increment()
            guard callNumber > 1 else { return nil }
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 2, staged: 0, untracked: 0),
                branch: "retry-success",
                origin: nil
            )
        }
        let actor = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: provider,
            coalescingWindow: .zero,
            sleepClock: clock,
            refreshPolicy: policy
        )

        let observed = ObservedGitEvents()
        let collectionTask = await startCollection(on: bus, observed: observed)
        await actor.start()

        let worktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/provider-nil-retry-\(UUID().uuidString)")
        await bus.post(makeFilesChangedEnvelope(seq: 1, worktreeId: worktreeId, rootPath: rootPath, batchSeq: 1))

        let firstAttemptCompleted = await waitUntil {
            await calls.value() == 1
        }
        #expect(firstAttemptCompleted)
        let retryScheduled = await waitUntilYielding {
            clock.pendingSleepCount > 0
        }
        #expect(retryScheduled)
        guard retryScheduled else {
            await actor.shutdown()
            collectionTask.cancel()
            return
        }
        #expect(await observed.snapshotCount(for: worktreeId) == 0)

        clock.advance(by: .milliseconds(50))

        let retriedAndEmittedSnapshot = await waitUntil {
            let callCount = await calls.value()
            let latestSnapshot = await observed.latestSnapshot(for: worktreeId)
            return callCount == 2 && latestSnapshot?.branch == "retry-success"
        }
        #expect(retriedAndEmittedSnapshot)
        #expect(await observed.snapshotCount(for: worktreeId) == 1)

        await actor.shutdown()
        collectionTask.cancel()
    }

    @Test("nil status retry skips when worktree context changes before delay")
    func nilStatusRetrySkipsWhenWorktreeContextChangesBeforeDelay() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let callOrder = CallOrderRecorder()
        let policy = AppPolicies.GitRefresh.Policy(
            backgroundStripeCount: 1,
            maxNilStatusRetries: 1,
            nilStatusRetryDelay: .milliseconds(50)
        )
        let provider = StubGitWorkingTreeStatusProvider { rootPath in
            let label = rootPath.lastPathComponent
            await callOrder.record(label)
            guard label.contains("old-retry-root") == false else { return nil }
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                branch: label,
                origin: nil
            )
        }
        let actor = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: provider,
            coalescingWindow: .zero,
            sleepClock: clock,
            refreshPolicy: policy
        )

        let observed = ObservedGitEvents()
        let collectionTask = await startCollection(on: bus, observed: observed)
        await actor.start()

        let worktreeId = UUID()
        let oldRootPath = URL(fileURLWithPath: "/tmp/old-retry-root-\(UUID().uuidString)")
        let newRootPath = URL(fileURLWithPath: "/tmp/new-retry-root-\(UUID().uuidString)")
        await bus.post(
            makeEnvelope(
                seq: 1,
                worktreeId: worktreeId,
                event: .worktreeRegistered(worktreeId: worktreeId, repoId: worktreeId, rootPath: oldRootPath)
            )
        )
        let oldNilAttemptCompleted = await waitUntil {
            let labels = await callOrder.labels
            return labels.contains { $0.contains("old-retry-root") }
        }
        #expect(oldNilAttemptCompleted)
        await clock.waitForPendingSleepCount(atLeast: 1)

        await actor.assertTopology(
            FilesystemTopologyAssertion(
                generation: 1,
                contextsByWorktreeId: [
                    worktreeId: WorktreeFilesystemContext(repoId: worktreeId, rootPath: newRootPath)
                ]
            )
        )
        let newContextSnapshotArrived = await waitUntil {
            await observed.latestSnapshot(for: worktreeId)?.rootPath == newRootPath
        }
        #expect(newContextSnapshotArrived)

        clock.advance(by: .milliseconds(50))
        for _ in 0..<300 {
            await Task.yield()
        }
        let labels = await callOrder.labels
        #expect(labels.filter { $0.contains("old-retry-root") }.count == 1)

        await actor.shutdown()
        collectionTask.cancel()
    }

    @Test("same worktree emits the latest snapshot after overlapping in-flight compute")
    func sameWorktreeEmitsLatestSnapshotAfterInFlightCompute() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let gate = AsyncGate()
        let calls = CallCounter()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            let callNumber = await calls.increment()
            await gate.waitUntilOpen()
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                branch: "main-\(callNumber)",
                origin: nil
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

        let reachedLatestSnapshot = await waitUntil {
            await observed.latestSnapshot(for: worktreeId)?.branch == "main-2"
        }
        #expect(reachedLatestSnapshot)
        #expect(await calls.value() >= 2)
        #expect(await observed.snapshotCount(for: worktreeId) >= 2)
        #expect(await observed.latestSnapshot(for: worktreeId)?.branch == "main-2")

        await actor.shutdown()
        collectionTask.cancel()
        await collectionTask.value
    }

    @Test("ignored-only filesChanged event does not call git provider")
    func ignoredOnlyFilesChangedEventDoesNotCallGitProvider() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let calls = CallCounter()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            _ = await calls.increment()
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                branch: "main",
                origin: nil
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
        let rootPath = URL(fileURLWithPath: "/tmp/ignored-only-\(UUID().uuidString)")
        await bus.post(
            makeFilesChangedEnvelope(
                seq: 1,
                worktreeId: worktreeId,
                rootPath: rootPath,
                batchSeq: 1,
                paths: [],
                suppressedIgnoredPathCount: 4
            )
        )

        for _ in 0..<300 {
            await Task.yield()
        }
        #expect(await calls.value() == 0)
        #expect(await observed.snapshotCount(for: worktreeId) == 0)

        await actor.shutdown()
        collectionTask.cancel()
    }

    @Test("identical snapshot result does not emit duplicate snapshot facts")
    func identicalSnapshotResultDoesNotEmitDuplicateSnapshotFacts() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let calls = CallCounter()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            _ = await calls.increment()
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                branch: "main",
                origin: nil
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
        let rootPath = URL(fileURLWithPath: "/tmp/dedup-\(UUID().uuidString)")
        await bus.post(makeFilesChangedEnvelope(seq: 1, worktreeId: worktreeId, rootPath: rootPath, batchSeq: 1))
        let firstSnapshotArrived = await waitUntil {
            await observed.snapshotCount(for: worktreeId) == 1
        }
        #expect(firstSnapshotArrived)

        await bus.post(makeFilesChangedEnvelope(seq: 2, worktreeId: worktreeId, rootPath: rootPath, batchSeq: 2))
        let secondProviderCallCompleted = await waitUntil {
            await calls.value() == 2
        }
        #expect(secondProviderCallCompleted)
        for _ in 0..<300 {
            await Task.yield()
        }
        #expect(await observed.snapshotCount(for: worktreeId) == 1)

        await actor.shutdown()
        collectionTask.cancel()
    }

    @Test("non-zero coalescing window merges rapid same-worktree bursts into one compute")
    func nonZeroCoalescingWindowMergesRapidBursts() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let calls = CallCounter()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            _ = await calls.increment()
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                branch: "main",
                origin: nil
            )
        }
        let actor = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: provider,
            coalescingWindow: .milliseconds(60),
            sleepClock: clock
        )

        let observed = ObservedGitEvents()
        let collectionTask = await startCollection(on: bus, observed: observed)
        await actor.start()

        let worktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/window-\(UUID().uuidString)")
        await bus.post(makeFilesChangedEnvelope(seq: 1, worktreeId: worktreeId, rootPath: rootPath, batchSeq: 1))
        await bus.post(makeFilesChangedEnvelope(seq: 2, worktreeId: worktreeId, rootPath: rootPath, batchSeq: 2))
        let coalescingSleepScheduled = await waitUntilYielding {
            clock.pendingSleepCount > 0
        }
        #expect(coalescingSleepScheduled)
        clock.advance(by: .milliseconds(60))

        let didEmitSnapshot = await waitUntil {
            await observed.snapshotCount(for: worktreeId) >= 1
        }
        #expect(didEmitSnapshot)

        await actor.shutdown()
        collectionTask.cancel()
        await collectionTask.value

        #expect(await calls.value() == 1)
        #expect(await observed.snapshotCount(for: worktreeId) == 1)
    }

    @Test("independent worktrees run independently")
    func independentWorktreesRunIndependently() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let gate = AsyncGate()
        let calls = CallCounter()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            _ = await calls.increment()
            await gate.waitUntilOpen()
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 2, staged: 1, untracked: 0),
                branch: "main",
                origin: nil
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

    @Test("admission budget caps concurrent provider calls")
    func admissionBudgetCapsConcurrentProviderCalls() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let gate = AsyncGate()
        let calls = CallCounter()
        let policy = AppPolicies.GitRefresh.Policy(
            backgroundStripeCount: 1,
            maxConcurrentStatusComputes: 2
        )
        let provider = StubGitWorkingTreeStatusProvider { _ in
            _ = await calls.increment()
            await gate.waitUntilOpen()
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                branch: "main",
                origin: nil
            )
        }
        let actor = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: provider,
            coalescingWindow: .zero,
            refreshPolicy: policy
        )

        let observed = ObservedGitEvents()
        let collectionTask = await startCollection(on: bus, observed: observed)
        await actor.start()

        let worktreeIds = (0..<6).map { _ in UUID() }
        for (offset, worktreeId) in worktreeIds.enumerated() {
            await bus.post(
                makeFilesChangedEnvelope(
                    seq: UInt64(offset + 1),
                    worktreeId: worktreeId,
                    rootPath: URL(fileURLWithPath: "/tmp/admission-\(offset)-\(UUID().uuidString)"),
                    batchSeq: 1
                )
            )
        }

        let admittedInitialBudget = await waitUntil {
            await calls.value() >= policy.maxConcurrentStatusComputes
        }
        #expect(admittedInitialBudget)
        for _ in 0..<300 {
            await Task.yield()
        }
        #expect(await calls.value() == policy.maxConcurrentStatusComputes)

        await gate.open()
        let drainedAllQueuedWork = await waitUntil {
            await calls.value() == worktreeIds.count
        }
        #expect(drainedAllQueuedWork)

        let emittedAllSnapshots = await waitUntil {
            for worktreeId in worktreeIds {
                guard await observed.snapshotCount(for: worktreeId) == 1 else {
                    return false
                }
            }
            return true
        }
        #expect(emittedAllSnapshots)

        await actor.shutdown()
        collectionTask.cancel()
    }

    @Test("nil status retry releases admission slot during backoff")
    func nilStatusRetryReleasesAdmissionSlotDuringBackoff() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let callOrder = CallOrderRecorder()
        let policy = AppPolicies.GitRefresh.Policy(
            backgroundStripeCount: 1,
            maxConcurrentStatusComputes: 1,
            maxNilStatusRetries: 1,
            nilStatusRetryDelay: .milliseconds(50)
        )
        let provider = StubGitWorkingTreeStatusProvider { rootPath in
            let label = rootPath.lastPathComponent
            await callOrder.record(label)
            guard label.contains("retry-sleeper") == false else { return nil }
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                branch: label,
                origin: nil
            )
        }
        let actor = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: provider,
            coalescingWindow: .zero,
            sleepClock: clock,
            refreshPolicy: policy
        )

        let observed = ObservedGitEvents()
        let collectionTask = await startCollection(on: bus, observed: observed)
        await actor.start()

        let retryWorktreeId = UUID()
        let healthyWorktreeId = UUID()
        await bus.post(
            makeFilesChangedEnvelope(
                seq: 1,
                worktreeId: retryWorktreeId,
                rootPath: URL(fileURLWithPath: "/tmp/retry-sleeper-\(UUID().uuidString)"),
                batchSeq: 1
            )
        )
        let retryAttemptCompleted = await waitUntil {
            await callOrder.labels.count == 1
        }
        #expect(retryAttemptCompleted)
        let retryBackoffScheduled = await waitUntilYielding {
            clock.pendingSleepCount > 0
        }
        #expect(retryBackoffScheduled)

        await bus.post(
            makeFilesChangedEnvelope(
                seq: 2,
                worktreeId: healthyWorktreeId,
                rootPath: URL(fileURLWithPath: "/tmp/healthy-after-nil-\(UUID().uuidString)"),
                batchSeq: 1
            )
        )

        let healthyWorktreeAdmittedBeforeRetryDelay = await waitUntil {
            let labels = await callOrder.labels
            return labels.contains { $0.contains("healthy-after-nil") }
        }
        #expect(healthyWorktreeAdmittedBeforeRetryDelay)
        let healthySnapshotObserved = await waitUntil {
            await observed.snapshotCount(for: healthyWorktreeId) == 1
        }
        #expect(healthySnapshotObserved)

        await actor.shutdown()
        collectionTask.cancel()
    }

    @Test("reserved oldest stale slot admits background work ahead of younger UUID")
    func reservedOldestStaleSlotAdmitsBackgroundWorkAheadOfYoungerUUID() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let gate = AsyncGate()
        let callOrder = CallOrderRecorder()
        let policy = AppPolicies.GitRefresh.Policy(
            backgroundStripeCount: 1,
            maxConcurrentStatusComputes: 1,
            oldestStaleReservedSlots: 1
        )
        let provider = StubGitWorkingTreeStatusProvider { rootPath in
            let label = rootPath.lastPathComponent
            await callOrder.record(label)
            await gate.waitUntilOpen()
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                branch: label,
                origin: nil
            )
        }
        let actor = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: provider,
            coalescingWindow: .zero,
            refreshPolicy: policy
        )

        let observed = ObservedGitEvents()
        let collectionTask = await startCollection(on: bus, observed: observed)
        await actor.start()

        let runningWorktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000100")!
        let olderBackgroundWorktreeId = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let youngerBackgroundWorktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

        await bus.post(
            makeFilesChangedEnvelope(
                seq: 1,
                worktreeId: runningWorktreeId,
                rootPath: URL(fileURLWithPath: "/tmp/running-slot-\(UUID().uuidString)"),
                batchSeq: 1
            )
        )
        let firstCallStarted = await waitUntil {
            await callOrder.labels.count == 1
        }
        #expect(firstCallStarted)

        await bus.post(
            makeFilesChangedEnvelope(
                seq: 2,
                worktreeId: olderBackgroundWorktreeId,
                rootPath: URL(fileURLWithPath: "/tmp/old-background-\(UUID().uuidString)"),
                batchSeq: 1
            )
        )
        await bus.post(
            makeFilesChangedEnvelope(
                seq: 3,
                worktreeId: youngerBackgroundWorktreeId,
                rootPath: URL(fileURLWithPath: "/tmp/young-background-\(UUID().uuidString)"),
                batchSeq: 1
            )
        )

        await gate.open()
        let secondCallArrived = await waitUntil {
            await callOrder.labels.count >= 2
        }
        #expect(secondCallArrived)
        let labels = await callOrder.labels
        #expect(labels.dropFirst().first?.contains("old-background") == true)

        await actor.shutdown()
        collectionTask.cancel()
    }

    @Test("periodic refresh admits only the matching background stripe")
    func periodicRefreshAdmitsOnlyMatchingBackgroundStripe() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let policy = AppPolicies.GitRefresh.Policy(
            activeCadence: .milliseconds(120),
            backgroundStripeCount: 2,
            maxConcurrentStatusComputes: 4
        )
        let calls = CallCounter()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            let callNumber = await calls.increment()
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: callNumber, staged: 0, untracked: 0),
                branch: "main",
                origin: nil
            )
        }
        let actor = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: provider,
            coalescingWindow: .zero,
            periodicRefreshInterval: policy.activeCadence,
            sleepClock: clock,
            refreshPolicy: policy
        )

        let observed = ObservedGitEvents()
        let collectionTask = await startCollection(on: bus, observed: observed)
        await actor.start()

        let firstStripeWorktreeId = worktreeId(forBackgroundStripe: 0, policy: policy)
        let secondStripeWorktreeId = worktreeId(forBackgroundStripe: 1, policy: policy)
        await bus.post(
            makeEnvelope(
                seq: 1,
                worktreeId: firstStripeWorktreeId,
                event: .worktreeRegistered(
                    worktreeId: firstStripeWorktreeId,
                    repoId: firstStripeWorktreeId,
                    rootPath: URL(fileURLWithPath: "/tmp/stripe-0-\(UUID().uuidString)")
                )
            )
        )
        await bus.post(
            makeEnvelope(
                seq: 2,
                worktreeId: secondStripeWorktreeId,
                event: .worktreeRegistered(
                    worktreeId: secondStripeWorktreeId,
                    repoId: secondStripeWorktreeId,
                    rootPath: URL(fileURLWithPath: "/tmp/stripe-1-\(UUID().uuidString)")
                )
            )
        )

        let initialSnapshotsArrived = await waitUntil {
            let firstSnapshotCount = await observed.snapshotCount(for: firstStripeWorktreeId)
            let secondSnapshotCount = await observed.snapshotCount(for: secondStripeWorktreeId)
            return firstSnapshotCount == 1 && secondSnapshotCount == 1
        }
        #expect(initialSnapshotsArrived)
        await clock.waitForPendingSleepCount(atLeast: 1)

        clock.advance(by: .milliseconds(120))
        let firstStripeRefreshed = await waitUntil {
            await observed.snapshotCount(for: firstStripeWorktreeId) == 2
        }
        #expect(firstStripeRefreshed)
        for _ in 0..<300 {
            await Task.yield()
        }
        #expect(await observed.snapshotCount(for: secondStripeWorktreeId) == 1)

        await clock.waitForPendingSleepCount(atLeast: 1)
        clock.advance(by: .milliseconds(120))
        let secondStripeRefreshed = await waitUntil {
            await observed.snapshotCount(for: secondStripeWorktreeId) == 2
        }
        #expect(secondStripeRefreshed)

        await actor.shutdown()
        collectionTask.cancel()
    }

    @Test("active worktree periodic refresh bypasses background stripe")
    func activeWorktreePeriodicRefreshBypassesBackgroundStripe() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let policy = AppPolicies.GitRefresh.Policy(
            activeCadence: .milliseconds(120),
            backgroundStripeCount: 2,
            maxConcurrentStatusComputes: 4
        )
        let calls = CallCounter()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            let callNumber = await calls.increment()
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: callNumber, staged: 0, untracked: 0),
                branch: "main",
                origin: nil
            )
        }
        let actor = GitWorkingDirectoryProjector(
            bus: bus,
            gitWorkingTreeProvider: provider,
            coalescingWindow: .zero,
            periodicRefreshInterval: policy.activeCadence,
            sleepClock: clock,
            refreshPolicy: policy
        )

        let observed = ObservedGitEvents()
        let collectionTask = await startCollection(on: bus, observed: observed)
        await actor.start()

        let activeWorktreeId = worktreeId(forBackgroundStripe: 1, policy: policy)
        let inactiveWorktreeId = worktreeId(
            forBackgroundStripe: 1,
            policy: policy,
            excluding: [activeWorktreeId]
        )
        let inactiveRootPath = URL(fileURLWithPath: "/tmp/inactive-stripe-\(UUID().uuidString)")
        await bus.post(
            makeEnvelope(
                seq: 1,
                worktreeId: activeWorktreeId,
                event: .worktreeRegistered(
                    worktreeId: activeWorktreeId,
                    repoId: activeWorktreeId,
                    rootPath: URL(fileURLWithPath: "/tmp/active-stripe-\(UUID().uuidString)")
                )
            )
        )
        await bus.post(
            makeEnvelope(
                seq: 2,
                worktreeId: inactiveWorktreeId,
                event: .worktreeRegistered(
                    worktreeId: inactiveWorktreeId,
                    repoId: inactiveWorktreeId,
                    rootPath: inactiveRootPath
                )
            )
        )

        let initialSnapshotsArrived = await waitUntil {
            let activeCount = await observed.snapshotCount(for: activeWorktreeId)
            let inactiveCount = await observed.snapshotCount(for: inactiveWorktreeId)
            return activeCount == 1 && inactiveCount == 1
        }
        #expect(initialSnapshotsArrived)

        await actor.setActivity(worktreeId: activeWorktreeId, isActiveInApp: true)
        let activityRefreshArrived = await waitUntil {
            await observed.snapshotCount(for: activeWorktreeId) == 2
        }
        #expect(activityRefreshArrived)

        await clock.waitForPendingSleepCount(atLeast: 1)
        clock.advance(by: policy.activeCadence)
        let activeRefreshedOnNonMatchingBackgroundStripe = await waitUntil {
            await observed.snapshotCount(for: activeWorktreeId) == 3
        }
        #expect(activeRefreshedOnNonMatchingBackgroundStripe)
        #expect(await observed.snapshotCount(for: inactiveWorktreeId) == 1)

        await actor.shutdown()
        collectionTask.cancel()
    }

    @Test("topology assertion recovers dropped registration envelope")
    func topologyAssertionRecoversDroppedRegistrationEnvelope() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let calls = CallCounter()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            _ = await calls.increment()
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                branch: "asserted",
                origin: nil
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
        let rootPath = URL(fileURLWithPath: "/tmp/topology-assert-\(UUID().uuidString)")
        await actor.assertTopology(
            FilesystemTopologyAssertion(
                generation: 1,
                contextsByWorktreeId: [
                    worktreeId: WorktreeFilesystemContext(repoId: worktreeId, rootPath: rootPath)
                ]
            )
        )

        let assertionProducedSnapshot = await waitUntil {
            await observed.latestSnapshot(for: worktreeId)?.branch == "asserted"
        }
        #expect(assertionProducedSnapshot)
        #expect(await calls.value() == 1)

        await actor.shutdown()
        collectionTask.cancel()
    }

    @Test("registration followed by identical topology assertion is idempotent")
    func registrationFollowedByIdenticalTopologyAssertionIsIdempotent() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let calls = CallCounter()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            _ = await calls.increment()
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                branch: "registered",
                origin: nil
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
        let rootPath = URL(fileURLWithPath: "/tmp/register-then-assert-\(UUID().uuidString)")
        await bus.post(
            makeEnvelope(
                seq: 1,
                worktreeId: worktreeId,
                event: .worktreeRegistered(worktreeId: worktreeId, repoId: worktreeId, rootPath: rootPath)
            )
        )

        let registrationSnapshotArrived = await waitUntil {
            await observed.snapshotCount(for: worktreeId) == 1
        }
        #expect(registrationSnapshotArrived)

        await actor.assertTopology(
            FilesystemTopologyAssertion(
                generation: 1,
                contextsByWorktreeId: [
                    worktreeId: WorktreeFilesystemContext(repoId: worktreeId, rootPath: rootPath)
                ]
            )
        )
        for _ in 0..<300 {
            await Task.yield()
        }
        #expect(await calls.value() == 1)
        #expect(await observed.snapshotCount(for: worktreeId) == 1)

        await actor.shutdown()
        collectionTask.cancel()
    }

    @Test("context change cancels in-flight compute before stale snapshot emit")
    func contextChangeCancelsInFlightComputeBeforeStaleSnapshotEmit() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let gate = AsyncGate()
        let callOrder = CallOrderRecorder()
        let provider = StubGitWorkingTreeStatusProvider { rootPath in
            let label = rootPath.lastPathComponent
            await callOrder.record(label)
            await gate.waitUntilOpen()
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                branch: label,
                origin: nil
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
        let oldRootPath = URL(fileURLWithPath: "/tmp/old-root-\(UUID().uuidString)")
        let newRootPath = URL(fileURLWithPath: "/tmp/new-root-\(UUID().uuidString)")
        await bus.post(
            makeEnvelope(
                seq: 1,
                worktreeId: worktreeId,
                event: .worktreeRegistered(worktreeId: worktreeId, repoId: worktreeId, rootPath: oldRootPath)
            )
        )
        let oldComputeStarted = await waitUntil {
            let labels = await callOrder.labels
            return labels.contains { $0.contains("old-root") }
        }
        #expect(oldComputeStarted)

        await actor.assertTopology(
            FilesystemTopologyAssertion(
                generation: 1,
                contextsByWorktreeId: [
                    worktreeId: WorktreeFilesystemContext(repoId: worktreeId, rootPath: newRootPath)
                ]
            )
        )
        let newComputeStarted = await waitUntil {
            let labels = await callOrder.labels
            return labels.contains { $0.contains("new-root") }
        }
        #expect(newComputeStarted)

        await gate.open()
        let newSnapshotArrived = await waitUntil {
            await observed.latestSnapshot(for: worktreeId)?.rootPath == newRootPath
        }
        #expect(newSnapshotArrived)
        #expect(await observed.snapshotCount(for: worktreeId) == 1)

        await actor.shutdown()
        collectionTask.cancel()
    }

    @Test("stale registration envelope after topology removal does not resurrect worktree")
    func staleRegistrationEnvelopeAfterTopologyRemovalDoesNotResurrectWorktree() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let calls = CallCounter()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            _ = await calls.increment()
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                branch: "stale",
                origin: nil
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
        let rootPath = URL(fileURLWithPath: "/tmp/topology-stale-\(UUID().uuidString)")
        await actor.assertTopology(
            FilesystemTopologyAssertion(
                generation: 1,
                contextsByWorktreeId: [
                    worktreeId: WorktreeFilesystemContext(repoId: worktreeId, rootPath: rootPath)
                ]
            )
        )
        let firstSnapshotArrived = await waitUntil {
            await observed.snapshotCount(for: worktreeId) == 1
        }
        #expect(firstSnapshotArrived)

        await actor.assertTopology(
            FilesystemTopologyAssertion(generation: 2, contextsByWorktreeId: [:])
        )
        await bus.post(
            makeEnvelope(
                seq: 10,
                worktreeId: worktreeId,
                event: .worktreeRegistered(worktreeId: worktreeId, repoId: worktreeId, rootPath: rootPath)
            )
        )

        for _ in 0..<300 {
            await Task.yield()
        }
        #expect(await calls.value() == 1)
        #expect(await observed.snapshotCount(for: worktreeId) == 1)

        await actor.shutdown()
        collectionTask.cancel()
    }

    @Test("duplicate topology assertion is idempotent")
    func duplicateTopologyAssertionIsIdempotent() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let calls = CallCounter()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            _ = await calls.increment()
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                branch: "idempotent",
                origin: nil
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
        let assertion = FilesystemTopologyAssertion(
            generation: 1,
            contextsByWorktreeId: [
                worktreeId: WorktreeFilesystemContext(
                    repoId: worktreeId,
                    rootPath: URL(fileURLWithPath: "/tmp/topology-idempotent-\(UUID().uuidString)")
                )
            ]
        )
        await actor.assertTopology(assertion)
        let firstSnapshotArrived = await waitUntil {
            await observed.snapshotCount(for: worktreeId) == 1
        }
        #expect(firstSnapshotArrived)

        await actor.assertTopology(assertion)
        for _ in 0..<300 {
            await Task.yield()
        }
        #expect(await calls.value() == 1)
        #expect(await observed.snapshotCount(for: worktreeId) == 1)

        await actor.shutdown()
        collectionTask.cancel()
    }

    @Test("worktree unregistration cancels and clears state")
    func worktreeUnregistrationCancelsAndClearsState() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let gate = AsyncGate()
        let cancellationReceipt = AsyncReceipt()
        let providerReleaseReceipt = AsyncReceipt()
        let calls = CallCounter()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            _ = await calls.increment()
            await withTaskCancellationHandler {
                await gate.waitUntilOpen()
            } onCancel: {
                Task { await cancellationReceipt.signal() }
            }
            await providerReleaseReceipt.signal()
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 4, staged: 0, untracked: 1),
                branch: "cleanup",
                origin: nil
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

        await cancellationReceipt.wait()
        await gate.open()
        await providerReleaseReceipt.wait()

        #expect(await calls.value() == 1)
        #expect(await observed.snapshotCount(for: worktreeId) == 0)
        #expect(await observed.branchEventCount(for: worktreeId) == 0)

        await actor.shutdown()
        collectionTask.cancel()
    }

    @Test("shutdown while provider is in-flight does not emit stale snapshot")
    func shutdownWhileProviderIsInFlightDoesNotEmitStaleSnapshot() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let gate = AsyncGate()
        let calls = CallCounter()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            _ = await calls.increment()
            await gate.waitUntilOpen()
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                branch: "main",
                origin: nil
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
        let bus = EventBus<RuntimeEnvelope>()
        let calls = CallCounter()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            let callNumber = await calls.increment()
            let branch = callNumber == 1 ? "main" : "feature/split"
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: callNumber, staged: 0, untracked: 0),
                branch: branch,
                origin: nil
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

    @Test("branchChanged emits when branchless snapshot becomes a branch")
    func branchChangedEmitsWhenBranchlessSnapshotBecomesBranch() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let calls = CallCounter()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            let callNumber = await calls.increment()
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: callNumber, staged: 0, untracked: 0),
                branch: callNumber == 1 ? nil : "main",
                origin: nil
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
        let rootPath = URL(fileURLWithPath: "/tmp/branchless-change-\(UUID().uuidString)")
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
        #expect(branchEvent?.0.isEmpty == true)
        #expect(branchEvent?.1 == "main")

        await actor.shutdown()
        collectionTask.cancel()
    }

    @Test("projector emits originChanged when origin differs from last known repo origin")
    func emitsOriginChangedWhenOriginChanges() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let repoId = UUID()
        let worktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/origin-change-\(UUID().uuidString)")
        let calls = CallCounter()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            let call = await calls.increment()
            let origin = call == 1 ? "git@github.com:acme/repo.git" : "git@github.com:acme/repo-2.git"
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
                branch: "main",
                origin: origin
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

        await bus.post(
            makeEnvelope(
                seq: 1,
                worktreeId: worktreeId,
                event: .worktreeRegistered(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)
            )
        )

        let firstOriginEvent = await waitUntil {
            await observed.originEventCount(for: repoId) == 1
        }
        #expect(firstOriginEvent)

        await bus.post(
            makeFilesChangedEnvelope(
                seq: 2,
                worktreeId: worktreeId,
                repoId: repoId,
                rootPath: rootPath,
                batchSeq: 1,
                paths: [".git/config"]
            )
        )

        let emittedTwoOriginEvents = await waitUntil {
            await observed.originEventCount(for: repoId) >= 2
        }
        #expect(emittedTwoOriginEvents)
        let latestOrigin = await observed.latestOriginEvent(for: repoId)
        #expect(latestOrigin?.0 == "git@github.com:acme/repo.git")
        #expect(latestOrigin?.1 == "git@github.com:acme/repo-2.git")

        await actor.shutdown()
        collectionTask.cancel()
    }

    @Test("projector tracks origin per repo and suppresses duplicates across worktrees")
    func suppressesDuplicateOriginEventsAcrossWorktreesInSameRepo() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let repoId = UUID()
        let firstWorktreeId = UUID()
        let secondWorktreeId = UUID()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
                branch: "main",
                origin: "git@github.com:acme/repo.git"
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

        await bus.post(
            makeEnvelope(
                seq: 1,
                worktreeId: firstWorktreeId,
                event: .worktreeRegistered(
                    worktreeId: firstWorktreeId,
                    repoId: repoId,
                    rootPath: URL(fileURLWithPath: "/tmp/repo-\(UUID().uuidString)-a")
                )
            )
        )
        await bus.post(
            makeEnvelope(
                seq: 2,
                worktreeId: secondWorktreeId,
                event: .worktreeRegistered(
                    worktreeId: secondWorktreeId,
                    repoId: repoId,
                    rootPath: URL(fileURLWithPath: "/tmp/repo-\(UUID().uuidString)-b")
                )
            )
        )

        let emittedSingleOriginEvent = await waitUntil {
            await observed.originEventCount(for: repoId) == 1
        }
        #expect(emittedSingleOriginEvent)

        await actor.shutdown()
        collectionTask.cancel()
    }

    @Test("projector only emits originChanged for registration and git config changes")
    func onlyEmitsOriginChangedForRegistrationAndGitConfigChanges() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let repoId = UUID()
        let worktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/origin-filter-\(UUID().uuidString)")
        let calls = CallCounter()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            let call = await calls.increment()
            let origin = call == 1 ? "git@github.com:acme/repo.git" : "git@github.com:acme/repo-2.git"
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
                branch: "main",
                origin: origin
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

        await bus.post(
            makeEnvelope(
                seq: 1,
                worktreeId: worktreeId,
                event: .worktreeRegistered(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)
            )
        )
        let firstOriginEvent = await waitUntil {
            await observed.originEventCount(for: repoId) == 1
        }
        #expect(firstOriginEvent)

        await bus.post(
            makeFilesChangedEnvelope(
                seq: 2,
                worktreeId: worktreeId,
                repoId: repoId,
                rootPath: rootPath,
                batchSeq: 1,
                paths: ["Sources/File.swift"]
            )
        )
        let nonConfigBatchProcessedWithoutOriginChange = await waitUntil {
            let callCount = await calls.value()
            let originCount = await observed.originEventCount(for: repoId)
            return callCount >= 2 && originCount == 1
        }
        #expect(nonConfigBatchProcessedWithoutOriginChange)
        #expect(await observed.originEventCount(for: repoId) == 1)

        await bus.post(
            makeFilesChangedEnvelope(
                seq: 3,
                worktreeId: worktreeId,
                repoId: repoId,
                rootPath: rootPath,
                batchSeq: 2,
                paths: [".git/config"]
            )
        )
        let secondOriginEvent = await waitUntil {
            await observed.originEventCount(for: repoId) == 2
        }
        #expect(secondOriginEvent)

        await actor.shutdown()
        collectionTask.cancel()
    }

    @Test("projector emits one initial empty origin event without locking retry state")
    func emitsInitialEmptyOriginEventWithoutLockingRetryState() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let repoId = UUID()
        let worktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/origin-none-\(UUID().uuidString)")
        let callCounter = CallCounter()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            _ = await callCounter.increment()
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
                branch: "main",
                origin: nil
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

        await bus.post(
            makeEnvelope(
                seq: 1,
                worktreeId: worktreeId,
                event: .worktreeRegistered(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)
            )
        )

        // First registration probes origin and emits exactly one local-origin signal.
        let emittedInitialOriginSignal = await waitUntil {
            let calls = await callCounter.value()
            let originEvents = await observed.originEventCount(for: repoId)
            return calls >= 1 && originEvents == 1
        }
        #expect(emittedInitialOriginSignal)
        let initialEvent = await observed.latestOriginEvent(for: repoId)
        #expect(initialEvent?.0.isEmpty == true)
        #expect(initialEvent?.1.isEmpty == true)

        await actor.shutdown()
        collectionTask.cancel()
    }

    @Test("projector retries origin discovery after initial empty result")
    func retriesOriginDiscoveryAfterInitialEmptyResult() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let repoId = UUID()
        let worktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/origin-retry-\(UUID().uuidString)")
        let callCounter = CallCounter()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            let call = await callCounter.increment()
            let origin = call >= 2 ? "git@github.com:acme/repo.git" : nil
            return GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
                branch: "main",
                origin: origin
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

        await bus.post(
            makeEnvelope(
                seq: 1,
                worktreeId: worktreeId,
                event: .worktreeRegistered(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)
            )
        )

        let registrationProcessed = await waitUntil {
            let calls = await callCounter.value()
            let originEvents = await observed.originEventCount(for: repoId)
            return calls >= 1 && originEvents == 1
        }
        #expect(registrationProcessed)

        await bus.post(
            makeFilesChangedEnvelope(
                seq: 2,
                worktreeId: worktreeId,
                repoId: repoId,
                rootPath: rootPath,
                batchSeq: 1,
                paths: [".git/config"]
            )
        )

        let emittedOriginAfterRetry = await waitUntil {
            await observed.originEventCount(for: repoId) == 2
        }
        #expect(emittedOriginAfterRetry)
        let event = await observed.latestOriginEvent(for: repoId)
        #expect(event?.0.isEmpty == true)
        #expect(event?.1 == "git@github.com:acme/repo.git")

        await actor.shutdown()
        collectionTask.cancel()
    }

    @Test("git internal-only filesChanged event still triggers git snapshot projection")
    func gitInternalOnlyFilesChangedEventStillTriggersSnapshot() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let provider = StubGitWorkingTreeStatusProvider { _ in
            GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                branch: "main",
                origin: nil
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
        on bus: EventBus<RuntimeEnvelope>,
        observed: ObservedGitEvents
    ) async -> Task<Void, Never> {
        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        return Task {
            for await envelope in stream {
                await observed.record(envelope)
            }
        }
    }

    private func makeFilesChangedEnvelope(
        seq: UInt64,
        worktreeId: UUID,
        repoId: UUID? = nil,
        rootPath: URL,
        batchSeq: UInt64,
        paths: [String] = ["Sources/File.swift"],
        containsGitInternalChanges: Bool = false,
        suppressedIgnoredPathCount: Int = 0,
        suppressedGitInternalPathCount: Int = 0
    ) -> RuntimeEnvelope {
        makeEnvelope(
            seq: seq,
            worktreeId: worktreeId,
            event: .filesChanged(
                changeset: FileChangeset(
                    worktreeId: worktreeId,
                    repoId: repoId ?? worktreeId,
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
    ) -> RuntimeEnvelope {
        switch event {
        case .worktreeRegistered(let registeredWorktreeId, let repoId, let rootPath):
            return .system(
                SystemEnvelope.test(
                    event: .topology(
                        .worktreeRegistered(
                            worktreeId: registeredWorktreeId,
                            repoId: repoId,
                            rootPath: rootPath
                        )
                    ),
                    source: .builtin(.filesystemWatcher),
                    seq: seq
                )
            )
        case .worktreeUnregistered(let unregisteredWorktreeId, let repoId):
            return .system(
                SystemEnvelope.test(
                    event: .topology(
                        .worktreeUnregistered(
                            worktreeId: unregisteredWorktreeId,
                            repoId: repoId
                        )
                    ),
                    source: .builtin(.filesystemWatcher),
                    seq: seq
                )
            )
        case .filesChanged(let changeset):
            return .worktree(
                WorktreeEnvelope.test(
                    event: .filesystem(.filesChanged(changeset: changeset)),
                    repoId: changeset.repoId,
                    worktreeId: changeset.worktreeId,
                    source: .system(.builtin(.filesystemWatcher)),
                    seq: seq
                )
            )
        case .gitSnapshotChanged(let snapshot):
            return .worktree(
                WorktreeEnvelope.test(
                    event: .gitWorkingDirectory(.snapshotChanged(snapshot: snapshot)),
                    repoId: snapshot.repoId,
                    worktreeId: snapshot.worktreeId,
                    source: .system(.builtin(.filesystemWatcher)),
                    seq: seq
                )
            )
        case .diffAvailable(let diffId, let changedWorktreeId, let repoId):
            return .worktree(
                WorktreeEnvelope.test(
                    event: .gitWorkingDirectory(
                        .diffAvailable(
                            diffId: diffId,
                            worktreeId: changedWorktreeId,
                            repoId: repoId
                        )
                    ),
                    repoId: repoId,
                    worktreeId: changedWorktreeId,
                    source: .system(.builtin(.filesystemWatcher)),
                    seq: seq
                )
            )
        case .branchChanged(let changedWorktreeId, let repoId, let from, let to):
            return .worktree(
                WorktreeEnvelope.test(
                    event: .gitWorkingDirectory(
                        .branchChanged(
                            worktreeId: changedWorktreeId,
                            repoId: repoId,
                            from: from,
                            to: to
                        )
                    ),
                    repoId: repoId,
                    worktreeId: changedWorktreeId,
                    source: .system(.builtin(.filesystemWatcher)),
                    seq: seq
                )
            )
        }
    }

    private func waitUntil(
        maxTurns: Int = 10_000,
        condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        for _ in 0..<maxTurns {
            if await condition() {
                return true
            }
            await Task.yield()
        }
        return await condition()
    }

    private func waitUntilYielding(
        maxTurns: Int = 10_000,
        condition: @escaping @Sendable () -> Bool
    ) async -> Bool {
        for _ in 0..<maxTurns {
            if condition() {
                return true
            }
            await Task.yield()
        }
        return condition()
    }

    private func worktreeId(
        forBackgroundStripe expectedStripe: Int,
        policy: AppPolicies.GitRefresh.Policy,
        excluding excludedWorktreeIds: Set<UUID> = []
    ) -> UUID {
        for suffix in 0..<10_000 {
            let uuidString = String(format: "00000000-0000-0000-0000-%012X", suffix)
            guard let candidate = UUID(uuidString: uuidString) else { continue }
            guard !excludedWorktreeIds.contains(candidate) else { continue }
            if policy.backgroundStripe(for: candidate) == expectedStripe {
                return candidate
            }
        }
        fatalError("Unable to find deterministic UUID for background stripe \(expectedStripe)")
    }
}

private actor ObservedGitEvents {
    private var snapshotsByWorktreeId: [UUID: [GitWorkingTreeSnapshot]] = [:]
    private var branchEventsByWorktreeId: [UUID: [(String, String)]] = [:]
    private var originEventsByRepoId: [UUID: [(String, String)]] = [:]

    func record(_ envelope: RuntimeEnvelope) {
        guard case .worktree(let worktreeEnvelope) = envelope else { return }
        guard case .gitWorkingDirectory(let gitEvent) = worktreeEnvelope.event else { return }
        guard let worktreeId = worktreeEnvelope.worktreeId else { return }

        switch gitEvent {
        case .snapshotChanged(let snapshot):
            snapshotsByWorktreeId[worktreeId, default: []].append(snapshot)
        case .branchChanged(let eventWorktreeId, _, let from, let to):
            guard eventWorktreeId == worktreeId else { return }
            branchEventsByWorktreeId[worktreeId, default: []].append((from, to))
        case .originChanged(let repoId, let from, let to):
            originEventsByRepoId[repoId, default: []].append((from, to))
        case .originUnavailable(let repoId):
            originEventsByRepoId[repoId, default: []].append(("", ""))
        case .worktreeDiscovered, .worktreeRemoved, .diffAvailable:
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

    func originEventCount(for repoId: UUID) -> Int {
        originEventsByRepoId[repoId]?.count ?? 0
    }

    func latestOriginEvent(for repoId: UUID) -> (String, String)? {
        originEventsByRepoId[repoId]?.last
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

private actor AsyncReceipt {
    private var wasSignaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !wasSignaled else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        guard !wasSignaled else { return }
        wasSignaled = true
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

private actor CallOrderRecorder {
    private var recordedLabels: [String] = []

    var labels: [String] {
        recordedLabels
    }

    func record(_ label: String) {
        recordedLabels.append(label)
    }
}
