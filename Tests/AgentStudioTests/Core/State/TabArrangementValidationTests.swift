import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct TabArrangementValidationTests {
    @Test
    func validate_removesDuplicatePaneIdsFromLaterTabsAndMinimizedSets() {
        let sharedPane = UUID()
        let uniquePane = UUID()
        let firstArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: sharedPane)
        )
        let first = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [sharedPane],
            arrangements: [firstArrangement],
            activeArrangementId: firstArrangement.id,
            activePaneId: sharedPane,
            zoomedPaneId: nil
        )
        let secondArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: sharedPane)
                .inserting(
                    paneId: uniquePane, at: sharedPane, direction: .horizontal, position: .after,
                    sizingMode: .halveTarget)!,
            minimizedPaneIds: [MainPaneId(sharedPane)]
        )
        let second = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [sharedPane, uniquePane],
            arrangements: [secondArrangement],
            activeArrangementId: secondArrangement.id,
            activePaneId: sharedPane,
            zoomedPaneId: nil
        )

        let validated = TabArrangementValidation.validating([first, second])

        #expect(validated.count == 2)
        #expect(validated[1].allPaneIds == [uniquePane])
        #expect(validated[1].arrangements[0].layout.paneIds == [uniquePane])
        #expect(validated[1].arrangements[0].minimizedPaneIds.isEmpty)
    }

    @Test
    func pruningInvalidPaneIds_removesInvalidDrawerViewPaneReferences() {
        let parentPane = UUID()
        let validDrawerPane = UUID()
        let invalidDrawerPane = UUID()
        let drawerId = UUID()
        let drawerLayout = DrawerGridLayout(
            topRow: Layout(paneId: validDrawerPane)
                .inserting(
                    paneId: invalidDrawerPane,
                    at: validDrawerPane,
                    direction: .horizontal,
                    position: .after,
                    sizingMode: .halveTarget
                )!)
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: parentPane),
            drawerViews: [
                drawerId: DrawerView(
                    layout: drawerLayout,
                    activeChildId: DrawerPaneId(invalidDrawerPane),
                    minimizedPaneIds: [DrawerPaneId(invalidDrawerPane)]
                )
            ]
        )
        let state = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [parentPane, validDrawerPane, invalidDrawerPane],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: parentPane,
            zoomedPaneId: nil
        )

        let validated = TabArrangementValidation.pruningInvalidPaneIds(
            validPaneIds: [parentPane, validDrawerPane],
            from: [state]
        )

        let drawerView = validated[0].arrangements[0].drawerViews[drawerId]
        #expect(drawerView?.layout.paneIds == [validDrawerPane])
        #expect(drawerView?.activeChildId?.rawValue == validDrawerPane)
        #expect(drawerView?.minimizedPaneIds.isEmpty == true)
    }

    @Test
    func validate_keepsDrawerPaneIdsInTabPaneMembership() {
        let parentPane = UUID()
        let drawerPane = UUID()
        let drawerId = UUID()
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: parentPane),
            drawerViews: [
                drawerId: DrawerView(layout: DrawerGridLayout(topRow: Layout(paneId: drawerPane)))
            ]
        )
        let state = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [parentPane, drawerPane],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: parentPane,
            zoomedPaneId: nil
        )

        let validated = TabArrangementValidation.validating([state])

        #expect(Set(validated[0].allPaneIds) == Set([parentPane, drawerPane]))
        #expect(validated[0].arrangements[0].drawerViews[drawerId]?.layout.paneIds == [drawerPane])
    }
}
