import Foundation
import Testing

@testable import AgentStudio

@Suite("FilesystemActor path filter reload")
struct FilesystemActorPathFilterReloadTests {
    @Test("suspended register attaches watcher before filter load completes")
    func suspendedRegisterAttachesWatcherBeforeFilterLoadCompletes() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let loader = ControlledPathFilterReloadLoader()
        let streamClient = ControllableFSEventStreamClient()
        let actor = FilesystemActor(
            bus: bus,
            fseventStreamClient: streamClient,
            pathFilterLoader: { rootPath in
                await loader.load(forRootPath: rootPath)
            },
            debounceWindow: .zero,
            maxFlushLatency: .zero
        )

        let worktreeId = UUID()
        await loader.suspendNextLoad()
        let registerTask = Task {
            await actor.register(
                worktreeId: worktreeId,
                repoId: worktreeId,
                rootPath: URL(fileURLWithPath: "/tmp/suspended-register-attaches-\(UUID().uuidString)")
            )
        }
        await loader.waitForSuspendedLoad()

        #expect(streamClient.registeredWorktreeIds.contains(worktreeId))

        await loader.resumeSuspendedLoad()
        await registerTask.value
        await actor.shutdown()
    }

    @Test("ingress overflow reloads gitignore policy before later classification")
    func ingressOverflowReloadsGitignorePolicyBeforeLaterClassification() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let streamClient = ControllableFSEventStreamClient()
        let actor = FilesystemActor(
            bus: bus,
            fseventStreamClient: streamClient,
            debounceWindow: .zero,
            maxFlushLatency: .zero
        )

        let rootPath = FileManager.default.temporaryDirectory
            .appending(path: "gitignore-overflow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootPath) }
        try "*.tmp\n".write(
            to: rootPath.appending(path: ".gitignore"),
            atomically: true,
            encoding: .utf8
        )

        let worktreeId = UUID()
        await actor.register(worktreeId: worktreeId, repoId: worktreeId, rootPath: rootPath)

        let observed = PathFilterReloadObservedChanges()
        let stream = await bus.subscribe()
        let collectionTask = Task {
            for await envelope in stream {
                await observed.record(envelope)
            }
        }
        defer { collectionTask.cancel() }

        try "# no ignore rules\n".write(
            to: rootPath.appending(path: ".gitignore"),
            atomically: true,
            encoding: .utf8
        )
        streamClient.send(.init(worktreeId: worktreeId, paths: [".gitignore"], didOverflow: true))
        streamClient.send(.init(worktreeId: worktreeId, paths: ["cache.tmp"]))

        let overflowResync = await observed.next()
        #expect(overflowResync.paths == ["."])

        let changeset = await observed.next()
        #expect(changeset.paths.contains("cache.tmp"))
        #expect(changeset.suppressedIgnoredPathCount == 0)

        await actor.shutdown()
    }

    @Test("ingress overflow emits coarse source worktree resync")
    func ingressOverflowEmitsCoarseSourceWorktreeResync() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let streamClient = ControllableFSEventStreamClient()
        let actor = FilesystemActor(
            bus: bus,
            fseventStreamClient: streamClient,
            debounceWindow: .zero,
            maxFlushLatency: .zero
        )

        let worktreeId = UUID()
        await actor.register(
            worktreeId: worktreeId,
            repoId: worktreeId,
            rootPath: URL(fileURLWithPath: "/tmp/overflow-resync-\(UUID().uuidString)")
        )

        let observed = PathFilterReloadObservedChanges()
        let stream = await bus.subscribe()
        let collectionTask = Task {
            for await envelope in stream {
                await observed.record(envelope)
            }
        }
        defer { collectionTask.cancel() }

        streamClient.send(.init(worktreeId: worktreeId, paths: [], didOverflow: true))

        let changeset = await observed.next()
        #expect(changeset.worktreeId == worktreeId)
        #expect(changeset.paths == ["."])

        await actor.shutdown()
    }

    @Test("slow gitignore reload does not block unrelated worktree ingress")
    func slowGitignoreReloadDoesNotBlockUnrelatedWorktreeIngress() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let loader = ControlledPathFilterReloadLoader()
        let actor = FilesystemActor(
            bus: bus,
            fseventStreamClient: ControllableFSEventStreamClient(),
            pathFilterLoader: { rootPath in
                await loader.load(forRootPath: rootPath)
            },
            debounceWindow: .zero,
            maxFlushLatency: .zero
        )

        let rootPath = FileManager.default.temporaryDirectory
            .appending(path: "gitignore-slow-reload-\(UUID().uuidString)")
        let unrelatedRootPath = FileManager.default.temporaryDirectory
            .appending(path: "gitignore-slow-reload-unrelated-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootPath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unrelatedRootPath, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: rootPath)
            try? FileManager.default.removeItem(at: unrelatedRootPath)
        }

        let worktreeId = UUID()
        let unrelatedWorktreeId = UUID()
        await actor.register(worktreeId: worktreeId, repoId: worktreeId, rootPath: rootPath)
        await actor.register(
            worktreeId: unrelatedWorktreeId,
            repoId: unrelatedWorktreeId,
            rootPath: unrelatedRootPath
        )

        let observed = PathFilterReloadObservedChanges()
        let stream = await bus.subscribe()
        let collectionTask = Task {
            for await envelope in stream {
                await observed.record(envelope)
            }
        }
        defer { collectionTask.cancel() }

        await loader.suspendNextLoad()
        let reloadTask = Task {
            await actor.enqueueRawPaths(worktreeId: worktreeId, paths: [".gitignore"])
        }
        await loader.waitForSuspendedLoad()

        await actor.enqueueRawPaths(worktreeId: unrelatedWorktreeId, paths: ["Sources/WhileReload.swift"])

        let changeset = await observed.next()
        #expect(changeset.worktreeId == unrelatedWorktreeId)
        #expect(changeset.paths == ["Sources/WhileReload.swift"])

        await loader.resumeSuspendedLoad()
        await reloadTask.value
        await actor.shutdown()
    }

    @Test("slow gitignore reload gates later same-worktree classification")
    func slowGitignoreReloadGatesLaterSameWorktreeClassification() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let loader = ControlledPathFilterReloadLoader()
        let actor = FilesystemActor(
            bus: bus,
            fseventStreamClient: ControllableFSEventStreamClient(),
            pathFilterLoader: { rootPath in
                await loader.load(forRootPath: rootPath)
            },
            debounceWindow: .zero,
            maxFlushLatency: .zero
        )

        let rootPath = FileManager.default.temporaryDirectory
            .appending(path: "gitignore-same-worktree-gate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootPath) }
        try "*.tmp\n".write(
            to: rootPath.appending(path: ".gitignore"),
            atomically: true,
            encoding: .utf8
        )

        let worktreeId = UUID()
        await actor.register(worktreeId: worktreeId, repoId: worktreeId, rootPath: rootPath)

        let observed = PathFilterReloadObservedChanges()
        let stream = await bus.subscribe()
        let collectionTask = Task {
            for await envelope in stream {
                await observed.record(envelope)
            }
        }
        defer { collectionTask.cancel() }

        try "# no ignore rules\n".write(
            to: rootPath.appending(path: ".gitignore"),
            atomically: true,
            encoding: .utf8
        )
        await loader.suspendNextLoad()
        let reloadTask = Task {
            await actor.enqueueRawPaths(worktreeId: worktreeId, paths: [".gitignore"])
        }
        await loader.waitForSuspendedLoad()

        let sameWorktreeTask = Task {
            await actor.enqueueRawPaths(worktreeId: worktreeId, paths: ["cache.tmp"])
        }
        await Task.yield()
        #expect(await observed.filesChangedCount(for: worktreeId) == 0)

        await loader.resumeSuspendedLoad()
        await reloadTask.value
        await sameWorktreeTask.value

        let changeset = await observed.next()
        #expect(changeset.paths.contains("cache.tmp"))
        #expect(changeset.suppressedIgnoredPathCount == 0)

        await actor.shutdown()
    }
}

private actor PathFilterReloadObservedChanges {
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

    func next() async -> FileChangeset {
        if !pendingChangesets.isEmpty {
            return pendingChangesets.removeFirst()
        }

        return await withCheckedContinuation { continuation in
            nextWaiters.append(continuation)
        }
    }
}

private actor ControlledPathFilterReloadLoader {
    private var shouldSuspendNextLoad = false
    private var suspendedContinuation: CheckedContinuation<Void, Never>?
    private var suspendedWaiters: [CheckedContinuation<Void, Never>] = []

    func suspendNextLoad() {
        shouldSuspendNextLoad = true
    }

    func load(forRootPath rootPath: URL) async -> FilesystemPathFilter {
        if shouldSuspendNextLoad {
            shouldSuspendNextLoad = false
            await withCheckedContinuation { continuation in
                suspendedContinuation = continuation
                let waiters = suspendedWaiters
                suspendedWaiters.removeAll(keepingCapacity: false)
                for waiter in waiters {
                    waiter.resume()
                }
            }
        }

        return await FilesystemPathFilter.load(forRootPath: rootPath)
    }

    func waitForSuspendedLoad() async {
        guard suspendedContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            suspendedWaiters.append(continuation)
        }
    }

    func resumeSuspendedLoad() {
        let continuation = suspendedContinuation
        suspendedContinuation = nil
        continuation?.resume()
    }
}
