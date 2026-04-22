import Foundation
import Testing

@testable import AgentStudio

/// Regression tests for `Drawer`'s Codable implementation.
///
/// Before this suite existed, the drawer-grid rework changed `Drawer.layout`
/// from `Layout` to `DrawerGridLayout` without adding a backward-compat
/// decode path. Workspaces persisted on the old schema failed to decode on
/// upgrade and were treated as corrupt, silently losing saved state.
/// The decoder now tries `DrawerGridLayout` first and falls back to legacy
/// `Layout`, wrapping it into a one-row grid.
@Suite
struct DrawerCodableTests {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Current format

    @Test
    func roundTrip_currentFormat_preservesLayout() throws {
        let paneA = UUID()
        let paneB = UUID()
        let paneC = UUID()
        let dividerId = UUID()

        let topRow = Layout(
            panes: [
                .init(paneId: paneA, ratio: 0.5),
                .init(paneId: paneB, ratio: 0.5),
            ],
            dividerIds: [dividerId]
        )
        let bottomRow = Layout(paneId: paneC)

        let drawer = Drawer(
            paneIds: [paneA, paneB, paneC],
            layout: DrawerGridLayout(
                topRow: topRow,
                bottomRow: bottomRow,
                rowSplitRatio: 0.4
            ),
            activePaneId: paneB,
            isExpanded: true,
            minimizedPaneIds: []
        )

        let data = try encoder.encode(drawer)
        let decoded = try decoder.decode(Drawer.self, from: data)

        #expect(decoded.paneIds == [paneA, paneB, paneC])
        #expect(decoded.layout.topRow.paneIds == [paneA, paneB])
        #expect(decoded.layout.bottomRow?.paneIds == [paneC])
        #expect(decoded.layout.rowSplitRatio == 0.4)
        #expect(decoded.activePaneId == paneB)
        #expect(decoded.isExpanded == true)
        #expect(decoded.minimizedPaneIds.isEmpty)
    }

    // MARK: - Legacy format backward compatibility

    @Test
    func decode_legacyLayoutFormat_wrapsIntoSingleRowGrid() throws {
        // Simulates a workspace persisted before the drawer-grid rework, where
        // `Drawer.layout` was a single `Layout`. The migration must wrap such
        // values into a one-row DrawerGridLayout so the workspace still loads.
        let paneA = UUID()
        let paneB = UUID()
        let dividerId = UUID()

        let legacyJSON = """
            {
                "paneIds": ["\(paneA.uuidString)", "\(paneB.uuidString)"],
                "layout": {
                    "panes": [
                        { "paneId": "\(paneA.uuidString)", "ratio": 0.6 },
                        { "paneId": "\(paneB.uuidString)", "ratio": 0.4 }
                    ],
                    "dividerIds": ["\(dividerId.uuidString)"]
                },
                "activePaneId": "\(paneA.uuidString)",
                "isExpanded": false
            }
            """

        let decoded = try decoder.decode(Drawer.self, from: Data(legacyJSON.utf8))

        #expect(decoded.paneIds == [paneA, paneB])
        #expect(decoded.layout.topRow.paneIds == [paneA, paneB])
        #expect(decoded.layout.bottomRow == nil)
        #expect(decoded.layout.rowSplitRatio == 0.5)
        #expect(decoded.activePaneId == paneA)
        #expect(decoded.isExpanded == false)
        #expect(decoded.minimizedPaneIds.isEmpty)
    }

    @Test
    func decode_legacyLayoutFormat_emptyPanes_wrapsIntoEmptyGrid() throws {
        // Legacy empty-drawer case — workspace with a drawer that has no panes.
        let legacyJSON = """
            {
                "paneIds": [],
                "layout": {
                    "panes": [],
                    "dividerIds": []
                },
                "isExpanded": false
            }
            """

        let decoded = try decoder.decode(Drawer.self, from: Data(legacyJSON.utf8))

        #expect(decoded.paneIds.isEmpty)
        #expect(decoded.layout.isEmpty)
        #expect(decoded.layout.bottomRow == nil)
        #expect(decoded.activePaneId == nil)
        #expect(decoded.isExpanded == false)
    }

    // MARK: - Malformed input still surfaces errors

    @Test
    func decode_invalidLayout_throws() {
        // Neither current DrawerGridLayout nor legacy Layout shape. The
        // backward-compat fallback must NOT swallow this as empty state —
        // we want the error to surface so higher layers can treat it as
        // truly corrupt.
        let bogusJSON = """
            {
                "paneIds": [],
                "layout": { "nonsense": true },
                "isExpanded": false
            }
            """

        #expect(throws: (any Error).self) {
            try decoder.decode(Drawer.self, from: Data(bogusJSON.utf8))
        }
    }
}
