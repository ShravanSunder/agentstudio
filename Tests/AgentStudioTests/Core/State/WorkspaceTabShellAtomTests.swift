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
}
