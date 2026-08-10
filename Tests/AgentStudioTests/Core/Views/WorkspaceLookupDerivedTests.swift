import AgentStudioTestSupport
import Foundation
import Observation
import Testing

@testable import AgentStudioCore

private final class WorkspaceLookupObservationInvalidationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCount = 0

    var invalidationCount: Int {
        lock.withLock { storedCount }
    }

    func record() {
        lock.withLock {
            storedCount += 1
        }
    }
}

@MainActor
@Suite(.serialized)
struct WorkspaceLookupDerivedTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test
    func tabContainingPane_returnsOwningTab() {
        withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let pane = store.createPane()
            let tab = Tab(paneId: pane.id)
            store.appendTab(tab)

            let resolvedTab = atom(\.workspaceLookup).tabContaining(paneId: pane.id)

            #expect(resolvedTab?.id == tab.id)
        }
    }

    @Test
    func repoAndWorktreeContainingCwd_resolvesNestedPath() {
        withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let repo = store.addRepo(at: URL(filePath: "/tmp/workspace-lookup"))
            let worktree = Worktree(
                repoId: repo.id,
                name: "feature-name",
                path: URL(filePath: "/tmp/workspace-lookup/feature-name")
            )
            store.reconcileDiscoveredWorktrees(repo.id, worktrees: repo.worktrees + [worktree])

            let resolved = atom(\.workspaceLookup).repoAndWorktree(
                containing: URL(filePath: "/tmp/workspace-lookup/feature-name/Sources/App")
            )

            #expect(resolved?.repo.id == repo.id)
            #expect(resolved?.worktree.id == worktree.id)
        }
    }

    @Test
    func repoAndWorktreeContainingCwd_rebuildsLookupAfterTopologyMutation() {
        withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let repo = store.addRepo(at: URL(filePath: "/tmp/workspace-lookup-index"))
            let nestedWorktree = Worktree(
                repoId: repo.id,
                name: "feature-name",
                path: URL(filePath: "/tmp/workspace-lookup-index/feature-name")
            )
            store.reconcileDiscoveredWorktrees(repo.id, worktrees: repo.worktrees + [nestedWorktree])

            let nestedResolved = atom(\.workspaceLookup).repoAndWorktree(
                containing: URL(filePath: "/tmp/workspace-lookup-index/feature-name/Sources/App")
            )

            #expect(nestedResolved?.repo.id == repo.id)
            #expect(nestedResolved?.worktree.id == nestedWorktree.id)

            store.reconcileDiscoveredWorktrees(repo.id, worktrees: [])

            let removedResolved = atom(\.workspaceLookup).repoAndWorktree(
                containing: URL(filePath: "/tmp/workspace-lookup-index/feature-name/Sources/App")
            )

            #expect(removedResolved == nil)
        }
    }

    @Test
    func paneLocationsForWorktree_returnsTabAndPaneOrder() {
        withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let repo = store.addRepo(at: URL(filePath: "/tmp/worktree-pane-locations"))
            let worktree = Worktree(
                repoId: repo.id,
                name: "feature-name",
                path: URL(filePath: "/tmp/worktree-pane-locations/feature-name")
            )
            store.reconcileDiscoveredWorktrees(repo.id, worktrees: repo.worktrees + [worktree])

            let paneA = store.createPane(
                launchDirectory: worktree.path,
                title: "Pane A",
                facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path),
            )
            let paneB = store.createPane(
                launchDirectory: worktree.path,
                title: "Pane B",
                facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path),
            )
            let tab = Tab(paneId: paneA.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            store.insertPane(
                paneB.id,
                inTab: tab.id,
                at: paneA.id,
                direction: .horizontal,
                position: .after, sizingMode: .halveTarget
            )

            let locations = atom(\.workspaceLookup).paneLocations(for: worktree.id)

            #expect(
                locations == [
                    WorkspacePaneLocation(
                        paneId: paneA.id,
                        tabId: tab.id,
                        tabIndex: 0,
                        paneIndexInTab: 0,
                        isActiveInTab: false
                    ),
                    WorkspacePaneLocation(
                        paneId: paneB.id,
                        tabId: tab.id,
                        tabIndex: 0,
                        paneIndexInTab: 1,
                        isActiveInTab: true
                    ),
                ]
            )
        }
    }

    @Test
    func paneLocationsByWorktreeId_batchesAllActivePaneLocations() {
        withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let repo = store.addRepo(at: URL(filePath: "/tmp/worktree-pane-location-batch"))
            let worktreeA = Worktree(
                repoId: repo.id,
                name: "feature-a",
                path: URL(filePath: "/tmp/worktree-pane-location-batch/feature-a")
            )
            let worktreeB = Worktree(
                repoId: repo.id,
                name: "feature-b",
                path: URL(filePath: "/tmp/worktree-pane-location-batch/feature-b")
            )
            store.reconcileDiscoveredWorktrees(repo.id, worktrees: repo.worktrees + [worktreeA, worktreeB])

            let paneA = store.createPane(
                launchDirectory: worktreeA.path,
                title: "Pane A",
                facets: PaneContextFacets(repoId: repo.id, worktreeId: worktreeA.id, cwd: worktreeA.path)
            )
            let paneB = store.createPane(
                launchDirectory: worktreeB.path,
                title: "Pane B",
                facets: PaneContextFacets(repoId: repo.id, worktreeId: worktreeB.id, cwd: worktreeB.path)
            )
            let backgroundedPane = store.createPane(
                launchDirectory: worktreeA.path,
                title: "Backgrounded Pane",
                residency: .backgrounded,
                facets: PaneContextFacets(repoId: repo.id, worktreeId: worktreeA.id, cwd: worktreeA.path)
            )
            let tab = Tab(paneId: paneA.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            store.insertPane(
                paneB.id,
                inTab: tab.id,
                at: paneA.id,
                direction: .horizontal,
                position: .after,
                sizingMode: .halveTarget
            )

            let locationsByWorktree = atom(\.workspaceLookup).paneLocationsByWorktreeId(
                repositoryTopology: store.repositoryTopologyAtom,
                workspacePane: store.paneAtom,
                workspaceTab: WorkspaceTabLayoutDerived(
                    shellAtom: store.tabShellAtom,
                    arrangementAtom: store.tabArrangementAtom
                )
            )

            #expect(locationsByWorktree[worktreeA.id]?.map(\.paneId) == [paneA.id])
            #expect(locationsByWorktree[worktreeB.id]?.map(\.paneId) == [paneB.id])
            #expect(locationsByWorktree.values.flatMap { $0 }.allSatisfy { $0.paneId != backgroundedPane.id })
            #expect(locationsByWorktree[worktreeB.id]?.first?.paneIndexInTab == 1)
        }
    }

    @Test("pane location observation ignores titles and invalidates for structural CWD changes")
    func paneLocationObservationIsTitleInsensitive() {
        withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let repo = store.addRepo(at: URL(filePath: "/tmp/workspace-lookup-observation"))
            let worktree = try! #require(repo.worktrees.first)
            let pane = store.createPane(
                launchDirectory: worktree.path,
                title: "Initial title",
                facets: PaneContextFacets(cwd: worktree.path)
            )
            store.appendTab(Tab(paneId: pane.id))
            let workspaceTab = WorkspaceTabLayoutDerived(
                shellAtom: store.tabShellAtom,
                arrangementAtom: store.tabArrangementAtom
            )
            let invalidationRecorder = WorkspaceLookupObservationInvalidationRecorder()
            withObservationTracking {
                _ = atom(\.workspaceLookup).paneLocationsByWorktreeId(
                    repositoryTopology: store.repositoryTopologyAtom,
                    workspacePane: store.paneAtom,
                    workspaceTab: workspaceTab
                )
            } onChange: {
                invalidationRecorder.record()
            }

            store.paneAtom.updatePaneTitle(pane.id, title: "Updated title")

            #expect(invalidationRecorder.invalidationCount == 0)

            store.paneAtom.updatePaneCWD(
                pane.id,
                cwd: URL(filePath: "/tmp/workspace-lookup-observation-moved")
            )

            #expect(invalidationRecorder.invalidationCount == 1)
        }
    }

    @Test
    func paneLocationsForWorktree_excludesBackgroundedPanes() {
        withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let repo = store.addRepo(at: URL(filePath: "/tmp/workspace-lookup-backgrounded"))
            let worktree = Worktree(
                repoId: repo.id,
                name: "feature-name",
                path: URL(filePath: "/tmp/workspace-lookup-backgrounded/feature-name")
            )
            store.reconcileDiscoveredWorktrees(repo.id, worktrees: repo.worktrees + [worktree])

            let activePane = store.createPane(
                launchDirectory: worktree.path,
                title: "Active Pane",
                facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path),
            )
            let backgroundedPane = store.createPane(
                launchDirectory: worktree.path,
                title: "Backgrounded Pane",
                residency: .backgrounded,
                facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
            )
            let tab = Tab(paneId: activePane.id)
            store.appendTab(tab)

            let locations = atom(\.workspaceLookup).paneLocations(for: worktree.id)

            #expect(locations.map(\.paneId) == [activePane.id])
            #expect(!locations.map(\.paneId).contains(backgroundedPane.id))
        }
    }
}
