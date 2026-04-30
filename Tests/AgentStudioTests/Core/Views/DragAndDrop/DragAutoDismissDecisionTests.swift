import Foundation
import Testing

@testable import AgentStudio

@Suite
struct DragAutoDismissDecisionTests {
    private let sourceTab = UUID()
    private let destinationTab = UUID()
    private let sourcePaneId = UUID()
    private let drawerParent = UUID()

    private func mainPayload() -> PaneDragPayload {
        PaneDragPayload(paneId: sourcePaneId, tabId: sourceTab, drawerParentPaneId: nil)
    }

    private func drawerChildPayload() -> PaneDragPayload {
        PaneDragPayload(paneId: sourcePaneId, tabId: sourceTab, drawerParentPaneId: drawerParent)
    }

    @Test
    func mainDrag_destinationHasExpandedDrawer_returnsDrawerParent() {
        let expandedDrawerInDestination = UUID()

        let result = DragAutoDismissDecision.shouldAutoDismiss(
            payload: mainPayload(),
            destinationTabId: destinationTab,
            destinationExpandedDrawerParentPaneId: expandedDrawerInDestination
        )

        #expect(result == expandedDrawerInDestination)
    }

    @Test
    func mainDrag_destinationNoDrawer_returnsNil() {
        let result = DragAutoDismissDecision.shouldAutoDismiss(
            payload: mainPayload(),
            destinationTabId: destinationTab,
            destinationExpandedDrawerParentPaneId: nil
        )

        #expect(result == nil)
    }

    @Test
    func drawerChildDrag_neverDismisses() {
        let expandedDrawerInDestination = UUID()

        let result = DragAutoDismissDecision.shouldAutoDismiss(
            payload: drawerChildPayload(),
            destinationTabId: destinationTab,
            destinationExpandedDrawerParentPaneId: expandedDrawerInDestination
        )

        #expect(result == nil)
    }

    @Test
    func mainDrag_destinationIsSourceTab_returnsNil() {
        let expandedDrawerInSource = UUID()

        let result = DragAutoDismissDecision.shouldAutoDismiss(
            payload: mainPayload(),
            destinationTabId: sourceTab,
            destinationExpandedDrawerParentPaneId: expandedDrawerInSource
        )

        #expect(result == nil)
    }
}
