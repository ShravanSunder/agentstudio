import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceTabShellAtomTests {
    @Test
    func appendTabShell_setsActiveTabId() {
        let atom = WorkspaceTabShellAtom()
        let shell = TabShell(id: UUID(), name: "One")

        atom.appendTabShell(shell)

        #expect(atom.tabShells == [shell])
        #expect(atom.activeTabId == shell.id)
    }

    @Test
    func removeTabShell_removesAndUpdatesActiveTabId() {
        let atom = WorkspaceTabShellAtom()
        let first = TabShell(id: UUID(), name: "One")
        let second = TabShell(id: UUID(), name: "Two")
        atom.appendTabShell(first)
        atom.appendTabShell(second)

        atom.removeTabShell(second.id)

        #expect(atom.tabShells == [first])
        #expect(atom.activeTabId == first.id)
    }

    @Test
    func moveTabShell_reordersShells() {
        let atom = WorkspaceTabShellAtom()
        let first = TabShell(id: UUID(), name: "One")
        let second = TabShell(id: UUID(), name: "Two")
        atom.appendTabShell(first)
        atom.appendTabShell(second)

        atom.moveTab(fromId: second.id, toIndex: 0)

        #expect(atom.tabShells.map { $0.id } == [second.id, first.id])
    }

    @Test
    func renameTabShell_updatesName() {
        let atom = WorkspaceTabShellAtom()
        let shell = TabShell(id: UUID(), name: "One")
        atom.appendTabShell(shell)

        atom.renameTab(shell.id, name: "Review Queue")

        #expect(atom.tabShells.first?.name == "Review Queue")
    }

    @Test
    func removeTabShell_middleActiveRemoval_activatesLastRemainingTab() {
        let atom = WorkspaceTabShellAtom()
        let first = TabShell(id: UUID(), name: "One")
        let second = TabShell(id: UUID(), name: "Two")
        let third = TabShell(id: UUID(), name: "Three")
        atom.appendTabShell(first)
        atom.appendTabShell(second)
        atom.appendTabShell(third)
        atom.setActiveTab(second.id)

        atom.removeTabShell(second.id)

        #expect(atom.tabShells.map(\.id) == [first.id, third.id])
        #expect(atom.activeTabId == third.id)
    }

    @Test
    func moveTabByDelta_reordersShells() {
        let atom = WorkspaceTabShellAtom()
        let first = TabShell(id: UUID(), name: "One")
        let second = TabShell(id: UUID(), name: "Two")
        let third = TabShell(id: UUID(), name: "Three")
        atom.appendTabShell(first)
        atom.appendTabShell(second)
        atom.appendTabShell(third)

        atom.moveTabByDelta(tabId: first.id, delta: 2)

        #expect(atom.tabShells.map(\.id) == [second.id, third.id, first.id])
    }

    @Test
    func insertTabShell_preservesExistingActiveTab() {
        let atom = WorkspaceTabShellAtom()
        let first = TabShell(id: UUID(), name: "One")
        let second = TabShell(id: UUID(), name: "Two")
        atom.appendTabShell(first)
        atom.setActiveTab(first.id)

        atom.insertTabShell(second, at: 0)

        #expect(atom.tabShells.map(\.id) == [second.id, first.id])
        #expect(atom.activeTabId == first.id)
    }

    @Test
    func setActiveTab_rejectsMissingTabId() {
        let atom = WorkspaceTabShellAtom()
        let first = TabShell(id: UUID(), name: "One")
        atom.appendTabShell(first)

        atom.setActiveTab(UUID())

        #expect(atom.activeTabId == first.id)
    }

    @Test
    func hydrate_withStaleActiveTabId_fallsBackToFirstTab() {
        let pane = UUID()
        let arrangement = PaneArrangement(name: "Default", isDefault: true, layout: Layout(paneId: pane))
        let tab = Tab(
            name: "One",
            allPaneIds: [pane],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: pane
        )
        let atom = WorkspaceTabShellAtom()

        atom.hydrate(persistedTabs: [tab], activeTabId: UUID())

        #expect(atom.activeTabId == tab.id)
    }
}
