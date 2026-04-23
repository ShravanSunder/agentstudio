import Foundation
import Testing

@testable import AgentStudio

@Suite
struct VisibleRowIndexMappingTests {
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()
    private let d = UUID()
    private let e = UUID()

    @Test
    func fullRowIndex_noMinimized_mapsIdentity() {
        let index = VisibleRowIndexMapping.fullRowIndex(
            forVisibleSlot: 1,
            fullRow: [a, b, c],
            minimizedPaneIds: [],
            showMinimizedBars: true
        )

        #expect(index == 1)
    }

    @Test
    func fullRowIndex_showMinimizedBars_minimizedVisibleCountsInSlots() {
        let index = VisibleRowIndexMapping.fullRowIndex(
            forVisibleSlot: 2,
            fullRow: [a, b, c],
            minimizedPaneIds: [b],
            showMinimizedBars: true
        )

        #expect(index == 2)
    }

    @Test
    func fullRowIndex_invisibleMinimizedInterleaved_translates() {
        let fullRow = [a, b, c, d, e]
        let minimizedPaneIds: Set<UUID> = [a, c, e]

        let slot0 = VisibleRowIndexMapping.fullRowIndex(
            forVisibleSlot: 0,
            fullRow: fullRow,
            minimizedPaneIds: minimizedPaneIds,
            showMinimizedBars: false
        )
        let slot1 = VisibleRowIndexMapping.fullRowIndex(
            forVisibleSlot: 1,
            fullRow: fullRow,
            minimizedPaneIds: minimizedPaneIds,
            showMinimizedBars: false
        )
        let slot2 = VisibleRowIndexMapping.fullRowIndex(
            forVisibleSlot: 2,
            fullRow: fullRow,
            minimizedPaneIds: minimizedPaneIds,
            showMinimizedBars: false
        )

        #expect(slot0 == 1)
        #expect(slot1 == 3)
        #expect(slot2 == 5)
    }

    @Test
    func fullRowIndex_allInvisibleMinimized_mapsToEnd() {
        let fullRow = [a, b, c]

        let index = VisibleRowIndexMapping.fullRowIndex(
            forVisibleSlot: 0,
            fullRow: fullRow,
            minimizedPaneIds: Set(fullRow),
            showMinimizedBars: false
        )

        #expect(index == 3)
    }
}
