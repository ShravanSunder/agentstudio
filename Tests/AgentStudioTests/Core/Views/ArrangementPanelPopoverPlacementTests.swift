import SwiftUI
import Testing

@testable import AgentStudio

struct ArrangementPanelPopoverPlacementTests {
    @Test("all placements use center attachment and leading arrow edge")
    func allPlacements_useCenterAttachmentAndLeadingArrow() {
        for placement in [
            ArrangementPanelPopoverPlacement.tabBar,
            ArrangementPanelPopoverPlacement.minimizedBar,
        ] {
            #expect(placement.sourceAttachmentPoint == .center)
            #expect(placement.arrowEdge == .leading)
        }
    }
}
