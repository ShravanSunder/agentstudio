import Foundation
import GRDB
import Testing

@testable import AgentStudio

@Suite("WorkspaceCoreRepositoryTabGraphStorageGuardTests")
struct WorkspaceCoreRepositoryTabGraphStorageGuardTests {
    @Test("tab graph storage rejects unexpected drawer layout row kind")
    func tabGraphStorageRejectsUnexpectedDrawerLayoutRowKind() throws {
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let repository = fixture.repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000003007")!
        let tabId = UUID(uuidString: "00000000-0000-0000-0000-000000003111")!
        let parentPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000003212")!
        let drawerPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000003213")!
        let drawerId = UUID(uuidString: "00000000-0000-0000-0000-000000003302")!
        let arrangementId = UUID(uuidString: "00000000-0000-0000-0000-000000003402")!
        try upsertWorkspace(repository, workspaceId: workspaceId, name: "Bad Row Kind")
        try repository.replacePaneGraph(
            workspaceId: workspaceId,
            graph: .init(panes: [
                makeFloatingPane(
                    id: parentPaneId,
                    drawer: .init(drawerId: drawerId, parentPaneId: parentPaneId, childPaneIds: [drawerPaneId])
                ),
                makeFloatingPane(id: drawerPaneId, placement: .drawerChild(parentPaneId: parentPaneId)),
            ])
        )
        try repository.replaceTabShellsAndGraph(
            workspaceId: workspaceId,
            shells: [.init(id: tabId, name: "Main")],
            graph: .init(tabs: [
                .init(
                    tabId: tabId,
                    allPaneIds: [parentPaneId, drawerPaneId],
                    arrangements: [
                        .init(
                            id: arrangementId,
                            name: "Default",
                            isDefault: true,
                            layout: Layout(paneId: parentPaneId),
                            minimizedPaneIds: [],
                            showsMinimizedPanes: true,
                            drawerViews: [
                                drawerId: .init(
                                    layout: DrawerGridLayout(topRow: Layout(paneId: drawerPaneId)),
                                    minimizedPaneIds: []
                                )
                            ]
                        )
                    ]
                )
            ])
        )

        do {
            try fixture.databaseQueue.write { database in
                try database.execute(
                    sql: """
                        INSERT INTO drawer_view_layout_divider(
                            arrangement_id, drawer_id, row_kind, divider_id, sort_index
                        )
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        arrangementId.uuidString,
                        drawerId.uuidString,
                        "diagonal",
                        UUID(uuidString: "00000000-0000-0000-0000-000000003503")!.uuidString,
                        0,
                    ]
                )
            }
            Issue.record("Expected row_kind storage guard to reject diagonal drawer layout row")
        } catch let error as DatabaseError {
            #expect(error.message?.contains("drawer view layout row_kind must be top or bottom") == true)
        } catch {
            Issue.record("Expected DatabaseError for invalid row_kind, got \(error)")
        }
    }

    private func makeFloatingPane(
        id: UUID,
        placement: WorkspaceCoreRepository.PanePlacementRecord = .layout,
        drawer: WorkspaceCoreRepository.DrawerRecord? = nil
    ) -> WorkspaceCoreRepository.PaneRecord {
        .init(
            id: id,
            content: .terminal(provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7()),
            metadata: .init(
                executionBackend: .local,
                createdAt: Date(timeIntervalSince1970: 300),
                title: "Pane",
                durableFacets: .init(cwd: URL(fileURLWithPath: "/tmp/agentstudio/tab-graph"))
            ),
            residency: .active,
            placement: placement,
            drawer: drawer,
            updatedAt: Date(timeIntervalSince1970: 500)
        )
    }

    private func upsertWorkspace(
        _ repository: WorkspaceCoreRepository,
        workspaceId: UUID,
        name: String
    ) throws {
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: name,
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
    }
}
