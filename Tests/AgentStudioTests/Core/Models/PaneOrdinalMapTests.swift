import Foundation
import Testing

@testable import AgentStudio

@Suite("PaneOrdinalMap")
struct PaneOrdinalMapTests {
    @Test("main pane ordinal map preserves active arrangement order")
    func mainPaneOrdinalMapPreservesActiveArrangementOrder() {
        let paneIds = Self.makePaneIds(count: 3)
        let map = PaneOrdinalMap(orderedPaneIds: paneIds)

        #expect(map.paneId(forOrdinal: 1) == paneIds[0])
        #expect(map.paneId(forOrdinal: 2) == paneIds[1])
        #expect(map.paneId(forOrdinal: 3) == paneIds[2])
        #expect(map.ordinal(forPaneId: paneIds[2]) == 3)
    }

    @Test("ordinal map returns nil for out of range ordinals")
    func outOfRangeOrdinalReturnsNil() {
        let paneIds = Self.makePaneIds(count: 2)
        let map = PaneOrdinalMap(orderedPaneIds: paneIds)

        #expect(map.paneId(forOrdinal: 0) == nil)
        #expect(map.paneId(forOrdinal: 3) == nil)
        #expect(map.ordinal(forPaneId: UUID()) == nil)
    }

    @Test("ordinal map exposes at most nine panes")
    func ordinalMapExposesAtMostNinePanes() {
        let paneIds = Self.makePaneIds(count: 10)
        let map = PaneOrdinalMap(orderedPaneIds: paneIds)

        #expect(map.paneId(forOrdinal: 9) == paneIds[8])
        #expect(map.paneId(forOrdinal: 10) == nil)
        #expect(map.ordinal(forPaneId: paneIds[9]) == nil)
    }

    @Test("drawer pane ordinal map follows drawer grid order")
    func drawerPaneOrdinalMapFollowsDrawerGridOrder() {
        let paneIds = Self.makePaneIds(count: 4)
        let drawerLayout = DrawerGridLayout(
            topRow: .autoTiled([paneIds[0], paneIds[1]]),
            bottomRow: .autoTiled([paneIds[2], paneIds[3]])
        )
        let map = PaneOrdinalMap(orderedPaneIds: drawerLayout.paneIds)

        #expect(map.paneId(forOrdinal: 1) == paneIds[0])
        #expect(map.paneId(forOrdinal: 2) == paneIds[1])
        #expect(map.paneId(forOrdinal: 3) == paneIds[2])
        #expect(map.paneId(forOrdinal: 4) == paneIds[3])
    }

    private static func makePaneIds(count: Int) -> [UUID] {
        (0..<count).map { _ in UUID() }
    }
}
