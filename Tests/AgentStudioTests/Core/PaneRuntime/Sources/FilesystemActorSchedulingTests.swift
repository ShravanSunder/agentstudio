import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

extension FilesystemActorTests {
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

    @Test("shutdown closes filesystem admission before asynchronous cleanup")
    func shutdownClosesFilesystemAdmission() async {
        let clock = TestPushClock()
        let streamClient = ControllableFSEventStreamClient()
        let actor = FilesystemActor(
            bus: EventBus<RuntimeEnvelope>(),
            fseventStreamClient: streamClient,
            sleepClock: clock,
            debounceWindow: .milliseconds(200),
            maxFlushLatency: .seconds(1)
        )
        let worktreeID = UUIDv7.generate()
        await actor.register(
            worktreeId: worktreeID,
            repoId: worktreeID,
            rootPath: URL(fileURLWithPath: "/tmp/shutdown-admission-\(UUIDv7.generate())")
        )

        await actor.shutdown()
        let revisionAfterShutdown = await actor.logicalDebtSnapshotPublicationRevision
        let postShutdownWorktreeID = UUIDv7.generate()
        await actor.register(
            worktreeId: postShutdownWorktreeID,
            repoId: postShutdownWorktreeID,
            rootPath: URL(fileURLWithPath: "/tmp/post-shutdown-registration")
        )
        await actor.enqueueRawPaths(worktreeId: worktreeID, paths: ["Sources/PostShutdown.swift"])
        clock.advance(by: .seconds(1))
        await Task.yield()

        #expect(await actor.logicalDebtSnapshotPublicationRevision == revisionAfterShutdown)
        #expect(await actor.logicalDebtSnapshot().logicalDebtCount == 0)
        #expect(streamClient.registeredWorktreeIds == [worktreeID])
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
}

actor ObservedFilesystemChanges {
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
