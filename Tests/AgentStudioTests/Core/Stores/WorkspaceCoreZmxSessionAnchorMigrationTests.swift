import Foundation
import Testing

@testable import AgentStudio

@Suite("Workspace core zmx session identity persistence")
struct WorkspaceCoreZmxSessionAnchorMigrationTests {
    @Test("terminal pane preserves existing opaque zmx session text through SQLite")
    func terminalPanePreservesExistingOpaqueZmxSessionTextThroughSQLite() throws {
        // Arrange
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let repository = fixture.repository
        let workspaceID = UUID(uuidString: "00000000-0000-0000-0000-00000000B001")!
        let paneID = UUID(uuidString: "00000000-0000-0000-0000-00000000B301")!
        let storedText = "as-a1b2c3d4e5f6a7b8-00112233aabbccdd-5566778899001122"
        let zmxSessionID = try #require(ZmxSessionID(restoring: storedText))
        try repository.upsertWorkspace(
            .init(
                id: workspaceID,
                name: "Opaque identity",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        let graph = WorkspaceCoreRepository.PaneGraphRecord(
            panes: [
                .init(
                    id: paneID,
                    content: .terminal(
                        provider: .zmx,
                        lifetime: .persistent,
                        zmxSessionID: zmxSessionID
                    ),
                    metadata: .init(
                        executionBackend: .local,
                        createdAt: Date(timeIntervalSince1970: 300),
                        title: "Existing terminal"
                    ),
                    residency: .active,
                    placement: .layout,
                    drawer: nil,
                    updatedAt: Date(timeIntervalSince1970: 400)
                )
            ]
        )

        // Act
        try repository.replacePaneGraph(workspaceId: workspaceID, graph: graph)
        let persistedText = try fixture.databaseQueue.read { database in
            try String.fetchOne(
                database,
                sql: "SELECT zmx_session_id FROM pane_content_terminal WHERE pane_id = ?",
                arguments: [paneID.uuidString]
            )
        }
        let restored = try repository.fetchPaneGraph(workspaceId: workspaceID)

        // Assert
        guard case .terminal(_, _, let restoredSessionID) = restored.panes.first?.content else {
            Issue.record("Expected terminal content record")
            return
        }
        #expect(persistedText == storedText)
        #expect(restoredSessionID.rawValue == storedText)
    }
}
