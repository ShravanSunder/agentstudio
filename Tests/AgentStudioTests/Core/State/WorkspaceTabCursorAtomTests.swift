import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceTabCursorAtomTests {
    @Test
    func hydrate_selectsProvidedTabWhenAvailable() {
        let firstTabId = UUID()
        let secondTabId = UUID()
        let atom = WorkspaceTabCursorAtom()

        atom.hydrate(activeTabId: secondTabId, availableTabIds: [firstTabId, secondTabId])

        #expect(atom.activeTabId == secondTabId)
    }

    @Test
    func hydrate_fallsBackToFirstTabWhenProvidedTabIsStale() {
        let firstTabId = UUID()
        let atom = WorkspaceTabCursorAtom()

        atom.hydrate(activeTabId: UUID(), availableTabIds: [firstTabId])

        #expect(atom.activeTabId == firstTabId)
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
