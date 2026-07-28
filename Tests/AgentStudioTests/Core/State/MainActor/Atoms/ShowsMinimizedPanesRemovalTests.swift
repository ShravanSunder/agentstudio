import Foundation
import GRDB
import Testing

@testable import AgentStudio

@Suite("Shows minimized panes removal")
struct ShowsMinimizedPanesRemovalTests {
    @Test
    func defaultArrangementConstructionDiscardsMinimizedPaneIds() {
        let paneA = UUID()
        let paneB = UUID()

        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout.autoTiled([paneA, paneB]),
            minimizedPaneIds: [paneB],
            activePaneId: paneA
        )

        #expect(arrangement.minimizedPaneIds.isEmpty)
        #expect(arrangement.activePaneId == paneA)
    }

    @Test
    func paneArrangementEncodingOmitsRetiredVisibilityAuthority() throws {
        let paneId = UUID()
        let arrangement = PaneArrangement(
            name: "Layout 1",
            isDefault: false,
            layout: Layout(paneId: paneId),
            minimizedPaneIds: [paneId]
        )

        let encodedData = try JSONEncoder().encode(arrangement)
        let encodedObject = try #require(
            JSONSerialization.jsonObject(with: encodedData) as? [String: Any]
        )

        #expect(encodedObject["showsMinimizedPanes"] == nil)
    }

    @Test
    func coreSchemaOmitsRetiredVisibilityAuthority() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()

        try WorkspaceCoreMigrations.migrate(databaseQueue)

        let arrangementColumns = try databaseQueue.read { database in
            try Row.fetchAll(database, sql: "PRAGMA table_info(tab_arrangement)")
                .map { row in row["name"] as String }
        }
        #expect(!arrangementColumns.contains("shows_minimized_panes"))
    }
}
