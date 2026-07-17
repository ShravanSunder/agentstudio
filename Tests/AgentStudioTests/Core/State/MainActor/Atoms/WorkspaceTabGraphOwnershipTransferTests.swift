import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace tab graph pane ownership transfer")
struct WorkspaceTabGraphOwnershipTransferTests {
    @Test("transfers exact pane ownership between two keyed tabs")
    func transfersExactPaneOwnership() {
        // Arrange
        let atom = WorkspaceTabGraphAtom()
        let movedPaneID = UUIDv7.generate()
        let sourceRetainedPaneID = UUIDv7.generate()
        let destinationPaneID = UUIDv7.generate()
        let source = makeTransferTab(paneIDs: [movedPaneID, sourceRetainedPaneID])
        let destination = makeTransferTab(paneIDs: [destinationPaneID])
        atom.replaceTabStates([source, destination])
        let sourceReplacement = replacingPaneMembership(
            source,
            paneIDs: [sourceRetainedPaneID]
        )
        let destinationReplacement = replacingPaneMembership(
            destination,
            paneIDs: [destinationPaneID, movedPaneID]
        )

        // Act
        atom.replaceTabStatesTransferringPaneOwnership(
            source: sourceReplacement,
            destination: destinationReplacement
        )

        // Assert
        #expect(atom.tabState(source.tabId) == sourceReplacement)
        #expect(atom.tabState(destination.tabId) == destinationReplacement)
        #expect(atom.tabID(containingPane: movedPaneID) == destination.tabId)
        #expect(atom.tabID(containingPane: sourceRetainedPaneID) == source.tabId)
        #expect(atom.tabID(containingPane: destinationPaneID) == destination.tabId)
        #expect(atom.tabID(containingArrangement: source.arrangements[0].id) == source.tabId)
        #expect(atom.tabID(containingArrangement: destination.arrangements[0].id) == destination.tabId)
    }

    @Test("preserves 256 unrelated tabs and reverse indexes")
    func preservesUnrelatedTabsAndReverseIndexes() {
        // Arrange
        let atom = WorkspaceTabGraphAtom()
        let movedPaneID = UUIDv7.generate()
        let sourceRetainedPaneID = UUIDv7.generate()
        let destinationPaneID = UUIDv7.generate()
        let source = makeTransferTab(paneIDs: [movedPaneID, sourceRetainedPaneID])
        let destination = makeTransferTab(paneIDs: [destinationPaneID])
        let unrelatedTabs = (0..<256).map { _ in makeTransferTab(paneIDs: [UUIDv7.generate()]) }
        atom.replaceTabStates([source] + unrelatedTabs + [destination])
        let sourceReplacement = replacingPaneMembership(source, paneIDs: [sourceRetainedPaneID])
        let destinationReplacement = replacingPaneMembership(
            destination,
            paneIDs: [destinationPaneID, movedPaneID]
        )

        // Act
        atom.replaceTabStatesTransferringPaneOwnership(
            source: sourceReplacement,
            destination: destinationReplacement
        )

        // Assert
        for unrelatedTab in unrelatedTabs {
            #expect(atom.tabState(unrelatedTab.tabId) == unrelatedTab)
            #expect(atom.tabID(containingPane: unrelatedTab.allPaneIds[0]) == unrelatedTab.tabId)
            #expect(atom.tabID(containingArrangement: unrelatedTab.arrangements[0].id) == unrelatedTab.tabId)
        }
        #expect(atom.tabStates == [sourceReplacement] + unrelatedTabs + [destinationReplacement])
    }
}

private func makeTransferTab(paneIDs: [UUID]) -> TabGraphState {
    let arrangementID = UUIDv7.generate()
    return TabGraphState(
        tabId: UUIDv7.generate(),
        allPaneIds: paneIDs,
        arrangements: [
            PaneArrangementGraphState(
                id: arrangementID,
                name: "Default",
                isDefault: true,
                layout: .autoTiled(paneIDs),
                minimizedPaneIds: [],
                showsMinimizedPanes: false,
                drawerViews: [:]
            )
        ]
    )
}

private func replacingPaneMembership(
    _ tab: TabGraphState,
    paneIDs: [UUID]
) -> TabGraphState {
    var replacement = tab
    replacement.allPaneIds = paneIDs
    replacement.arrangements[0].layout = .autoTiled(paneIDs)
    return replacement
}
