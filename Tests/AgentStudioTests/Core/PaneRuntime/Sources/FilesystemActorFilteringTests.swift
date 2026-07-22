import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct FilesystemActorFilteringTests {
    @Test("git internal paths are suppressed from projection payload and annotated for downstream sinks")
    func gitInternalPathsAreSuppressedFromProjectionPayload() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let actor = makeActor(bus: bus)

        let worktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/git-internal-\(UUID().uuidString)")
        await actor.register(worktreeId: worktreeId, repoId: worktreeId, rootPath: rootPath)

        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        var iterator = stream.makeAsyncIterator()

        await actor.enqueueRawPaths(
            worktreeId: worktreeId,
            paths: [".git/index", ".git/objects/aa/bb", "Sources/App.swift"]
        )

        let envelope = try #require(await iterator.next())
        let changeset = try #require(filesChangedChangeset(from: envelope))
        #expect(changeset.worktreeId == worktreeId)
        #expect(changeset.paths == ["Sources/App.swift"])
        #expect(changeset.containsGitInternalChanges)
        #expect(changeset.suppressedGitInternalPathCount == 2)
        #expect(changeset.suppressedIgnoredPathCount == 0)

        await actor.shutdown()
    }

    @Test("gitignore policy suppresses ignored paths while preserving included and unignored paths")
    func gitignorePolicySuppressesIgnoredPaths() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let actor = makeActor(bus: bus)

        let rootPath = FileManager.default.temporaryDirectory
            .appending(path: "gitignore-filter-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootPath) }

        let gitignoreContents = """
            *.log
            build/
            !build/include.log
            """
        try gitignoreContents.write(
            to: rootPath.appending(path: ".gitignore"),
            atomically: true,
            encoding: .utf8
        )

        let worktreeId = UUID()
        await actor.register(worktreeId: worktreeId, repoId: worktreeId, rootPath: rootPath)

        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        var iterator = stream.makeAsyncIterator()

        await actor.enqueueRawPaths(
            worktreeId: worktreeId,
            paths: ["app.log", "build/out.txt", "build/include.log", "Sources/App.swift", ".git/index"]
        )

        let envelope = try #require(await iterator.next())
        let changeset = try #require(filesChangedChangeset(from: envelope))
        #expect(Set(changeset.paths) == Set(["build/include.log", "Sources/App.swift"]))
        #expect(changeset.containsGitInternalChanges)
        #expect(changeset.suppressedIgnoredPathCount == 2)
        #expect(changeset.suppressedGitInternalPathCount == 1)

        await actor.shutdown()
    }

    @Test("filtered-only changes still emit filesChanged to drive git projector refresh")
    func filteredOnlyChangesStillEmitFilesChangedEvent() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let actor = makeActor(bus: bus)

        let rootPath = FileManager.default.temporaryDirectory
            .appending(path: "filtered-only-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootPath) }
        try "*.tmp\n".write(
            to: rootPath.appending(path: ".gitignore"),
            atomically: true,
            encoding: .utf8
        )

        let worktreeId = UUID()
        await actor.register(worktreeId: worktreeId, repoId: worktreeId, rootPath: rootPath)

        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        var iterator = stream.makeAsyncIterator()

        await actor.enqueueRawPaths(
            worktreeId: worktreeId,
            paths: [".git/index", "cache.tmp"]
        )

        let envelope = try #require(await iterator.next())
        let changeset = try #require(filesChangedChangeset(from: envelope))
        #expect(Set(changeset.paths).isSubset(of: ["."]))
        #expect(changeset.containsGitInternalChanges)
        #expect(changeset.suppressedIgnoredPathCount == 1)
        #expect(changeset.suppressedGitInternalPathCount == 1)

        await actor.shutdown()
    }

    @Test("ignored-only changes do not emit filesChanged envelope")
    func ignoredOnlyChangesDoNotEmitFilesChangedEnvelope() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let actor = makeActor(bus: bus)

        let rootPath = FileManager.default.temporaryDirectory
            .appending(path: "ignored-only-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootPath) }
        try "*.tmp\n".write(
            to: rootPath.appending(path: ".gitignore"),
            atomically: true,
            encoding: .utf8
        )

        let worktreeId = UUID()
        await actor.register(worktreeId: worktreeId, repoId: worktreeId, rootPath: rootPath)

        let observed = FilteringObservedFilesystemChanges()
        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        let collectionTask = Task {
            for await envelope in stream {
                await observed.record(envelope)
            }
        }
        defer { collectionTask.cancel() }

        await actor.enqueueRawPaths(worktreeId: worktreeId, paths: ["cache.tmp"])
        for _ in 0..<300 {
            await Task.yield()
        }

        #expect(await observed.filesChangedCount(for: worktreeId) == 0)

        await actor.shutdown()
    }

    @Test("gitignore modification reloads filter for subsequent batches")
    func gitignoreModificationReloadsFilterForSubsequentBatches() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let actor = makeActor(bus: bus)

        let rootPath = FileManager.default.temporaryDirectory
            .appending(path: "gitignore-reload-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootPath) }
        try "*.tmp\n".write(
            to: rootPath.appending(path: ".gitignore"),
            atomically: true,
            encoding: .utf8
        )

        let worktreeId = UUID()
        await actor.register(worktreeId: worktreeId, repoId: worktreeId, rootPath: rootPath)

        let observed = FilteringObservedFilesystemChanges()
        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        let collectionTask = Task {
            for await envelope in stream {
                await observed.record(envelope)
            }
        }
        defer { collectionTask.cancel() }

        await actor.enqueueRawPaths(worktreeId: worktreeId, paths: [".git/index", "cache.tmp"])
        let initialChangeset = await observed.next()
        #expect(initialChangeset.paths.isEmpty)
        #expect(initialChangeset.containsGitInternalChanges)
        #expect(initialChangeset.suppressedIgnoredPathCount == 1)

        try "# no ignore rules\n".write(
            to: rootPath.appending(path: ".gitignore"),
            atomically: true,
            encoding: .utf8
        )
        await actor.enqueueRawPaths(worktreeId: worktreeId, paths: [".gitignore"])

        await actor.enqueueRawPaths(worktreeId: worktreeId, paths: ["cache.tmp"])
        let nextChangeset = await observed.next()
        let postReloadChangeset: FileChangeset
        if nextChangeset.paths.contains("cache.tmp") {
            postReloadChangeset = nextChangeset
        } else {
            #expect(!nextChangeset.paths.contains(".gitignore"))
            postReloadChangeset = await observed.next()
        }
        #expect(postReloadChangeset.paths.contains("cache.tmp"))
        #expect(!postReloadChangeset.paths.contains(".gitignore"))
        #expect(postReloadChangeset.suppressedIgnoredPathCount == 0)

        await actor.shutdown()
    }

    @Test("gitignore-only modification emits refresh-worthy empty changeset")
    func gitignoreOnlyModificationEmitsRefreshWorthyEmptyChangeset() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let actor = makeActor(bus: bus)

        let rootPath = FileManager.default.temporaryDirectory
            .appending(path: "gitignore-only-refresh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootPath) }
        try "*.tmp\n".write(
            to: rootPath.appending(path: ".gitignore"),
            atomically: true,
            encoding: .utf8
        )

        let worktreeId = UUID()
        await actor.register(worktreeId: worktreeId, repoId: worktreeId, rootPath: rootPath)

        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        var iterator = stream.makeAsyncIterator()

        try "# no ignore rules\n".write(
            to: rootPath.appending(path: ".gitignore"),
            atomically: true,
            encoding: .utf8
        )
        await actor.enqueueRawPaths(worktreeId: worktreeId, paths: [".gitignore"])

        let envelope = try #require(await iterator.next())
        let changeset = try #require(filesChangedChangeset(from: envelope))
        #expect(changeset.worktreeId == worktreeId)
        #expect(changeset.paths.isEmpty)
        #expect(changeset.containsGitInternalChanges)
        #expect(changeset.suppressedIgnoredPathCount == 0)
        #expect(changeset.suppressedGitInternalPathCount == 0)

        await actor.shutdown()
    }

    @Test("gitignore reload batch does not leak .gitignore into projected paths when coalesced")
    func gitignoreReloadBatchDoesNotLeakGitignoreIntoProjectedPathsWhenCoalesced() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let actor = makeActor(bus: bus)

        let rootPath = FileManager.default.temporaryDirectory
            .appending(path: "gitignore-coalesced-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootPath) }
        try "*.tmp\n".write(
            to: rootPath.appending(path: ".gitignore"),
            atomically: true,
            encoding: .utf8
        )

        let worktreeId = UUID()
        await actor.register(worktreeId: worktreeId, repoId: worktreeId, rootPath: rootPath)

        let observed = FilteringObservedFilesystemChanges()
        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        let collectionTask = Task {
            for await envelope in stream {
                await observed.record(envelope)
            }
        }

        await actor.enqueueRawPaths(worktreeId: worktreeId, paths: [".git/index", "cache.tmp"])
        let initialChangeset = await observed.next()
        #expect(initialChangeset.paths.isEmpty)
        #expect(initialChangeset.containsGitInternalChanges)
        #expect(initialChangeset.suppressedIgnoredPathCount == 1)

        try "# no ignore rules\n".write(
            to: rootPath.appending(path: ".gitignore"),
            atomically: true,
            encoding: .utf8
        )
        await actor.enqueueRawPaths(worktreeId: worktreeId, paths: [".gitignore", "cache.tmp"])

        let nextChangeset = await observed.next()
        let postReloadChangeset: FileChangeset
        if nextChangeset.paths.contains("cache.tmp") {
            postReloadChangeset = nextChangeset
        } else {
            #expect(!nextChangeset.paths.contains(".gitignore"))
            postReloadChangeset = await observed.next()
        }
        #expect(postReloadChangeset.paths.contains("cache.tmp"))
        #expect(!postReloadChangeset.paths.contains(".gitignore"))
        #expect(postReloadChangeset.suppressedIgnoredPathCount == 0)

        await actor.shutdown()
        collectionTask.cancel()
        await collectionTask.value
    }

    private func filesChangedChangeset(from envelope: RuntimeEnvelope) -> FileChangeset? {
        guard case .worktree(let worktreeEnvelope) = envelope else { return nil }
        guard case .filesystem(.filesChanged(let changeset)) = worktreeEnvelope.event else {
            return nil
        }
        return changeset
    }

    private func makeActor(bus: EventBus<RuntimeEnvelope>) -> FilesystemActor {
        FilesystemActor(
            bus: bus,
            fseventStreamClient: ControllableFSEventStreamClient(),
            debounceWindow: .zero,
            maxFlushLatency: .zero
        )
    }
}

private actor FilteringObservedFilesystemChanges {
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
