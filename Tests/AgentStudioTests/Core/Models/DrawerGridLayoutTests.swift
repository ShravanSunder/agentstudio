import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class DrawerGridLayoutTests {

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
