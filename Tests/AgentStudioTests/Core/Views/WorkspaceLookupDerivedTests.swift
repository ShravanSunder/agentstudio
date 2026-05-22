import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceLookupDerivedTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test
    func tabContainingPane_returnsOwningTab() {
        withTestAtomRegistry { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let pane = store.createPane(source: .floating(launchDirectory: nil, title: "Pane A"))
            let tab = Tab(paneId: pane.id)
            store.appendTab(tab)

            let resolvedTab = atom(\.workspaceLookup).tabContaining(paneId: pane.id)

            #expect(resolvedTab?.id == tab.id)
        }
    }

    @Test
    func repoAndWorktreeContainingCwd_resolvesNestedPath() {
        withTestAtomRegistry { atoms in
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
            store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])

            let resolved = atom(\.workspaceLookup).repoAndWorktree(
                containing: URL(filePath: "/tmp/workspace-lookup/feature-name/Sources/App")
            )

            #expect(resolved?.repo.id == repo.id)
            #expect(resolved?.worktree.id == worktree.id)
        }
    }

    @Test
    func paneLocationsForWorktree_returnsTabAndPaneOrder() {
        withTestAtomRegistry { atoms in
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
            store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])

            let paneA = store.createPane(
                source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
                title: "Pane A"
            )
            let paneB = store.createPane(
                source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
                title: "Pane B"
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
    func paneLocationsForWorktree_excludesBackgroundedPanes() {
        withTestAtomRegistry { atoms in
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
            store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])

            let activePane = store.createPane(
                source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
                title: "Active Pane"
            )
            let backgroundedPane = store.createPane(
                source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
                title: "Backgrounded Pane",
                residency: .backgrounded
            )
            let tab = Tab(paneId: activePane.id)
            store.appendTab(tab)

            let locations = atom(\.workspaceLookup).paneLocations(for: worktree.id)

            #expect(locations.map(\.paneId) == [activePane.id])
            #expect(!locations.map(\.paneId).contains(backgroundedPane.id))
        }
    }
}
