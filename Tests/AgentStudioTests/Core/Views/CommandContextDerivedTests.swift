import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceFocusDerivedTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test
    func emptyWorkspaceHasNoActiveContext() {
        withTestAtomRegistry { _ in
            let focus = atom(\.workspaceFocus).currentFocus(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane)
            )

            #expect(focus.paneContentType == .noActivePane)
            #expect(focus.satisfiedRequirements.isEmpty)
        }
    }

    @Test
    func activeTerminalTabReportsFocusRequirements() {
        withTestAtomRegistry { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let pane = store.createPane(source: .floating(launchDirectory: nil, title: "Pane A"))
            let tab = Tab(paneId: pane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)

            let focus = atom(\.workspaceFocus).currentFocus(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane)
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
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let paneA = store.createPane(source: .floating(launchDirectory: nil, title: "Pane A"))
            let paneB = store.createPane(source: .floating(launchDirectory: nil, title: "Pane B"))
            var tab = Tab(paneId: paneA.id)
            let namedArrangement = PaneArrangement(
                name: "Review",
                isDefault: false,
                layout: tab.layout,
                visiblePaneIds: Set(tab.activePaneIds)
            )
            tab.arrangements.append(namedArrangement)
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            store.insertPane(
                paneB.id,
                inTab: tab.id,
                at: paneA.id,
                direction: .horizontal,
                position: .after
            )
            _ = store.addDrawerPane(to: paneA.id)

            let focus = atom(\.workspaceFocus).currentFocus(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane)
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
                catalogAtom: atoms.workspaceRepositoryTopology,
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
                source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
                title: "Terminal"
            )
            let tab = Tab(paneId: pane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)

            let focus = atom(\.workspaceFocus).currentFocus(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane)
            )

            #expect(focus.activeRepoId == repo.id)
            #expect(focus.activeWorktreeId == worktree.id)
        }
    }
}
