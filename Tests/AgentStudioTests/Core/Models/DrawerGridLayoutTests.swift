import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioCore

@Suite(.serialized)
final class DrawerGridLayoutTests {

    @Test
    func horizontalVisibleNavigation_keepsBothRowsAndStopsAtTheirEdges() {
        let topPane = UUIDv7.generate()
        let bottomLeft = UUIDv7.generate()
        let bottomHidden = UUIDv7.generate()
        let bottomRight = UUIDv7.generate()
        let layout = DrawerGridLayout(
            topRow: Layout.autoTiled([topPane]),
            bottomRow: Layout.autoTiled([bottomLeft, bottomHidden, bottomRight])
        )
        let visiblePaneIds: Set<UUID> = [topPane, bottomLeft, bottomRight]

        #expect(layout.horizontalNeighbor(of: bottomLeft, direction: .right, among: visiblePaneIds) == bottomRight)
        #expect(layout.horizontalNeighbor(of: bottomRight, direction: .left, among: visiblePaneIds) == bottomLeft)
        #expect(layout.horizontalNeighbor(of: bottomLeft, direction: .left, among: visiblePaneIds) == nil)
        #expect(layout.horizontalNeighbor(of: bottomRight, direction: .right, among: visiblePaneIds) == nil)
        #expect(layout.horizontalNeighbor(of: topPane, direction: .right, among: visiblePaneIds) == nil)
        #expect(layout.horizontalNeighbor(of: bottomHidden, direction: .right, among: visiblePaneIds) == nil)
        #expect(layout.horizontalNeighbor(of: bottomLeft, direction: .right, among: []) == nil)
        #expect(layout.neighbor(of: bottomLeft, direction: .right) == bottomHidden)
    }

    @Test
    func verticalNeighborLookup_prefersPaneInOtherRow() {
        let topLeft = UUID()
        let topRight = UUID()
        let bottomLeft = UUID()
        let bottomRight = UUID()

        let layout = DrawerGridLayout(
            topRow: Layout.autoTiled([topLeft, topRight]),
            bottomRow: Layout.autoTiled([bottomLeft, bottomRight]),
            rowSplitRatio: 0.5
        )

        #expect(layout.neighbor(of: topLeft, direction: .down) == bottomLeft)
        #expect(layout.neighbor(of: bottomRight, direction: .up) == topRight)
    }

    @Test
    func verticalNeighborLookup_returnsNilAtEdge() {
        let topOnly = UUID()
        let peer = UUID()
        let layout = DrawerGridLayout(topRow: Layout.autoTiled([topOnly, peer]))

        #expect(layout.neighbor(of: topOnly, direction: .up) == nil)
        #expect(layout.neighbor(of: peer, direction: .down) == nil)
    }

    @Test
    func insertingThirdRow_isRejected() {
        let top = UUID()
        let bottom = UUID()
        let incoming = UUID()

        let layout = DrawerGridLayout(
            topRow: Layout.autoTiled([top]),
            bottomRow: Layout.autoTiled([bottom]),
            rowSplitRatio: 0.5
        )

        let rejected = layout.inserting(
            paneId: incoming,
            at: bottom,
            direction: .down,
            sizingMode: .halveTarget
        )

        #expect(rejected == nil)
    }

    @Test
    func removingOnlyTopRowPane_collapsesBottomRow() throws {
        let topOnly = UUID()
        let bottomLeft = UUID()
        let bottomRight = UUID()

        let layout = DrawerGridLayout(
            topRow: Layout.autoTiled([topOnly]),
            bottomRow: Layout.autoTiled([bottomLeft, bottomRight]),
            rowSplitRatio: 0.5
        )

        let collapsed = try #require(layout.removing(paneId: topOnly, sizingMode: .halveTarget))
        #expect(collapsed.topRow.paneIds == [bottomLeft, bottomRight])
        #expect(collapsed.bottomRow == nil)
    }

    @Test
    func removingOnlyBottomRowPane_collapsesToSingleRow() throws {
        let topLeft = UUID()
        let topRight = UUID()
        let bottomOnly = UUID()

        let layout = DrawerGridLayout(
            topRow: Layout.autoTiled([topLeft, topRight]),
            bottomRow: Layout.autoTiled([bottomOnly]),
            rowSplitRatio: 0.5
        )

        let collapsed = try #require(layout.removing(paneId: bottomOnly, sizingMode: .halveTarget))
        #expect(collapsed.topRow.paneIds == [topLeft, topRight])
        #expect(collapsed.bottomRow == nil)
    }
}
