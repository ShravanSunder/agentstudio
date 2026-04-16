import SwiftUI
import Testing

@testable import AgentStudio

struct ArrangementPanelPopoverPlacementTests {
    @Test
    func allPlacements_shareAnchorAndArrowContract() {
        for placement in [
            ArrangementPanelPopoverPlacement.tabBar,
            ArrangementPanelPopoverPlacement.minimizedBar,
        ] {
            #expect(placement.sourceAttachmentPoint == .center)
            #expect(placement.arrowEdge == .leading)
        }
    }
}
