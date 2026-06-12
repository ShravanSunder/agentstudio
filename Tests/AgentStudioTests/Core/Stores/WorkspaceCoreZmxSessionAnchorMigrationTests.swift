import Foundation
import GRDB
import Testing

@testable import AgentStudio

/// zmx-session-anchor plan T1: the spawn-time session id is stored on the
/// terminal content row and round-trips through the pane-graph codecs.
@Suite("WorkspaceCoreZmxSessionAnchorMigrationTests")
struct WorkspaceCoreZmxSessionAnchorMigrationTests {
    @Test("pane_content_terminal has a nullable zmx_session_id column")
    func paneContentTerminalHasNullableZmxSessionIdColumn() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()

        try WorkspaceCoreMigrations.migrate(databaseQueue)

        let columns = try databaseQueue.read { database in
            try Row.fetchAll(database, sql: "PRAGMA table_info(pane_content_terminal)")
        }
        let columnsByName = Dictionary(
            uniqueKeysWithValues: columns.map { row in
                (row["name"] as String, row)
            })
        #expect(columnsByName["zmx_session_id"] != nil)
        #expect((columnsByName["zmx_session_id"]?["notnull"] as Int?) == 0)
    }

    @Test("terminal pane zmx session id round trips through the pane graph")
    func terminalPaneZmxSessionIdRoundTripsThroughPaneGraph() throws {
        // Arrange
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let repository = fixture.repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-00000000B001")!
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-00000000B301")!
        let anchoredSessionId = "as-a1b2c3d4e5f6a7b8-00112233aabbccdd-5566778899001122"
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Anchor",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        let graph = WorkspaceCoreRepository.PaneGraphRecord(
            panes: [
                .init(
                    id: paneId,
                    content: .terminal(
                        provider: .zmx,
                        lifetime: .persistent,
                        zmxSessionId: anchoredSessionId
                    ),
                    metadata: .init(
                        executionBackend: .local,
                        createdAt: Date(timeIntervalSince1970: 300),
                        title: "Anchored Terminal"
                    ),
                    residency: .active,
                    placement: .layout,
                    drawer: nil,
                    updatedAt: Date(timeIntervalSince1970: 400)
                )
            ]
        )

        // Act
        try repository.replacePaneGraph(workspaceId: workspaceId, graph: graph)
        let restored = try repository.fetchPaneGraph(workspaceId: workspaceId)

        // Assert
        guard case .terminal(_, _, let restoredSessionId) = restored.panes.first?.content else {
            Issue.record("Expected terminal content record")
            return
        }
        #expect(restoredSessionId == anchoredSessionId)
    }

    @Test("anchor-less terminal records persist a NULL zmx session id")
    func anchorlessTerminalRecordsPersistNullZmxSessionId() throws {
        // Arrange — the anchor-less factory used by pre-anchor call sites.
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let repository = fixture.repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-00000000B002")!
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-00000000B302")!
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Anchorless",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        let graph = WorkspaceCoreRepository.PaneGraphRecord(
            panes: [
                .init(
                    id: paneId,
                    content: .terminal(provider: .zmx, lifetime: .persistent),
                    metadata: .init(
                        executionBackend: .local,
                        createdAt: Date(timeIntervalSince1970: 300),
                        title: "Anchorless Terminal"
                    ),
                    residency: .active,
                    placement: .layout,
                    drawer: nil,
                    updatedAt: Date(timeIntervalSince1970: 400)
                )
            ]
        )

        // Act
        try repository.replacePaneGraph(workspaceId: workspaceId, graph: graph)
        let storedSessionId = try fixture.databaseQueue.read { database in
            try String.fetchOne(
                database,
                sql: "SELECT zmx_session_id FROM pane_content_terminal WHERE pane_id = ?",
                arguments: [paneId.uuidString]
            )
        }

        // Assert
        #expect(storedSessionId == nil)
    }
}
