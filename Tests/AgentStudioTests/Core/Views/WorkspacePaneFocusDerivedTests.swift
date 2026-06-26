import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspacePaneFocusDerivedTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test
    func emptyWorkspaceHasNoActiveContext() {
        withTestAtomRegistry { _ in
            let focus = atom(\.workspacePaneFocus).currentFocus(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane),
                workspaceFocusOwner: atom(\.workspaceFocusOwner)
            )

            #expect(focus.paneContentType == .noActivePane)
            #expect(focus.satisfiedRequirements.isEmpty)
        }
    }

    @Test
    func activeTerminalTabReportsFocusRequirements() {
        withTestAtomRegistry { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.repositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let pane = store.createPane()
            let tab = Tab(paneId: pane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)

            let focus = atom(\.workspacePaneFocus).currentFocus(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane),
                workspaceFocusOwner: atom(\.workspaceFocusOwner)
            )

            #expect(focus.paneContentType == .terminal)
            #expect(focus.activeRepoId == nil)
            #expect(focus.activeWorktreeId == nil)
            #expect(focus.satisfiedRequirements.contains(.hasActiveTab))
            #expect(focus.satisfiedRequirements.contains(.hasActivePane))
            #expect(focus.satisfiedRequirements.contains(.paneIsTerminal))
            #expect(!focus.satisfiedRequirements.contains(.hasDrawerPanes))
            #expect(!focus.satisfiedRequirements.contains(.hasMultiplePanes))
            #expect(!focus.satisfiedRequirements.contains(.hasArrangements))
        }
    }

    @Test
    func drawerAndArrangementRequirementsAreReported() {
        withTestAtomRegistry { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.repositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let paneA = store.createPane()
            let paneB = store.createPane()
            var tab = Tab(paneId: paneA.id)
            let namedArrangement = PaneArrangement(
                name: "Review",
                isDefault: false,
                layout: tab.layout
            )
            tab.arrangements.append(namedArrangement)
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            store.insertPane(
                paneB.id,
                inTab: tab.id,
                at: paneA.id,
                direction: .horizontal,
                position: .after, sizingMode: .halveTarget
            )
            _ = store.addDrawerPane(to: paneA.id)
            store.setActivePane(paneA.id, inTab: tab.id)

            let focus = atom(\.workspacePaneFocus).currentFocus(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane),
                workspaceFocusOwner: atom(\.workspaceFocusOwner)
            )

            #expect(focus.satisfiedRequirements.contains(.hasMultiplePanes))
            #expect(focus.satisfiedRequirements.contains(.hasArrangements))
            #expect(focus.satisfiedRequirements.contains(.hasDrawer))
            #expect(focus.satisfiedRequirements.contains(.hasDrawerPanes))
        }
    }

    @Test
    func worktreeBackedPane_populatesActiveRepoAndWorktreeIds() {
        withTestAtomRegistry { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.repositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let repo = store.addRepo(at: URL(filePath: "/tmp/workspace-focus-derived"))
            let worktree = Worktree(
                repoId: repo.id,
                name: "feature-name",
                path: URL(filePath: "/tmp/workspace-focus-derived/feature-name")
            )
            store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])
            let pane = store.createPane(
                launchDirectory: worktree.path,
                title: "Terminal",
                facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path),
            )
            let tab = Tab(paneId: pane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)

            let focus = atom(\.workspacePaneFocus).currentFocus(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane),
                workspaceFocusOwner: atom(\.workspaceFocusOwner)
            )

            #expect(focus.activeRepoId == repo.id)
            #expect(focus.activeWorktreeId == worktree.id)
        }
    }

    @Test
    func staleEmptyDrawerScope_isIgnoredWhenDrawerIsCollapsed() {
        withTestAtomRegistry { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.repositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let pane = store.createPane()
            let tab = Tab(paneId: pane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            atoms.workspaceFocusOwner.focusEmptyDrawer(parentPaneId: pane.id)

            let focus = atom(\.workspacePaneFocus).currentFocus(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane),
                workspaceFocusOwner: atom(\.workspaceFocusOwner)
            )

            #expect(focus.drawerFocusState == .inactive)
            #expect(!focus.satisfiedRequirements.contains(.hasEmptyDrawerFocus))
        }
    }

    @Test
    func staleDrawerPaneOwner_fallsBackToRealActiveDrawerPane() {
        withTestAtomRegistry { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.repositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let parentPane = store.createPane()
            let tab = Tab(paneId: parentPane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            store.setActivePane(parentPane.id, inTab: tab.id)

            let firstDrawerPane = store.addDrawerPane(to: parentPane.id)
            let secondDrawerPane = store.addDrawerPane(to: parentPane.id)
            let staleDrawerPane = firstDrawerPane?.id
            let activeDrawerPane = secondDrawerPane?.id

            guard let staleDrawerPane, let activeDrawerPane else {
                Issue.record("Expected two drawer panes")
                return
            }

            atoms.workspaceFocusOwner.focusDrawerPane(parentPaneId: parentPane.id, paneId: staleDrawerPane)

            let focus = atom(\.workspacePaneFocus).currentFocus(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane),
                workspaceFocusOwner: atom(\.workspaceFocusOwner)
            )

            #expect(
                focus.drawerFocusState == .drawerPane(parentPaneId: parentPane.id, paneId: activeDrawerPane)
            )
            #expect(focus.satisfiedRequirements.contains(.hasFocusedDrawerPane))
        }
    }

    @Test
    func focusedDrawerPane_reportsDrawerPaneIdentityAndMetadataNotParent() {
        withTestAtomRegistry { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.repositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let parentRepoId = UUID()
            let parentWorktreeId = UUID()
            let drawerRepoId = UUID()
            let drawerWorktreeId = UUID()
            let parentPane = store.createPane(
                launchDirectory: URL(filePath: "/tmp/parent-worktree"),
                title: "Parent",
                facets: PaneContextFacets(
                    repoId: parentRepoId,
                    worktreeId: parentWorktreeId,
                    cwd: URL(filePath: "/tmp/parent-worktree")
                )
            )
            let tab = Tab(paneId: parentPane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            store.setActivePane(parentPane.id, inTab: tab.id)

            guard
                let drawerPane = atoms.workspacePane.addDrawerPane(
                    to: parentPane.id,
                    content: .webview(WebviewState(url: URL(string: "https://drawer.example")!)),
                    metadata: PaneMetadata(
                        launchDirectory: URL(filePath: "/tmp/drawer-worktree"),
                        title: "Drawer Web",
                        facets: PaneContextFacets(
                            repoId: drawerRepoId,
                            worktreeId: drawerWorktreeId,
                            cwd: URL(filePath: "/tmp/drawer-worktree")
                        )
                    )
                )
            else {
                Issue.record("Expected drawer pane")
                return
            }

            atoms.workspaceFocusOwner.focusDrawerPane(parentPaneId: parentPane.id, paneId: drawerPane.id)

            let focus = atom(\.workspacePaneFocus).currentFocus(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane),
                workspaceFocusOwner: atom(\.workspaceFocusOwner)
            )

            // Focus state correctly identifies the drawer child.
            #expect(focus.drawerFocusState == .drawerPane(parentPaneId: parentPane.id, paneId: drawerPane.id))
            #expect(focus.activePaneId == drawerPane.id)
            #expect(focus.activeRepoId == drawerRepoId)
            #expect(focus.activeWorktreeId == drawerWorktreeId)
            #expect(focus.paneContentType == .webview)
        }
    }
}
