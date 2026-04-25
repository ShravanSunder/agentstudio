import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite
struct PaneDropTargetOverlayTests {
    @Test
    func debugDestinationsIncludeBothZonesForEachPaneInLayoutOrder() {
        let leftPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let rightPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        let destinations = PaneDropTargetOverlay.debugDestinations(for: [
            rightPaneId: CGRect(x: 220, y: 0, width: 200, height: 100),
            leftPaneId: CGRect(x: 0, y: 0, width: 200, height: 100),
        ])

        #expect(destinations.map(\.paneId) == [leftPaneId, leftPaneId, rightPaneId, rightPaneId])
        #expect(destinations.map(\.zone) == [.left, .right, .left, .right])
    }
}
