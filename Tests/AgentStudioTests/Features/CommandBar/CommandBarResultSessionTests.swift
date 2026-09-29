import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Observation
import Testing

@testable import AgentStudioCommandBar

@MainActor
@Suite(.serialized)
struct CommandBarResultSessionTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("result session prepares declared documents for the service")
    func resultSessionPreparesSearchDocuments() async {
        let store = WorkspaceStore()
        let repoCache = RepoCacheAtom()
        let state = CommandBarState()
        state.show(prefix: ">")
        state.rawInput = "> close"

        let session = CommandBarResultSession(
            store: store,
            repoCache: repoCache,
            dispatcher: FakeAppCommandDispatcher()
        )

        let prepared = session.prepareSearch(state: state)
        let answer = await SearchService().search(
            SearchRequest(
                sequence: SearchRequestSequence(1),
                text: "close",
                recentItemIds: [],
                documentSet: prepared.documentSet
            )
        )

        #expect(!prepared.documentSet.documents.isEmpty)
        #expect(answer.outcome == .answered)
        #expect(!answer.groups.isEmpty)
        #expect(answer.groups.flatMap(\.matches).allSatisfy { prepared.rowsById[$0.itemId] != nil })
    }

    @Test("nested result session uses level items instead of rebuilding root items")
    func nestedResultSessionUsesLevelItems() {
        let state = CommandBarState()
        let nestedItem = CommandBarItem(
            id: "nested-open",
            title: "Open Here",
            group: "Actions",
            groupPriority: 1,
            action: .custom({})
        )
        state.pushLevel(
            CommandBarLevel(
                id: "worktree-actions",
                title: "Worktree Actions",
                items: [nestedItem]
            )
        )

        let session = CommandBarResultSession(
            store: WorkspaceStore(),
            repoCache: RepoCacheAtom(),
            dispatcher: FakeAppCommandDispatcher()
        )

        let snapshot = session.snapshot(state: state)

        #expect(snapshot.allItems.map(\.id) == ["nested-open"])
        #expect(snapshot.selectedItem?.id == "nested-open")
    }

    @Test("# root item snapshot rebuilds at the empty-to-meaningful boundary only")
    func rootItemSnapshotRebuildsOnlyAtMeaningfulBoundary() {
        let store = WorkspaceStore()
        let state = CommandBarState()
        state.show(prefix: "#")

        let dispatcher = FakeAppCommandDispatcher()
        let session = CommandBarResultSession(
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: dispatcher
        )

        _ = session.snapshot(state: state)
        state.rawInput = "# repo"
        _ = session.prepareSearch(state: state)
        state.rawInput = "# repo feature"
        _ = session.prepareSearch(state: state)

        #expect(session.rootItemSnapshotBuildCount == 2)
        #expect(session.rootItemSnapshotCacheHitCount == 1)
    }

    @Test("reopening after one repository changes preserves unrelated repository artifacts")
    func reopeningAfterRepositoryChangeKeepsUnrelatedArtifacts() {
        let store = WorkspaceStore()
        let changedRepository = store.addRepo(at: URL(filePath: "/tmp/command-bar-cache-changed"))
        _ = store.addRepo(at: URL(filePath: "/tmp/command-bar-cache-unchanged"))
        let state = CommandBarState()
        state.show(prefix: "#")
        let session = CommandBarResultSession(
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: FakeAppCommandDispatcher()
        )

        _ = session.snapshot(state: state)
        #expect(session.repoScopeItemBuildCount == 2)

        store.reconcileDiscoveredWorktrees(
            changedRepository.id,
            worktrees: changedRepository.worktrees + [
                makeWorktree(
                    repoId: changedRepository.id,
                    name: "feature-cache-identity",
                    path: "/tmp/command-bar-cache-changed/feature",
                    isMainWorktree: false
                )
            ]
        )
        #expect(!store.repositoryTopologyAtom.isRepoUnavailable(changedRepository.id))
        _ = session.snapshot(state: state)
        #expect(session.repoScopeItemBuildCount == 3)

        state.show(prefix: "#")
        _ = session.snapshot(state: state)

        #expect(session.repoScopeItemBuildCount == 3)
    }

    @Test("root item cache records hits and bounded miss reasons")
    func rootItemCacheRecordsHitsAndBoundedMissReasons() async throws {
        let traceDirectory = FileManager.default.temporaryDirectory
            .appending(path: "command-bar-cache-\(UUIDv7.generate().uuidString)")
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "command-bar-cache",
                "AGENTSTUDIO_TRACE_TAGS": "performance",
            ]),
            processIdentifier: 946,
            timeUnixNano: { 200 }
        )
        let recorder = AgentStudioPerformanceTraceRecorder(traceRuntime: runtime)
        let state = CommandBarState()
        state.show(prefix: "#")
        let session = CommandBarResultSession(
            store: WorkspaceStore(),
            repoCache: RepoCacheAtom(),
            dispatcher: FakeAppCommandDispatcher(),
            performanceTraceRecorder: recorder
        )

        _ = session.snapshot(state: state)
        _ = session.snapshot(state: state)
        state.rawInput = "# repo"
        _ = session.prepareSearch(state: state)
        try await recorder.drain()

        let outputFileURL = try #require(runtime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"body\":\"performance.commandbar.cache\""))
        #expect(contents.contains("\"agentstudio.performance.commandbar.cache_outcome\":\"hit\""))
        #expect(contents.contains("\"agentstudio.performance.commandbar.invalidation_reason\":\"open_generation\""))
        #expect(
            contents.contains(
                "\"agentstudio.performance.commandbar.invalidation_reason\":\"query_meaningful_transition\""
            )
        )
    }

    @Test("whitespace-only root input stays in the empty projection and passes an empty fuzzy query")
    func whitespaceOnlyRootInputReusesEmptyProjection() {
        let state = CommandBarState()
        state.show(prefix: "#")
        let session = CommandBarResultSession(
            store: WorkspaceStore(),
            repoCache: RepoCacheAtom(),
            dispatcher: FakeAppCommandDispatcher()
        )

        _ = session.snapshot(state: state)
        state.rawInput = "# \n  "
        let snapshot = session.snapshot(state: state)

        #expect(session.rootItemSnapshotBuildCount == 1)
        #expect(session.rootItemSnapshotCacheHitCount == 1)
        #expect(snapshot.searchDocument.query.isEmpty)
    }

    @Test("root input trims edges for substring search and preserves internal whitespace")
    func rootInputUsesOneNormalizedQuery() {
        let state = CommandBarState()
        state.show(prefix: "#")
        state.rawInput = "#   repo   feature  "
        let session = CommandBarResultSession(
            store: WorkspaceStore(),
            repoCache: RepoCacheAtom(),
            dispatcher: FakeAppCommandDispatcher()
        )

        let snapshot = session.snapshot(state: state)

        #expect(snapshot.searchDocument.query == "repo   feature")
    }

    @Test("clearing a meaningful root query rebuilds the empty projection once")
    func clearingMeaningfulRootQueryReversesProjectionBoundary() {
        let state = CommandBarState()
        state.show(prefix: ">")
        let session = CommandBarResultSession(
            store: WorkspaceStore(),
            repoCache: RepoCacheAtom(),
            dispatcher: FakeAppCommandDispatcher()
        )

        _ = session.snapshot(state: state)
        state.rawInput = "> close"
        _ = session.prepareSearch(state: state)
        state.rawInput = "> close pane"
        _ = session.prepareSearch(state: state)
        state.rawInput = "> "
        _ = session.snapshot(state: state)

        #expect(session.rootItemSnapshotBuildCount == 3)
        #expect(session.rootItemSnapshotCacheHitCount == 1)
    }

    @Test("pending search preserves the selected row until an answer applies")
    func pendingSearchPreservesStableRowIdentity() throws {
        let store = WorkspaceStore()
        let firstRepository = store.addRepo(at: URL(filePath: "/tmp/command-bar-selection-first"))
        let selectedRepository = store.addRepo(at: URL(filePath: "/tmp/command-bar-selection-selected"))
        let state = CommandBarState()
        state.show(prefix: "#")
        let dispatcher = FakeAppCommandDispatcher()
        let session = CommandBarResultSession(
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: dispatcher
        )

        let emptySnapshot = session.snapshot(state: state)
        let selectedID = "repo-\(selectedRepository.id.uuidString)"
        state.selectedIndex = try #require(
            emptySnapshot.displayedItems.firstIndex { $0.id == selectedID }
        )
        #expect(firstRepository.id != selectedRepository.id)
        state.rawInput = "# selected"
        let pendingSnapshot = session.snapshot(state: state)

        #expect(pendingSnapshot.selectedItem?.id == selectedID)
        #expect(pendingSnapshot.displayedItems[state.selectedIndex].id == selectedID)
    }

    @Test("pending search keeps the previously displayed rows")
    func pendingSearchKeepsPreviousRows() {
        let state = CommandBarState()
        state.show(prefix: ">")
        let session = CommandBarResultSession(
            store: WorkspaceStore(),
            repoCache: RepoCacheAtom(),
            dispatcher: FakeAppCommandDispatcher()
        )

        let initialSnapshot = session.snapshot(state: state)
        state.selectedIndex = max(0, initialSnapshot.displayedItems.count - 1)
        state.rawInput = "> no command can match this sentinel"
        let pendingSnapshot = session.snapshot(state: state)

        #expect(pendingSnapshot.displayedItems.map(\.id) == initialSnapshot.displayedItems.map(\.id))
        #expect(pendingSnapshot.selectedItem?.id == initialSnapshot.displayedItems.last?.id)
    }

    @Test("selection wraps symmetrically through consecutive result snapshots")
    func selectionWrapsSymmetricallyThroughResultSnapshots() throws {
        let state = CommandBarState()
        state.show(prefix: ">")
        let session = CommandBarResultSession(
            store: WorkspaceStore(),
            repoCache: RepoCacheAtom(),
            dispatcher: FakeAppCommandDispatcher()
        )
        let initialSnapshot = session.snapshot(state: state)
        let finalIndex = initialSnapshot.displayedItems.count - 1
        let firstItemID = try #require(initialSnapshot.displayedItems.first?.id)
        let finalItemID = try #require(initialSnapshot.displayedItems.last?.id)

        state.selectedIndex = finalIndex
        _ = session.snapshot(state: state)
        state.moveSelectionDown(totalItems: initialSnapshot.totalItems)
        let downWrappedSnapshot = session.snapshot(state: state)

        #expect(state.selectedIndex == 0)
        #expect(downWrappedSnapshot.selectedItem?.id == firstItemID)

        state.moveSelectionUp(totalItems: downWrappedSnapshot.totalItems)
        let upWrappedSnapshot = session.snapshot(state: state)

        #expect(state.selectedIndex == finalIndex)
        #expect(upWrappedSnapshot.selectedItem?.id == finalItemID)
    }

    @Test("# root item snapshot rebuilds when observed topology changes")
    func rootItemSnapshotRebuildsWhenObservedTopologyChangesInSameMainActorTurn() {
        let store = WorkspaceStore()
        let state = CommandBarState()
        state.show(prefix: "#")

        let session = CommandBarResultSession(
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: FakeAppCommandDispatcher()
        )

        _ = session.snapshot(state: state)
        let repo = store.addRepo(at: URL(filePath: "/tmp/command-bar-root-cache"))
        let snapshot = session.snapshot(state: state)

        #expect(session.rootItemSnapshotBuildCount == 2)
        #expect(snapshot.allItems.contains { $0.id == "repo-\(repo.id.uuidString)" })
    }

    @Test("# root rebuild touches only the changed repository artifact at fleet scale")
    func rootItemSnapshotRebuildsOnlyChangedRepositoryArtifactAtFleetScale() throws {
        let store = WorkspaceStore()
        let repositories = (0..<121).map { repositoryIndex in
            store.addRepo(
                at: URL(filePath: "/tmp/command-bar-incremental-\(repositoryIndex)")
            )
        }
        let state = CommandBarState()
        state.show(prefix: "#")
        let dispatcher = FakeAppCommandDispatcher()
        let session = CommandBarResultSession(
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: dispatcher
        )

        _ = session.snapshot(state: state)
        let initialRepositoryArtifactBuildCount = session.repoScopeItemBuildCount
        let changedRepository = repositories[60]
        try store.mutationCoordinator.setRepoTags(
            ["changed-key"],
            repositoryID: changedRepository.id
        )
        let updatedSnapshot = session.snapshot(state: state)

        #expect(initialRepositoryArtifactBuildCount == 121)
        #expect(dispatcher.bridgeTargetLookupCount == 0)
        #expect(session.repoScopeItemBuildCount == initialRepositoryArtifactBuildCount + 1)
        #expect(
            updatedSnapshot.allItems
                .first { $0.id == "repo-\(changedRepository.id.uuidString)" }?
                .keywords.contains("changed-key") == true
        )
    }

    @Test("# root item invalidation publishes an observable session change")
    func rootItemInvalidationPublishesObservableSessionChange() {
        let store = WorkspaceStore()
        let state = CommandBarState()
        state.show(prefix: "#")
        state.rawInput = "# repo"
        let invalidationCounter = CommandBarResultSessionInvalidationCounter()

        let session = CommandBarResultSession(
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: FakeAppCommandDispatcher()
        )

        withObservationTracking {
            _ = session.snapshot(state: state).displayedItems.map(\.id)
        } onChange: {
            invalidationCounter.record()
        }

        let repo = store.addRepo(at: URL(filePath: "/tmp/command-bar-root-cache-observable"))
        let prepared = session.prepareSearch(state: state)

        #expect(invalidationCounter.count >= 1)
        #expect(prepared.documentSet.documents.contains { $0.itemId.rawValue == "repo-\(repo.id.uuidString)" })
    }

    @Test("# root item snapshot rebuilds after a new command bar session starts")
    func rootItemSnapshotRebuildsAfterNewCommandBarSessionStarts() {
        let state = CommandBarState()
        state.show(prefix: "#")

        let session = CommandBarResultSession(
            store: WorkspaceStore(),
            repoCache: RepoCacheAtom(),
            dispatcher: FakeAppCommandDispatcher()
        )

        _ = session.snapshot(state: state)
        state.dismiss()
        state.show(prefix: "#")
        _ = session.snapshot(state: state)

        #expect(session.rootItemSnapshotBuildCount == 2)
    }

    @Test("# root item observer ignores stale registrations from previous sessions")
    func rootItemObserverIgnoresStaleRegistrationsFromPreviousSessions() {
        let store = WorkspaceStore()
        let state = CommandBarState()
        state.show(prefix: "#")

        let session = CommandBarResultSession(
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: FakeAppCommandDispatcher()
        )

        _ = session.snapshot(state: state)
        state.dismiss()
        state.show(prefix: "#")
        _ = session.snapshot(state: state)
        state.dismiss()
        state.show(prefix: "#")
        _ = session.snapshot(state: state)

        let revisionBeforeChange = session.rootItemSnapshotInvalidationRevision
        _ = store.addRepo(at: URL(filePath: "/tmp/command-bar-stale-observer"))

        #expect(session.rootItemSnapshotInvalidationRevision == revisionBeforeChange + 1)
    }
}

private final class CommandBarResultSessionInvalidationCounter: @unchecked Sendable {
    private(set) var count = 0

    func record() {
        count += 1
    }
}
