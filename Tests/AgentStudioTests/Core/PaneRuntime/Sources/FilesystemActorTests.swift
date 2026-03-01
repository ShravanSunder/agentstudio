import Foundation
import Testing

@testable import AgentStudio

@Suite("FilesystemActor")
struct FilesystemActorTests {
    @Test("register emits worktreeRegistered fact")
    func registerEmitsWorktreeRegisteredFact() async throws {
        let bus = EventBus<PaneEventEnvelope>()
        let actor = makeActor(bus: bus)

        let stream = await bus.subscribe()
        var iterator = stream.makeAsyncIterator()

        let worktreeId = UUID()
        let repoId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/register-\(UUID().uuidString)")
        await actor.register(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)

        let envelope = try #require(await iterator.next())
        guard case .filesystem(let filesystemEvent) = envelope.event else {
            Issue.record("Expected filesystem event")
            return
        }
        guard
            case .worktreeRegistered(let registeredWorktreeId, let registeredRepoId, let registeredRootPath) =
            filesystemEvent
        else {
            Issue.record("Expected worktreeRegistered filesystem event")
            return
        }

        #expect(registeredWorktreeId == worktreeId)
        #expect(registeredRepoId == repoId)
        #expect(registeredRootPath == rootPath)
        #expect(envelope.sourceFacets.repoId == repoId)
        #expect(envelope.sourceFacets.worktreeId == worktreeId)
        #expect(filesystemEvent.compatibilityScope == .systemTopology)

        guard case .repoDiscovered(let mappedRepoPath, let mappedParentPath) = filesystemEvent.compatibilityTopologyEvent()
        else {
            Issue.record("Expected compatibility topology mapping for registration")
            return
        }
        #expect(mappedRepoPath == rootPath)
        #expect(mappedParentPath == rootPath.deletingLastPathComponent())
        if filesystemEvent.compatibilityWorktreeScopedEvent != nil {
            Issue.record("Expected register compatibility mapping to exclude worktree-scoped payload")
        }

        await actor.shutdown()
    }

    @Test("unregister emits worktreeUnregistered fact")
    func unregisterEmitsWorktreeUnregisteredFact() async throws {
        let bus = EventBus<PaneEventEnvelope>()
        let actor = makeActor(bus: bus)

        let stream = await bus.subscribe()
        var iterator = stream.makeAsyncIterator()

        let worktreeId = UUID()
        let repoId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/unregister-\(UUID().uuidString)")
        await actor.register(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)
        _ = try #require(await iterator.next())  // worktreeRegistered

        await actor.unregister(worktreeId: worktreeId)
        let envelope = try #require(await iterator.next())
        guard case .filesystem(let filesystemEvent) = envelope.event else {
            Issue.record("Expected filesystem event")
            return
        }
        guard
            case .worktreeUnregistered(let unregisteredWorktreeId, let unregisteredRepoId) = filesystemEvent
        else {
            Issue.record("Expected worktreeUnregistered filesystem event")
            return
        }

        #expect(unregisteredWorktreeId == worktreeId)
        #expect(unregisteredRepoId == repoId)
        #expect(envelope.sourceFacets.repoId == repoId)
        #expect(envelope.sourceFacets.worktreeId == worktreeId)
        #expect(filesystemEvent.compatibilityScope == .systemTopology)

        guard
            case .repoRemoved(let mappedRepoPath) = filesystemEvent.compatibilityTopologyEvent(unregisterRootPath: rootPath)
        else {
            Issue.record("Expected compatibility topology mapping for unregistration")
            return
        }
        #expect(mappedRepoPath == rootPath)
        if filesystemEvent.compatibilityWorktreeScopedEvent != nil {
            Issue.record("Expected unregister compatibility mapping to exclude worktree-scoped payload")
        }

        await actor.shutdown()
    }

    @Test("deepest ownership dedupes nested roots")
    func deepestOwnershipDedupesNestedRoots() async throws {
        let bus = EventBus<PaneEventEnvelope>()
        let actor = makeActor(bus: bus)

        let parentId = UUID()
        let childId = UUID()
        await actor.register(worktreeId: parentId, repoId: parentId, rootPath: URL(fileURLWithPath: "/tmp/repo"))
        await actor.register(worktreeId: childId, repoId: childId, rootPath: URL(fileURLWithPath: "/tmp/repo/nested"))

        let stream = await bus.subscribe()
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
        let bus = EventBus<PaneEventEnvelope>()
        let actor = makeActor(bus: bus)

        let parentId = UUID()
        let childId = UUID()
        await actor.register(worktreeId: parentId, repoId: parentId, rootPath: URL(fileURLWithPath: "/tmp/repo"))
        await actor.register(worktreeId: childId, repoId: childId, rootPath: URL(fileURLWithPath: "/tmp/repo/nested"))

        let stream = await bus.subscribe()
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
        let bus = EventBus<PaneEventEnvelope>()
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

        let stream = await bus.subscribe()
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
        let bus = EventBus<PaneEventEnvelope>()
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

        let stream = await bus.subscribe()
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

    @Test("filesChanged envelope source and facets contract")
    func filesChangedSourceFacetContract() async throws {
        let bus = EventBus<PaneEventEnvelope>()
        let actor = makeActor(bus: bus)

        let worktreeId = UUID()
        await actor.register(
            worktreeId: worktreeId, repoId: worktreeId, rootPath: URL(fileURLWithPath: "/tmp/contract"))

        let stream = await bus.subscribe()
        var iterator = stream.makeAsyncIterator()

        await actor.enqueueRawPaths(worktreeId: worktreeId, paths: ["Sources/App.swift"])

        let envelope = try #require(await iterator.next())
        #expect(envelope.source == .system(.builtin(.filesystemWatcher)))
        #expect(envelope.sourceFacets.worktreeId == worktreeId)
        guard case .filesystem(let filesystemEvent) = envelope.event else {
            Issue.record("Expected filesystem event")
            return
        }
        #expect(filesystemEvent.compatibilityScope == .worktreeFilesystem)
        guard
            case .filesystem(.filesChanged(let compatibilityChangeset))? = filesystemEvent.compatibilityWorktreeScopedEvent
        else {
            Issue.record("Expected compatibility worktree filesystem mapping")
            return
        }

        let changeset = try #require(filesChangedChangeset(from: envelope))
        #expect(changeset.worktreeId == worktreeId)
        #expect(changeset.paths == ["Sources/App.swift"])
        #expect(compatibilityChangeset.worktreeId == changeset.worktreeId)
        #expect(compatibilityChangeset.paths == changeset.paths)

        await actor.shutdown()
    }

    @Test("large path bursts split into fixed-size ordered filesChanged batches")
    func largeBurstSplitsIntoBoundedSortedBatches() async throws {
        let bus = EventBus<PaneEventEnvelope>()
        let actor = makeActor(bus: bus)

        let worktreeId = UUID()
        await actor.register(
            worktreeId: worktreeId, repoId: worktreeId, rootPath: URL(fileURLWithPath: "/tmp/large-batch"))

        let stream = await bus.subscribe()
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

    @Test("git internal paths are suppressed from projection payload and annotated for downstream sinks")
    func gitInternalPathsAreSuppressedFromProjectionPayload() async throws {
        let bus = EventBus<PaneEventEnvelope>()
        let actor = makeActor(bus: bus)

        let worktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/git-internal-\(UUID().uuidString)")
        await actor.register(worktreeId: worktreeId, repoId: worktreeId, rootPath: rootPath)

        let stream = await bus.subscribe()
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
        let bus = EventBus<PaneEventEnvelope>()
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

        let stream = await bus.subscribe()
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
        let bus = EventBus<PaneEventEnvelope>()
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

        let stream = await bus.subscribe()
        var iterator = stream.makeAsyncIterator()

        await actor.enqueueRawPaths(
            worktreeId: worktreeId,
            paths: [".git/index", "cache.tmp"]
        )

        let envelope = try #require(await iterator.next())
        let changeset = try #require(filesChangedChangeset(from: envelope))
        #expect(changeset.paths.isEmpty)
        #expect(changeset.containsGitInternalChanges)
        #expect(changeset.suppressedIgnoredPathCount == 1)
        #expect(changeset.suppressedGitInternalPathCount == 1)

        await actor.shutdown()
    }

    @Test("gitignore modification reloads filter for subsequent batches")
    func gitignoreModificationReloadsFilterForSubsequentBatches() async throws {
        let bus = EventBus<PaneEventEnvelope>()
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

        let stream = await bus.subscribe()
        var iterator = stream.makeAsyncIterator()

        await actor.enqueueRawPaths(worktreeId: worktreeId, paths: ["cache.tmp"])
        let initialEnvelope = try #require(await iterator.next())
        let initialChangeset = try #require(filesChangedChangeset(from: initialEnvelope))
        #expect(initialChangeset.paths.isEmpty)
        #expect(initialChangeset.suppressedIgnoredPathCount == 1)

        try "# no ignore rules\n".write(
            to: rootPath.appending(path: ".gitignore"),
            atomically: true,
            encoding: .utf8
        )
        await actor.enqueueRawPaths(worktreeId: worktreeId, paths: [".gitignore"])
        _ = try #require(await iterator.next())  // reload-trigger batch

        await actor.enqueueRawPaths(worktreeId: worktreeId, paths: ["cache.tmp"])
        let postReloadEnvelope = try #require(await iterator.next())
        let postReloadChangeset = try #require(filesChangedChangeset(from: postReloadEnvelope))
        #expect(postReloadChangeset.paths == ["cache.tmp"])
        #expect(postReloadChangeset.suppressedIgnoredPathCount == 0)

        await actor.shutdown()
    }

    @Test("debounce coalesces bursts and flushes once after debounce window")
    func debounceCoalescesBursts() async throws {
        let bus = EventBus<PaneEventEnvelope>()
        let actor = FilesystemActor(
            bus: bus,
            debounceWindow: .milliseconds(60),
            maxFlushLatency: .seconds(1)
        )

        let observed = ObservedFilesystemChanges()
        let stream = await bus.subscribe()
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

        try await Task.sleep(for: .milliseconds(20))
        #expect(await observed.filesChangedCount(for: worktreeId) == 0)

        try await Task.sleep(for: .milliseconds(80))
        #expect(await observed.filesChangedCount(for: worktreeId) == 1)
        let changeset = await observed.latestChangeset(for: worktreeId)
        #expect(Set(changeset?.paths ?? []) == Set(["Sources/A.swift", "Sources/B.swift"]))

        await actor.shutdown()
    }

    @Test("max latency flushes pending changes even when debounce keeps extending")
    func maxLatencyFlushesPendingChanges() async throws {
        let bus = EventBus<PaneEventEnvelope>()
        let actor = FilesystemActor(
            bus: bus,
            debounceWindow: .milliseconds(250),
            maxFlushLatency: .milliseconds(120)
        )

        let observed = ObservedFilesystemChanges()
        let stream = await bus.subscribe()
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
        try await Task.sleep(for: .milliseconds(70))
        await actor.enqueueRawPaths(worktreeId: worktreeId, paths: ["Sources/Second.swift"])

        try await Task.sleep(for: .milliseconds(120))
        #expect(await observed.filesChangedCount(for: worktreeId) >= 1)
        let changeset = await observed.latestChangeset(for: worktreeId)
        #expect(Set(changeset?.paths ?? []) == Set(["Sources/First.swift", "Sources/Second.swift"]))

        await actor.shutdown()
    }

    @Test("shutdown cancels pending debounce drain and prevents delayed filesChanged emission")
    func shutdownCancelsPendingDrain() async throws {
        let bus = EventBus<PaneEventEnvelope>()
        let actor = FilesystemActor(
            bus: bus,
            debounceWindow: .milliseconds(200),
            maxFlushLatency: .seconds(1)
        )

        let observed = ObservedFilesystemChanges()
        let stream = await bus.subscribe()
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
        await actor.shutdown()
        try await Task.sleep(for: .milliseconds(260))

        #expect(await observed.filesChangedCount(for: worktreeId) == 0)
    }

    @Test("unregister during debounce window prevents stale filesChanged emission")
    func unregisterDuringDebouncePreventsStaleEmission() async throws {
        let bus = EventBus<PaneEventEnvelope>()
        let actor = FilesystemActor(
            bus: bus,
            debounceWindow: .milliseconds(200),
            maxFlushLatency: .seconds(1)
        )

        let observed = ObservedFilesystemChanges()
        let stream = await bus.subscribe()
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
        try await Task.sleep(for: .milliseconds(25))
        await actor.unregister(worktreeId: worktreeId)
        try await Task.sleep(for: .milliseconds(260))

        #expect(await observed.filesChangedCount(for: worktreeId) == 0)
        await actor.shutdown()
    }

    private func filesChangedChangeset(from envelope: PaneEventEnvelope) -> FileChangeset? {
        guard case .filesystem(.filesChanged(let changeset)) = envelope.event else {
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

    private func makeActor(bus: EventBus<PaneEventEnvelope>) -> FilesystemActor {
        FilesystemActor(
            bus: bus,
            debounceWindow: .zero,
            maxFlushLatency: .zero
        )
    }
}

private actor ObservedFilesystemChanges {
    private var changesetsByWorktreeId: [UUID: [FileChangeset]] = [:]

    func record(_ envelope: PaneEventEnvelope) {
        guard case .filesystem(.filesChanged(let changeset)) = envelope.event else { return }
        changesetsByWorktreeId[changeset.worktreeId, default: []].append(changeset)
    }

    func filesChangedCount(for worktreeId: UUID) -> Int {
        changesetsByWorktreeId[worktreeId]?.count ?? 0
    }

    func latestChangeset(for worktreeId: UUID) -> FileChangeset? {
        changesetsByWorktreeId[worktreeId]?.last
    }
}
