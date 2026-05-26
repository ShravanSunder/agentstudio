import Foundation
import Testing

@testable import AgentStudio

@Suite("ArrangementPanelTabPresentationState")
struct ArrangementPanelTabPresentationStateTests {
    @Test("present records the owning tab")
    func presentRecordsOwningTab() {
        let tabId = UUID()
        var state = ArrangementPanelTabPresentationState()

        state.present(tabId: tabId)

        #expect(state.isPresented)
        #expect(state.presentedTabId == tabId)
    }

    @Test("active tab change closes panel owned by previous tab")
    func activeTabChangeClosesPanelOwnedByPreviousTab() {
        let firstTabId = UUID()
        let secondTabId = UUID()
        var state = ArrangementPanelTabPresentationState()
        state.present(tabId: firstTabId)

        state.activeTabDidChange(to: secondTabId)

        #expect(!state.isPresented)
        #expect(state.presentedTabId == nil)
    }

    @Test("active tab change keeps panel owned by same tab")
    func activeTabChangeKeepsPanelOwnedBySameTab() {
        let tabId = UUID()
        var state = ArrangementPanelTabPresentationState()
        state.present(tabId: tabId)

        state.activeTabDidChange(to: tabId)

        #expect(state.isPresented)
        #expect(state.presentedTabId == tabId)
    }

    @Test("toggle opens for active tab and closes when already open")
    func toggleOpensForActiveTabAndClosesWhenAlreadyOpen() {
        let tabId = UUID()
        var state = ArrangementPanelTabPresentationState()

        state.toggle(activeTabId: tabId)
        #expect(state.isPresented)
        #expect(state.presentedTabId == tabId)

        state.toggle(activeTabId: tabId)
        #expect(!state.isPresented)
        #expect(state.presentedTabId == nil)
    }

    @Test("set presented false clears owner")
    func setPresentedFalseClearsOwner() {
        let tabId = UUID()
        var state = ArrangementPanelTabPresentationState()
        state.present(tabId: tabId)

        state.setPresented(false, activeTabId: tabId)

        #expect(!state.isPresented)
        #expect(state.presentedTabId == nil)
    }
}
