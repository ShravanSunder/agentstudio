import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceTabCursorAtomTests {
    @Test
    func replacement_selectsProvidedTab() {
        let firstTabId = UUID()
        let secondTabId = UUID()
        let atom = WorkspaceTabCursorAtom()

        atom.replaceActiveTab(secondTabId)

        #expect(atom.activeTabId == secondTabId)
    }

    @Test
    func replacement_canClearActiveTab() {
        let firstTabId = UUID()
        let atom = WorkspaceTabCursorAtom()

        atom.replaceActiveTab(firstTabId)
        atom.replaceActiveTab(nil)

        #expect(atom.activeTabId == nil)
    }

    @Test
    func removingActiveTabSelectsLastRemainingTab() {
        let firstTabId = UUID()
        let secondTabId = UUID()
        let atom = WorkspaceTabCursorAtom()
        atom.selectTab(secondTabId, availableTabIds: [firstTabId, secondTabId])

        atom.removeTab(secondTabId, remainingTabIds: [firstTabId])

        #expect(atom.activeTabId == firstTabId)
    }

    @Test
    func removingInactiveTabKeepsActiveTab() {
        let firstTabId = UUID()
        let secondTabId = UUID()
        let atom = WorkspaceTabCursorAtom()
        atom.selectTab(firstTabId, availableTabIds: [firstTabId, secondTabId])

        atom.removeTab(secondTabId, remainingTabIds: [firstTabId])

        #expect(atom.activeTabId == firstTabId)
    }

    @Test
    func selectTabRejectsMissingTab() {
        let activeTabId = UUID()
        let missingTabId = UUID()
        let atom = WorkspaceTabCursorAtom()
        atom.selectTab(activeTabId, availableTabIds: [activeTabId])

        atom.selectTab(missingTabId, availableTabIds: [activeTabId])

        #expect(atom.activeTabId == activeTabId)
    }

}
