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
            minimizedPaneIds: [sharedPane]
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
}
