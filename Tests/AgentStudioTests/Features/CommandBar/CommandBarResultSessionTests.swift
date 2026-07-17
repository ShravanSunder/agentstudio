import Foundation
import Observation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct CommandBarResultSessionTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("result session owns item filtering, grouping, and selection")
    func resultSessionOwnsFilteringGroupingAndSelection() {
        let store = WorkspaceStore()
        let repoCache = RepoCacheAtom()
        let state = CommandBarState()
        state.show(prefix: ">")
        state.rawInput = "> close"

        let session = CommandBarResultSession(
            store: store,
            repoCache: repoCache,
            dispatcher: .shared
        )

        let snapshot = session.snapshot(state: state)

        #expect(
            snapshot.filteredItems.allSatisfy { item in
                item.title.localizedCaseInsensitiveContains("close")
                    || item.keywords.contains { $0.localizedCaseInsensitiveContains("close") }
            })
        #expect(
            snapshot.displayedItems.map(\.id)
                == CommandBarDataSource.displayItems(from: snapshot.groups).map(\.id)
        )
        #expect(snapshot.selectedItem?.id == snapshot.displayedItems.first?.id)
        #expect(snapshot.totalItems == snapshot.displayedItems.count)
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
            dispatcher: .shared
        )

        let snapshot = session.snapshot(state: state)

        #expect(snapshot.allItems.map(\.id) == ["nested-open"])
        #expect(snapshot.selectedItem?.id == "nested-open")
    }

    @Test("# root item snapshot is reused while only the query changes")
    func rootItemSnapshotIsReusedWhileOnlyQueryChanges() {
        let store = WorkspaceStore()
        let state = CommandBarState()
        state.show(prefix: "#")

        let session = CommandBarResultSession(
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: .shared
        )

        _ = session.snapshot(state: state)
        state.rawInput = "# repo"
        _ = session.snapshot(state: state)
        state.rawInput = "# repo feature"
        _ = session.snapshot(state: state)

        #expect(session.rootItemSnapshotBuildCount == 1)
        #expect(session.rootItemSnapshotCacheHitCount == 2)
    }

    @Test("# root item snapshot rebuilds when observed topology changes")
    func rootItemSnapshotRebuildsWhenObservedTopologyChangesInSameMainActorTurn() {
        let store = WorkspaceStore()
        let state = CommandBarState()
        state.show(prefix: "#")

        let session = CommandBarResultSession(
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: .shared
        )

        _ = session.snapshot(state: state)
        let repo = store.addRepo(at: URL(filePath: "/tmp/command-bar-root-cache"))
        let snapshot = session.snapshot(state: state)

        #expect(session.rootItemSnapshotBuildCount == 2)
        #expect(snapshot.allItems.contains { $0.id == "repo-\(repo.id.uuidString)" })
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
            dispatcher: .shared
        )

        withObservationTracking {
            _ = session.snapshot(state: state).displayedItems.map(\.id)
        } onChange: {
            invalidationCounter.record()
        }

        let repo = store.addRepo(at: URL(filePath: "/tmp/command-bar-root-cache-observable"))
        let snapshot = session.snapshot(state: state)

        #expect(invalidationCounter.count >= 1)
        #expect(snapshot.allItems.contains { $0.id == "repo-\(repo.id.uuidString)" })
    }

    @Test("# root item snapshot rebuilds after a new command bar session starts")
    func rootItemSnapshotRebuildsAfterNewCommandBarSessionStarts() {
        let state = CommandBarState()
        state.show(prefix: "#")

        let session = CommandBarResultSession(
            store: WorkspaceStore(),
            repoCache: RepoCacheAtom(),
            dispatcher: .shared
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
            dispatcher: .shared
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
