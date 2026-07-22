import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("SidebarVisibleWorktreesRuntimeAtom")
struct SidebarVisibleWorktreesRuntimeAtomTests {
    @Test("visible worktree runtime atom replaces and clears visible ids")
    func visibleWorktreeRuntimeAtomReplacesAndClearsVisibleIds() {
        let atom = SidebarVisibleWorktreesRuntimeAtom()
        let firstWorktreeId = UUID()
        let secondWorktreeId = UUID()

        #expect(atom.visibleWorktreeIds.isEmpty)

        atom.setVisibleWorktreeIds([firstWorktreeId, secondWorktreeId])
        #expect(atom.visibleWorktreeIds == [firstWorktreeId, secondWorktreeId])

        atom.setVisibleWorktreeIds([secondWorktreeId])
        #expect(atom.visibleWorktreeIds == [secondWorktreeId])

        atom.clear()
        #expect(atom.visibleWorktreeIds.isEmpty)
    }
}
