import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("PaneInboxPresentationAtom")
struct PaneInboxPresentationAtomTests {
    @Test("filter mode defaults to unread per parent pane")
    func filterModeDefaultsToUnreadPerParentPane() {
        let atom = PaneInboxPresentationAtom()
        let parentPaneId = UUID()

        #expect(atom.filterMode(for: parentPaneId) == .unread)
    }

    @Test("filter mode is stored independently per parent pane without persistence")
    func filterModeIsStoredIndependentlyPerParentPane() {
        let atom = PaneInboxPresentationAtom()
        let firstParentPaneId = UUID()
        let secondParentPaneId = UUID()

        atom.setFilterMode(.all, for: firstParentPaneId)

        #expect(atom.filterMode(for: firstParentPaneId) == .all)
        #expect(atom.filterMode(for: secondParentPaneId) == .unread)
    }

    @Test("toggle advances only the requested parent pane filter")
    func toggleAdvancesOnlyRequestedParentPaneFilter() {
        let atom = PaneInboxPresentationAtom()
        let firstParentPaneId = UUID()
        let secondParentPaneId = UUID()

        let updatedMode = atom.toggleFilterMode(for: firstParentPaneId)

        #expect(updatedMode == .all)
        #expect(atom.filterMode(for: firstParentPaneId) == .all)
        #expect(atom.filterMode(for: secondParentPaneId) == .unread)
    }

    @Test("prune removes filter modes for closed parent panes")
    func pruneRemovesFilterModesForClosedParentPanes() {
        let atom = PaneInboxPresentationAtom()
        let retainedParentPaneId = UUID()
        let closedParentPaneId = UUID()
        atom.setFilterMode(.all, for: retainedParentPaneId)
        atom.setFilterMode(.all, for: closedParentPaneId)

        atom.prune(retainingParentPaneIds: [retainedParentPaneId])

        #expect(atom.filterMode(for: retainedParentPaneId) == .all)
        #expect(atom.filterMode(for: closedParentPaneId) == .unread)
    }

    @Test("chrome override is consumed without changing explicit preferences")
    func chromeOverrideIsConsumedWithoutChangingExplicitPreferences() {
        let atom = PaneInboxPresentationAtom()

        atom.requestTemporaryOverride(contentMode: .rollUpAlerts, rowStateFilter: .unreadOnly)
        let override = atom.consumeTemporaryOverride()

        #expect(override?.contentMode == .rollUpAlerts)
        #expect(override?.rowStateFilter == .unreadOnly)
        #expect(atom.consumeTemporaryOverride() == nil)
    }
}
