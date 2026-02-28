import Foundation
import Testing

@testable import AgentStudio

@Suite("FilesystemActor")
struct FilesystemActorTests {
    @Test("deepest ownership dedupes nested roots")
    func deepestOwnershipDedupesNestedRoots() async throws {
        let bus = EventBus<PaneEventEnvelope>()
        let actor = FilesystemActor(
            bus: bus,
            gitStatusProvider: StubGitStatusProvider()
        )

        let parentId = UUID()
        let childId = UUID()
        await actor.register(worktreeId: parentId, rootPath: URL(fileURLWithPath: "/tmp/repo"))
        await actor.register(worktreeId: childId, rootPath: URL(fileURLWithPath: "/tmp/repo/nested"))

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
        let actor = FilesystemActor(
            bus: bus,
            gitStatusProvider: StubGitStatusProvider()
        )

        let parentId = UUID()
        let childId = UUID()
        await actor.register(worktreeId: parentId, rootPath: URL(fileURLWithPath: "/tmp/repo"))
        await actor.register(worktreeId: childId, rootPath: URL(fileURLWithPath: "/tmp/repo/nested"))

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
        let actor = FilesystemActor(
            bus: bus,
            gitStatusProvider: StubGitStatusProvider()
        )

        let sidebarOnlyWorktreeId = UUID()
        let activeWorktreeId = UUID()
        await actor.register(worktreeId: sidebarOnlyWorktreeId, rootPath: URL(fileURLWithPath: "/tmp/sidebar"))
        await actor.register(worktreeId: activeWorktreeId, rootPath: URL(fileURLWithPath: "/tmp/active"))
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
        let actor = FilesystemActor(
            bus: bus,
            gitStatusProvider: StubGitStatusProvider()
        )

        let basePath = "/tmp/priority-\(UUID().uuidString)"
        let sidebarWorktreeId = UUID()
        let activeWorktreeId = UUID()
        let focusedWorktreeId = UUID()
        await actor.register(worktreeId: sidebarWorktreeId, rootPath: URL(fileURLWithPath: basePath))
        await actor.register(worktreeId: activeWorktreeId, rootPath: URL(fileURLWithPath: "\(basePath)/active"))
        await actor.register(
            worktreeId: focusedWorktreeId, rootPath: URL(fileURLWithPath: "\(basePath)/active/focused"))

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
        let actor = FilesystemActor(
            bus: bus,
            gitStatusProvider: StubGitStatusProvider()
        )

        let worktreeId = UUID()
        await actor.register(worktreeId: worktreeId, rootPath: URL(fileURLWithPath: "/tmp/contract"))

        let stream = await bus.subscribe()
        var iterator = stream.makeAsyncIterator()

        await actor.enqueueRawPaths(worktreeId: worktreeId, paths: ["Sources/App.swift"])

        let envelope = try #require(await iterator.next())
        #expect(envelope.source == .system(.builtin(.filesystemWatcher)))
        #expect(envelope.sourceFacets.worktreeId == worktreeId)

        let changeset = try #require(filesChangedChangeset(from: envelope))
        #expect(changeset.worktreeId == worktreeId)
        #expect(changeset.paths == ["Sources/App.swift"])

        await actor.shutdown()
    }

    @Test("large path bursts split into fixed-size ordered filesChanged batches")
    func largeBurstSplitsIntoBoundedSortedBatches() async throws {
        let bus = EventBus<PaneEventEnvelope>()
        let actor = FilesystemActor(
            bus: bus,
            gitStatusProvider: StubGitStatusProvider()
        )

        let worktreeId = UUID()
        await actor.register(worktreeId: worktreeId, rootPath: URL(fileURLWithPath: "/tmp/large-batch"))

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
}
