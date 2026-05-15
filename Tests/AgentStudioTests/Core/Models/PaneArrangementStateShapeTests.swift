import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct PaneArrangementStateShapeTests {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    @Test
    func paneArrangementEncodingUsesCompleteViewShape() throws {
        let paneId = UUID()
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: paneId),
            minimizedPaneIds: [paneId],
            showsMinimizedPanes: true,
            activePaneId: paneId,
            drawerViews: [:]
        )

        let encodedData = try encoder.encode(arrangement)
        let encoded = try #require(String(bytes: encodedData, encoding: .utf8))

        #expect(!encoded.contains("visiblePaneIds"))
        #expect(encoded.contains("showsMinimizedPanes"))
        #expect(encoded.contains("activePaneId"))
        #expect(encoded.contains("drawerViews"))
    }

    @Test
    func drawerEncodingUsesIdentityDataAndGlobalExpandedOnly() throws {
        let drawerPaneId = UUID()
        let drawer = Drawer(
            drawerId: UUID(),
            parentPaneId: UUID(),
            paneIds: [drawerPaneId],
            isExpanded: true
        )

        let encodedData = try encoder.encode(drawer)
        let encoded = try #require(String(bytes: encodedData, encoding: .utf8))

        #expect(encoded.contains("drawerId"))
        #expect(encoded.contains("parentPaneId"))
        #expect(encoded.contains("paneIds"))
        #expect(encoded.contains("isExpanded"))
        #expect(!encoded.contains("layout"))
        #expect(!encoded.contains("activeChildId"))
        #expect(!encoded.contains("minimizedPaneIds"))
    }

    @Test
    func drawerRejectsOldViewStateShape() throws {
        let drawerPaneId = UUID()
        let oldShapeData = Data(
            """
            {
              "paneIds": ["\(drawerPaneId.uuidString)"],
              "layout": {"topRow": {"panes": [{"paneId": "\(drawerPaneId.uuidString)", "ratio": 1}], "dividerIds": []}},
              "activeChildId": "\(drawerPaneId.uuidString)",
              "isExpanded": true
            }
            """.utf8
        )

        #expect(throws: DecodingError.self) {
            try decoder.decode(Drawer.self, from: oldShapeData)
        }
    }
}
