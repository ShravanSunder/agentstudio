import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct FilesystemActorTests {
    @Test("older scheduler snapshot cannot overwrite a newer logical-debt publication")
    func olderSchedulerSnapshotCannotOverwriteNewerLogicalDebtPublication() async throws {
        let traceRuntime = makeFilesystemLogicalDebtTraceRuntime()
        let recorder = AgentStudioPerformanceTraceRecorder(
            traceRuntime: traceRuntime,
            processMemorySampleWait: { false }
        )
        let clock = TestPushClock()
        let actor = FilesystemActor(
            bus: EventBus<RuntimeEnvelope>(),
            fseventStreamClient: ControllableFSEventStreamClient(),
            sleepClock: clock,
            debounceWindow: .seconds(1),
            maxFlushLatency: .seconds(2),
            performanceTraceRecorder: recorder
        )
        let worktreeID = UUIDv7.generate()
        await actor.register(
            worktreeId: worktreeID,
            repoId: worktreeID,
            rootPath: URL(
                fileURLWithPath: "/tmp/logical-debt-ordering-\(UUIDv7.generate().uuidString)"
            )
        )
        let snapshotGate = LogicalDebtSnapshotGate()
        let olderPublication = Task {
            await actor.recordLogicalDebtSnapshotIfChanged(
                watchedFolderStateSnapshot: { await snapshotGate.waitForRelease() }
            )
        }
        await snapshotGate.waitUntilEntered()

        await actor.enqueueRawPaths(worktreeId: worktreeID, paths: ["Sources/Fresher.swift"])
        let newerSnapshot = await actor.lastRecordedLogicalDebtSnapshot
        #expect(newerSnapshot?.logicalDebtCount == 2)

        await snapshotGate.release()
        await olderPublication.value
        #expect(await actor.lastRecordedLogicalDebtSnapshot == newerSnapshot)

        await actor.shutdown()
        try await recorder.drain()
    }

    @Test("register emits worktreeRegistered fact")
    func registerEmitsWorktreeRegisteredFact() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let actor = makeActor(bus: bus)

        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        var iterator = stream.makeAsyncIterator()

        let worktreeId = UUID()
        let repoId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/register-\(UUID().uuidString)")
        await actor.register(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)

        let envelope = try #require(await iterator.next())
        guard case .system(let systemEnvelope) = envelope else {
            Issue.record("Expected system envelope")
            return
        }
        guard
            case .topology(
                .worktreeRegistered(let registeredWorktreeId, let registeredRepoId, let registeredRootPath)) =
                systemEnvelope.event
        else {
            Issue.record("Expected worktreeRegistered topology event")
            return
        }

        #expect(registeredWorktreeId == worktreeId)
        #expect(registeredRepoId == repoId)
        #expect(registeredRootPath == rootPath)
        #expect(systemEnvelope.source == .builtin(.filesystemWatcher))

        await actor.shutdown()
    }

    @Test("unregister emits worktreeUnregistered fact")
    func unregisterEmitsWorktreeUnregisteredFact() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let actor = makeActor(bus: bus)

        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        var iterator = stream.makeAsyncIterator()

        let worktreeId = UUID()
        let repoId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/unregister-\(UUID().uuidString)")
        await actor.register(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)
        _ = try #require(await iterator.next())  // worktreeRegistered

        await actor.unregister(worktreeId: worktreeId)
        let envelope = try #require(await iterator.next())
        guard case .system(let systemEnvelope) = envelope else {
            Issue.record("Expected system envelope")
            return
        }
        guard
            case .topology(.worktreeUnregistered(let unregisteredWorktreeId, let unregisteredRepoId)) = systemEnvelope
                .event
        else {
            Issue.record("Expected worktreeUnregistered topology event")
            return
        }

        #expect(unregisteredWorktreeId == worktreeId)
        #expect(unregisteredRepoId == repoId)
        #expect(systemEnvelope.source == .builtin(.filesystemWatcher))

        await actor.shutdown()
    }

    @Test("deepest ownership dedupes nested roots")
    func deepestOwnershipDedupesNestedRoots() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let actor = makeActor(bus: bus)

        let parentId = UUID()
        let childId = UUID()
        await actor.register(worktreeId: parentId, repoId: parentId, rootPath: URL(fileURLWithPath: "/tmp/repo"))
        await actor.register(worktreeId: childId, repoId: childId, rootPath: URL(fileURLWithPath: "/tmp/repo/nested"))

        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        var iterator = stream.makeAsyncIterator()

        await actor.enqueueRawPaths(
            worktreeId: parentId,
            paths: ["nested/file.swift", "nested/file.swift"]
        )

        let envelope = try #require(await iterator.next())
        let changeset = try #require(filesChangedChangeset(from: envelope))
        #expect(changeset.worktreeId == childId)
        #expect(changeset.paths == ["file.swift"])

        await actor.shutdown()
    }

    @Test("nested root routing emits one owner event per path without duplication")
    func nestedRootRoutingEmitsSingleOwnerPerPath() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let actor = makeActor(bus: bus)

        let parentId = UUID()
        let childId = UUID()
        await actor.register(worktreeId: parentId, repoId: parentId, rootPath: URL(fileURLWithPath: "/tmp/repo"))
        await actor.register(worktreeId: childId, repoId: childId, rootPath: URL(fileURLWithPath: "/tmp/repo/nested"))

        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        var iterator = stream.makeAsyncIterator()

        await actor.enqueueRawPaths(
            worktreeId: parentId,
            paths: ["README.md", "nested/src/feature.swift"]
        )

        let firstEnvelope = try #require(await iterator.next())
        let secondEnvelope = try #require(await iterator.next())
        let firstChangeset = try #require(filesChangedChangeset(from: firstEnvelope))
        let secondChangeset = try #require(filesChangedChangeset(from: secondEnvelope))

        #expect(firstChangeset.worktreeId == parentId)
        #expect(firstChangeset.paths == ["README.md"])
        #expect(secondChangeset.worktreeId == childId)
        #expect(secondChangeset.paths == ["src/feature.swift"])

        await actor.shutdown()
    }

    @Test("active-in-app priority order beats sidebar-only")
    func activeInAppPriorityWinsQueueOrder() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let actor = makeActor(bus: bus)

        let sidebarOnlyWorktreeId = UUID()
        let activeWorktreeId = UUID()
        await actor.register(
            worktreeId: sidebarOnlyWorktreeId, repoId: sidebarOnlyWorktreeId,
            rootPath: URL(fileURLWithPath: "/tmp/sidebar"))
        await actor.register(
            worktreeId: activeWorktreeId, repoId: activeWorktreeId, rootPath: URL(fileURLWithPath: "/tmp/active"))
        await actor.setActivity(worktreeId: activeWorktreeId, isActiveInApp: true)
        await actor.setActivity(worktreeId: sidebarOnlyWorktreeId, isActiveInApp: false)
        await actor.setActivePaneWorktree(worktreeId: activeWorktreeId)

        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        var iterator = stream.makeAsyncIterator()

        await actor.enqueueRawPaths(worktreeId: sidebarOnlyWorktreeId, paths: ["README.md"])
        await actor.enqueueRawPaths(worktreeId: activeWorktreeId, paths: ["src/main.swift"])

        let firstEnvelope = try #require(await iterator.next())
        let firstChangeset = try #require(filesChangedChangeset(from: firstEnvelope))
        #expect(firstChangeset.worktreeId == activeWorktreeId)

        await actor.shutdown()
    }

    @Test("priority ordering is focused active pane, then active in app, then sidebar-only")
    func priorityOrderingFocusedThenActiveThenSidebar() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let actor = makeActor(bus: bus)

        let basePath = "/tmp/priority-\(UUID().uuidString)"
        let sidebarWorktreeId = UUID()
        let activeWorktreeId = UUID()
        let focusedWorktreeId = UUID()
        await actor.register(
            worktreeId: sidebarWorktreeId, repoId: sidebarWorktreeId, rootPath: URL(fileURLWithPath: basePath))
        await actor.register(
            worktreeId: activeWorktreeId, repoId: activeWorktreeId, rootPath: URL(fileURLWithPath: "\(basePath)/active")
        )
        await actor.register(
            worktreeId: focusedWorktreeId,
            repoId: focusedWorktreeId,
            rootPath: URL(fileURLWithPath: "\(basePath)/active/focused")
        )

        await actor.setActivity(worktreeId: sidebarWorktreeId, isActiveInApp: false)
        await actor.setActivity(worktreeId: activeWorktreeId, isActiveInApp: true)
        await actor.setActivity(worktreeId: focusedWorktreeId, isActiveInApp: true)
        await actor.setActivePaneWorktree(worktreeId: focusedWorktreeId)

        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        var iterator = stream.makeAsyncIterator()

        // Route all tiers in one ingress call so queue order depends only on priority keys.
        await actor.enqueueRawPaths(
            worktreeId: sidebarWorktreeId,
            paths: ["sidebar.txt", "active/active.txt", "active/focused/focused.txt"]
        )

        let firstEnvelope = try #require(await iterator.next())
        let secondEnvelope = try #require(await iterator.next())
        let thirdEnvelope = try #require(await iterator.next())

        let firstChangeset = try #require(filesChangedChangeset(from: firstEnvelope))
        let secondChangeset = try #require(filesChangedChangeset(from: secondEnvelope))
        let thirdChangeset = try #require(filesChangedChangeset(from: thirdEnvelope))

        #expect(firstChangeset.worktreeId == focusedWorktreeId)
        #expect(secondChangeset.worktreeId == activeWorktreeId)
        #expect(thirdChangeset.worktreeId == sidebarWorktreeId)

        await actor.shutdown()
    }

    @Test("filesChanged routes through worktree envelope from filesystem watcher")
    func filesChangedRoutingContract() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let actor = makeActor(bus: bus)

        let worktreeId = UUID()
        await actor.register(
            worktreeId: worktreeId, repoId: worktreeId, rootPath: URL(fileURLWithPath: "/tmp/contract"))

        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        var iterator = stream.makeAsyncIterator()

        await actor.enqueueRawPaths(worktreeId: worktreeId, paths: ["Sources/App.swift"])

        let envelope = try #require(await iterator.next())
        guard case .worktree(let worktreeEnvelope) = envelope else {
            Issue.record("Expected worktree envelope")
            return
        }
        #expect(worktreeEnvelope.source == .system(.builtin(.filesystemWatcher)))
        #expect(worktreeEnvelope.worktreeId == worktreeId)
        #expect(worktreeEnvelope.repoId == worktreeId)

        let changeset = try #require(filesChangedChangeset(from: envelope))
        #expect(changeset.worktreeId == worktreeId)
        #expect(changeset.paths == ["Sources/App.swift"])

        await actor.shutdown()
    }

    @Test("large path bursts split into fixed-size ordered filesChanged batches")
    func largeBurstSplitsIntoBoundedSortedBatches() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let actor = makeActor(bus: bus)

        let worktreeId = UUID()
        await actor.register(
            worktreeId: worktreeId, repoId: worktreeId, rootPath: URL(fileURLWithPath: "/tmp/large-batch"))

        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        var iterator = stream.makeAsyncIterator()

        let batchLimit = FilesystemActor.maxPathsPerFilesChangedEvent
        let uniquePathCount = batchLimit * 2 + 17
        let descendingPaths = (0..<uniquePathCount).map { index in
            String(format: "src/%04d.swift", uniquePathCount - index)
        }
        let rawPaths = descendingPaths + ["src/0001.swift", "./src/0001.swift", "/src/0001.swift"]
        let expectedSortedPaths = Set(rawPaths.map(normalizedRelativePath)).sorted()
        let expectedChunkCount = (expectedSortedPaths.count + batchLimit - 1) / batchLimit

        await actor.enqueueRawPaths(worktreeId: worktreeId, paths: rawPaths)

        var receivedChangesets: [FileChangeset] = []
        for _ in 0..<expectedChunkCount {
            let envelope = try #require(await iterator.next())
            let changeset = try #require(filesChangedChangeset(from: envelope))
            receivedChangesets.append(changeset)
        }

        let flattenedPaths = receivedChangesets.flatMap(\.paths)
        let batchSequences = receivedChangesets.map(\.batchSeq)

        #expect(receivedChangesets.count == expectedChunkCount)
        #expect(receivedChangesets.allSatisfy { $0.paths.count <= batchLimit })
        #expect(flattenedPaths == expectedSortedPaths)
        #expect(batchSequences == Array(1...UInt64(expectedChunkCount)))

        await actor.shutdown()
    }

    @Test("debounce coalesces bursts and flushes once after debounce window")
    func debounceCoalescesBursts() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let actor = FilesystemActor(
            bus: bus,
            fseventStreamClient: ControllableFSEventStreamClient(),
            sleepClock: clock,
            debounceWindow: .milliseconds(60),
            maxFlushLatency: .seconds(1)
        )

        let observed = ObservedFilesystemChanges()
        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        let collectionTask = Task {
            for await envelope in stream {
                await observed.record(envelope)
            }
        }

        defer { collectionTask.cancel() }

        let worktreeId = UUID()
        await actor.register(
            worktreeId: worktreeId,
            repoId: worktreeId,
            rootPath: URL(fileURLWithPath: "/tmp/debounce-\(UUID().uuidString)")
        )

        await actor.enqueueRawPaths(worktreeId: worktreeId, paths: ["Sources/A.swift"])
        await actor.enqueueRawPaths(worktreeId: worktreeId, paths: ["Sources/B.swift"])

        await clock.waitForPendingSleepCount()
        clock.advance(by: .milliseconds(20))
        await Task.yield()
        #expect(await observed.filesChangedCount(for: worktreeId) == 0)

        clock.advance(by: .milliseconds(40))
        let changeset = await observed.next()
        #expect(changeset.worktreeId == worktreeId)
        #expect(Set(changeset.paths) == Set(["Sources/A.swift", "Sources/B.swift"]))

        await actor.shutdown()
    }

    @Test("logical debt retains drain custody until the accepted filesystem batch finishes")
    func logicalDebtRetainsDrainCustodyUntilBatchFinishes() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let actor = FilesystemActor(
            bus: bus,
            fseventStreamClient: ControllableFSEventStreamClient(),
            sleepClock: clock,
            debounceWindow: .milliseconds(60),
            maxFlushLatency: .seconds(1)
        )
        let observed = ObservedFilesystemChanges()
        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        let collectionTask = Task {
            for await envelope in stream {
                await observed.record(envelope)
            }
        }
        defer { collectionTask.cancel() }

        let worktreeId = UUID()
        await actor.register(
            worktreeId: worktreeId,
            repoId: worktreeId,
            rootPath: URL(fileURLWithPath: "/tmp/logical-debt-\(UUID().uuidString)")
        )
        await actor.enqueueRawPaths(worktreeId: worktreeId, paths: ["Sources/Accepted.swift"])
        await clock.waitForPendingSleepCount()

        let pendingSnapshot = await actor.logicalDebtSnapshot()
        #expect(pendingSnapshot.pendingWorktreeCount == 1)
        #expect(pendingSnapshot.drainTaskCount == 1)
        #expect(pendingSnapshot.logicalDebtCount == 2)

        clock.advance(by: .milliseconds(60))
        _ = await observed.next()
        let reachedZeroDebt = await waitUntilFilesystemLogicalDebt(actor, equals: 0)
        #expect(reachedZeroDebt)
        let finalSnapshot = await actor.logicalDebtSnapshot()
        #expect(finalSnapshot.pendingWorktreeCount == 0)
        #expect(finalSnapshot.drainTaskCount == 0)
        #expect(finalSnapshot.logicalDebtCount == 0)

        await actor.shutdown()
    }

    @Test("default debounce flushes an isolated change after 500 milliseconds of quiet")
    func defaultDebounceFlushesIsolatedChangeAfterQuietWindow() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let actor = FilesystemActor(
            bus: bus,
            fseventStreamClient: ControllableFSEventStreamClient(),
            sleepClock: clock
        )

        let observed = ObservedFilesystemChanges()
        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        let collectionTask = Task {
            for await envelope in stream {
                await observed.record(envelope)
            }
        }
        defer { collectionTask.cancel() }

        let worktreeId = UUID()
        await actor.register(
            worktreeId: worktreeId,
            repoId: worktreeId,
            rootPath: URL(fileURLWithPath: "/tmp/default-debounce-\(UUID().uuidString)")
        )
        await actor.enqueueRawPaths(worktreeId: worktreeId, paths: ["Sources/Isolated.swift"])

        await clock.waitForPendingSleepCount()
        clock.advance(by: .milliseconds(499))
        await Task.yield()
        #expect(await observed.filesChangedCount(for: worktreeId) == 0)

        clock.advance(by: .milliseconds(1))
        let changeset = await observed.next()
        #expect(changeset.paths == ["Sources/Isolated.swift"])

        await actor.shutdown()
    }

    @Test("default maximum latency forces a flush after 10 seconds of continuous changes")
    func defaultMaximumLatencyForcesContinuousStormFlush() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let actor = FilesystemActor(
            bus: bus,
            fseventStreamClient: ControllableFSEventStreamClient(),
            sleepClock: clock
        )

        let observed = ObservedFilesystemChanges()
        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        let collectionTask = Task {
            for await envelope in stream {
                await observed.record(envelope)
            }
        }
        defer { collectionTask.cancel() }

        let worktreeId = UUID()
        await actor.register(
            worktreeId: worktreeId,
            repoId: worktreeId,
            rootPath: URL(fileURLWithPath: "/tmp/default-max-latency-\(UUID().uuidString)")
        )
        await actor.enqueueRawPaths(worktreeId: worktreeId, paths: ["Sources/Change-0.swift"])
        await clock.waitForPendingSleepCount()

        for changeIndex in 1...24 {
            clock.advance(by: .milliseconds(400))
            await actor.enqueueRawPaths(
                worktreeId: worktreeId,
                paths: ["Sources/Change-\(changeIndex).swift"]
            )
        }
        #expect(await observed.filesChangedCount(for: worktreeId) == 0)

        clock.advance(by: .milliseconds(400))
        let changeset = await observed.next()
        #expect(changeset.paths.count == 25)

        await actor.shutdown()
    }

    @Test("max latency flushes pending changes even when debounce keeps extending")
    func maxLatencyFlushesPendingChanges() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let actor = FilesystemActor(
            bus: bus,
            fseventStreamClient: ControllableFSEventStreamClient(),
            sleepClock: clock,
            debounceWindow: .milliseconds(250),
            maxFlushLatency: .milliseconds(120)
        )

        let observed = ObservedFilesystemChanges()
        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        let collectionTask = Task {
            for await envelope in stream {
                await observed.record(envelope)
            }
        }

        defer { collectionTask.cancel() }

        let worktreeId = UUID()
        await actor.register(
            worktreeId: worktreeId,
            repoId: worktreeId,
            rootPath: URL(fileURLWithPath: "/tmp/max-latency-\(UUID().uuidString)")
        )

        await actor.enqueueRawPaths(worktreeId: worktreeId, paths: ["Sources/First.swift"])
        await clock.waitForPendingSleepCount()
        clock.advance(by: .milliseconds(70))
        await Task.yield()
        #expect(await observed.filesChangedCount(for: worktreeId) == 0)
        await actor.enqueueRawPaths(worktreeId: worktreeId, paths: ["Sources/Second.swift"])

        await Task.yield()
        clock.advance(by: .milliseconds(50))
        let changeset = await observed.next()
        #expect(changeset.worktreeId == worktreeId)
        #expect(Set(changeset.paths) == Set(["Sources/First.swift", "Sources/Second.swift"]))

        await actor.shutdown()
    }

    @Test("shutdown cancels pending debounce drain and prevents delayed filesChanged emission")
    func shutdownCancelsPendingDrain() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let actor = FilesystemActor(
            bus: bus,
            fseventStreamClient: ControllableFSEventStreamClient(),
            sleepClock: clock,
            debounceWindow: .milliseconds(200),
            maxFlushLatency: .seconds(1)
        )

        let observed = ObservedFilesystemChanges()
        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        let collectionTask = Task {
            for await envelope in stream {
                await observed.record(envelope)
            }
        }
        defer { collectionTask.cancel() }

        let worktreeId = UUID()
        await actor.register(
            worktreeId: worktreeId,
            repoId: worktreeId,
            rootPath: URL(fileURLWithPath: "/tmp/shutdown-drain-\(UUID().uuidString)")
        )

        await actor.enqueueRawPaths(worktreeId: worktreeId, paths: ["Sources/Cancelled.swift"])
        await Task.yield()
        await actor.shutdown()
        clock.advance(by: .milliseconds(300))
        await Task.yield()
        #expect(await observed.filesChangedCount(for: worktreeId) == 0)
    }

    @Test("unregister during debounce window prevents stale filesChanged emission")
    func unregisterDuringDebouncePreventsStaleEmission() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let clock = TestPushClock()
        let actor = FilesystemActor(
            bus: bus,
            fseventStreamClient: ControllableFSEventStreamClient(),
            sleepClock: clock,
            debounceWindow: .milliseconds(200),
            maxFlushLatency: .seconds(1)
        )

        let observed = ObservedFilesystemChanges()
        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        let collectionTask = Task {
            for await envelope in stream {
                await observed.record(envelope)
            }
        }
        defer { collectionTask.cancel() }

        let worktreeId = UUID()
        await actor.register(
            worktreeId: worktreeId,
            repoId: worktreeId,
            rootPath: URL(fileURLWithPath: "/tmp/unregister-debounce-\(UUID().uuidString)")
        )

        await actor.enqueueRawPaths(worktreeId: worktreeId, paths: ["Sources/Stale.swift"])
        await Task.yield()
        clock.advance(by: .milliseconds(25))
        await Task.yield()
        await actor.unregister(worktreeId: worktreeId)
        clock.advance(by: .milliseconds(300))
        await Task.yield()
        #expect(await observed.filesChangedCount(for: worktreeId) == 0)
        await actor.shutdown()
    }

    private func filesChangedChangeset(from envelope: RuntimeEnvelope) -> FileChangeset? {
        guard case .worktree(let worktreeEnvelope) = envelope else { return nil }
        guard case .filesystem(.filesChanged(let changeset)) = worktreeEnvelope.event else {
            return nil
        }
        return changeset
    }

    private func normalizedRelativePath(_ rawPath: String) -> String {
        var normalizedPath = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalizedPath.hasPrefix("./") {
            normalizedPath.removeFirst(2)
        }
        if normalizedPath.hasPrefix("/") {
            normalizedPath.removeFirst()
        }
        return normalizedPath
    }

    private func makeActor(bus: EventBus<RuntimeEnvelope>) -> FilesystemActor {
        FilesystemActor(
            bus: bus,
            fseventStreamClient: ControllableFSEventStreamClient(),
            debounceWindow: .zero,
            maxFlushLatency: .zero
        )
    }

    private func waitUntilFilesystemLogicalDebt(
        _ actor: FilesystemActor,
        equals expectedCount: Int,
        maxTurns: Int = 10_000
    ) async -> Bool {
        for _ in 0..<maxTurns {
            if await actor.logicalDebtSnapshot().logicalDebtCount == expectedCount {
                return true
            }
            await Task.yield()
        }
        return await actor.logicalDebtSnapshot().logicalDebtCount == expectedCount
    }

    private func makeFilesystemLogicalDebtTraceRuntime() -> AgentStudioTraceRuntime {
        AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": FileManager.default.temporaryDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "filesystem-logical-debt-ordering-\(UUIDv7.generate().uuidString)",
                "AGENTSTUDIO_TRACE_TAGS": "performance",
            ]),
            processIdentifier: 924
        )
    }
}

private actor LogicalDebtSnapshotGate {
    private var didEnter = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func waitForRelease() async -> WatchedFolderScanSchedulerStateSnapshot {
        didEnter = true
        let waiters = entryWaiters
        entryWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
        return .active(
            WatchedFolderScanSchedulerActiveState(
                ready: 1,
                activeQuanta: 0,
                awaitingValidations: 0,
                pendingResults: 0,
                leasedResults: 0,
                dirtyFollowUps: 0,
                resultCustodyHighWater: 0
            )
        )
    }

    func waitUntilEntered() async {
        guard !didEnter else { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func release() {
        let waiters = releaseWaiters
        releaseWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private actor ObservedFilesystemChanges {
    private var changesetsByWorktreeId: [UUID: [FileChangeset]] = [:]
    private var pendingChangesets: [FileChangeset] = []
    private var nextWaiters: [CheckedContinuation<FileChangeset, Never>] = []

    func record(_ envelope: RuntimeEnvelope) {
        guard case .worktree(let worktreeEnvelope) = envelope else { return }
        guard case .filesystem(.filesChanged(let changeset)) = worktreeEnvelope.event else { return }
        changesetsByWorktreeId[changeset.worktreeId, default: []].append(changeset)
        if nextWaiters.isEmpty {
            pendingChangesets.append(changeset)
            return
        }

        let waiter = nextWaiters.removeFirst()
        waiter.resume(returning: changeset)
    }

    func filesChangedCount(for worktreeId: UUID) -> Int {
        changesetsByWorktreeId[worktreeId]?.count ?? 0
    }

    func latestChangeset(for worktreeId: UUID) -> FileChangeset? {
        changesetsByWorktreeId[worktreeId]?.last
    }

    func next() async -> FileChangeset {
        if !pendingChangesets.isEmpty {
            return pendingChangesets.removeFirst()
        }

        return await withCheckedContinuation { continuation in
            nextWaiters.append(continuation)
        }
    }
}
