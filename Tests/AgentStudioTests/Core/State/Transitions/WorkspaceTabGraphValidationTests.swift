import Foundation
import Testing

@testable import AgentStudio

@Suite("Workspace tab graph validation")
struct WorkspaceTabGraphValidationTests {
    @Test("append rejects empty tab pane membership")
    func appendRejectsEmptyTabPaneMembership() {
        // Arrange
        let arrangementID = UUIDv7.generate()
        let tab = Tab(
            id: UUIDv7.generate(),
            allPaneIds: [],
            arrangements: [
                PaneArrangement(
                    id: arrangementID,
                    isDefault: true,
                    layout: Layout()
                )
            ],
            activeArrangementId: arrangementID
        )

        // Act
        let decision = WorkspaceAppendTabTransitionDecider.decide(
            tab: tab,
            context: makeAppendContext()
        )

        // Assert
        #expect(decision == .rejected(.tabHasNoPanes(tab.id)))
    }

    @Test("append rejects an empty default arrangement main layout")
    func appendRejectsEmptyDefaultArrangementLayout() {
        // Arrange
        let paneID = UUIDv7.generate()
        let defaultArrangementID = UUIDv7.generate()
        let liveArrangementID = UUIDv7.generate()
        let tab = Tab(
            id: UUIDv7.generate(),
            allPaneIds: [paneID],
            arrangements: [
                PaneArrangement(
                    id: defaultArrangementID,
                    isDefault: true,
                    layout: Layout()
                ),
                PaneArrangement(
                    id: liveArrangementID,
                    isDefault: false,
                    layout: Layout(paneId: paneID),
                    activePaneId: paneID
                ),
            ],
            activeArrangementId: liveArrangementID
        )

        // Act
        let decision = WorkspaceAppendTabTransitionDecider.decide(
            tab: tab,
            context: makeAppendContext()
        )

        // Assert
        #expect(
            decision
                == .rejected(
                    .defaultArrangementLayoutIsEmpty(
                        tabID: tab.id,
                        arrangementID: defaultArrangementID
                    )
                )
        )
    }

    @Test("append rejects duplicate main-layout divider IDs")
    func appendRejectsDuplicateMainLayoutDividerIDs() {
        // Arrange
        let paneIDs = [UUIDv7.generate(), UUIDv7.generate(), UUIDv7.generate()]
        let duplicateDividerID = UUIDv7.generate()
        let arrangementID = UUIDv7.generate()
        let tab = Tab(
            id: UUIDv7.generate(),
            allPaneIds: paneIDs,
            arrangements: [
                PaneArrangement(
                    id: arrangementID,
                    isDefault: true,
                    layout: makeLayout(
                        paneIDs: paneIDs,
                        dividerIDs: [duplicateDividerID, duplicateDividerID]
                    ),
                    activePaneId: paneIDs[0]
                )
            ],
            activeArrangementId: arrangementID
        )

        // Act
        let decision = WorkspaceAppendTabTransitionDecider.decide(
            tab: tab,
            context: makeAppendContext()
        )

        // Assert
        #expect(
            decision
                == .rejected(
                    .duplicateLayoutDividerID(
                        arrangementID: arrangementID,
                        dividerID: duplicateDividerID
                    )
                )
        )
    }

    @Test("append rejects duplicate drawer-layout divider IDs")
    func appendRejectsDuplicateDrawerLayoutDividerIDs() {
        // Arrange
        let parentPaneID = UUIDv7.generate()
        let drawerPaneIDs = [UUIDv7.generate(), UUIDv7.generate(), UUIDv7.generate()]
        let duplicateDividerID = UUIDv7.generate()
        let arrangementID = UUIDv7.generate()
        let drawerID = UUIDv7.generate()
        let drawerView = DrawerView(
            layout: DrawerGridLayout(
                topRow: makeLayout(
                    paneIDs: drawerPaneIDs,
                    dividerIDs: [duplicateDividerID, duplicateDividerID]
                )
            ),
            activeChildId: drawerPaneIDs[0]
        )
        let tab = Tab(
            id: UUIDv7.generate(),
            allPaneIds: [parentPaneID] + drawerPaneIDs,
            arrangements: [
                PaneArrangement(
                    id: arrangementID,
                    isDefault: true,
                    layout: Layout(paneId: parentPaneID),
                    activePaneId: parentPaneID,
                    drawerViews: [drawerID: drawerView]
                )
            ],
            activeArrangementId: arrangementID
        )
        let key = ArrangementDrawerCursorKey(
            arrangementId: arrangementID,
            drawerId: drawerID
        )

        // Act
        let decision = WorkspaceAppendTabTransitionDecider.decide(
            tab: tab,
            context: makeAppendContext(
                panePlacementDescriptors: [
                    .drawerParent(
                        paneID: parentPaneID,
                        drawerID: drawerID,
                        drawerChildPaneIDs: Set(drawerPaneIDs)
                    )
                ]
                    + drawerPaneIDs.map {
                        .drawerChild(paneID: $0, parentPaneID: parentPaneID)
                    }
            )
        )

        // Assert
        #expect(
            decision
                == .rejected(
                    .duplicateDrawerLayoutDividerID(
                        key: key,
                        dividerID: duplicateDividerID
                    )
                )
        )
    }

    @Test("append rejects an empty drawer layout")
    func appendRejectsEmptyDrawerLayout() {
        // Arrange
        let parentPaneID = UUIDv7.generate()
        let arrangementID = UUIDv7.generate()
        let drawerID = UUIDv7.generate()
        let tab = Tab(
            id: UUIDv7.generate(),
            allPaneIds: [parentPaneID],
            arrangements: [
                PaneArrangement(
                    id: arrangementID,
                    isDefault: true,
                    layout: Layout(paneId: parentPaneID),
                    activePaneId: parentPaneID,
                    drawerViews: [drawerID: DrawerView()]
                )
            ],
            activeArrangementId: arrangementID
        )
        let key = ArrangementDrawerCursorKey(
            arrangementId: arrangementID,
            drawerId: drawerID
        )

        // Act
        let decision = WorkspaceAppendTabTransitionDecider.decide(
            tab: tab,
            context: makeAppendContext(
                panePlacementDescriptors: [
                    .drawerParent(
                        paneID: parentPaneID,
                        drawerID: drawerID,
                        drawerChildPaneIDs: []
                    )
                ]
            )
        )

        // Assert
        #expect(decision == .rejected(.drawerViewLayoutIsEmpty(key: key)))
    }
}

private func makeLayout(paneIDs: [UUID], dividerIDs: [UUID]) -> Layout {
    let ratio = 1.0 / Double(paneIDs.count)
    return Layout(
        panes: paneIDs.map { Layout.PaneEntry(paneId: $0, ratio: ratio) },
        dividerIds: dividerIDs
    )
}
