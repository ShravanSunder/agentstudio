import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct DrawerCommandValidatorTests {
    private func makeState(
        parentPaneId: UUID,
        paneIds: [UUID],
        layout: DrawerGridLayout
    ) -> ActionStateSnapshot {
        ActionStateSnapshot(
            tabs: [
                TabSnapshot(
                    id: UUID(),
                    visiblePaneIds: [parentPaneId],
                    ownedPaneIds: [parentPaneId] + paneIds,
                    activePaneId: parentPaneId
                )
            ],
            activeTabId: nil,
            isManagementLayerActive: true,
            drawerParentByPaneId: Dictionary(
                uniqueKeysWithValues: paneIds.map { ($0, parentPaneId) }
            ),
            drawerLayoutByParentPaneId: [parentPaneId: layout]
        )
    }

    @Test
    func validateMove_acceptsExplicitTopRowSlot() {
        let parent = UUID()
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let state = makeState(
            parentPaneId: parent,
            paneIds: [a, b, c],
            layout: DrawerGridLayout(topRow: Layout.autoTiled([a, b, c]))
        )

        let result = DrawerCommandValidator.validateMove(
            parentPaneId: parent,
            drawerPaneId: c,
            target: .rowSlot(row: .top, insertionIndex: 0),
            sizingMode: .proportional,
            state: state
        )

        if case .success = result { return }
        Issue.record("Expected success")
    }

    @Test
    func validateMove_acceptsCreateSecondRowFromOneRow() {
        let parent = UUID()
        let a = UUID()
        let b = UUID()
        let state = makeState(
            parentPaneId: parent,
            paneIds: [a, b],
            layout: DrawerGridLayout(topRow: Layout.autoTiled([a, b]))
        )

        let result = DrawerCommandValidator.validateMove(
            parentPaneId: parent,
            drawerPaneId: b,
            target: .createSecondRow(position: .bottom),
            sizingMode: .proportional,
            state: state
        )

        if case .success = result { return }
        Issue.record("Expected success")
    }

    @Test
    func validateMove_rejectsThirdRowCreation() {
        let parent = UUID()
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let state = makeState(
            parentPaneId: parent,
            paneIds: [a, b, c],
            layout: DrawerGridLayout(
                topRow: Layout.autoTiled([a, b]),
                bottomRow: Layout.autoTiled([c]),
                rowSplitRatio: 0.5
            )
        )

        let result = DrawerCommandValidator.validateMove(
            parentPaneId: parent,
            drawerPaneId: a,
            target: .createSecondRow(position: .bottom),
            sizingMode: .proportional,
            state: state
        )

        if case .failure(.invalidDrawerLayout(parentPaneId: parent, reason: .projectedMove(.secondRowAlreadyExists))) =
            result
        {
            return
        }
        Issue.record("Expected invalidDrawerLayout with secondRowAlreadyExists reason")
    }
}
