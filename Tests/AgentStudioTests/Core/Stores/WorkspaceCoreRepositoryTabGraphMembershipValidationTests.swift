import Foundation
import GRDB
import Testing

@testable import AgentStudio

@Suite("WorkspaceCoreRepositoryTabGraphMembershipValidationTests")
struct TabGraphMembershipValidationTests {
    @Test("tab graph replace rejects tabs without exactly one default arrangement")
    func tabGraphReplaceRejectsTabsWithoutExactlyOneDefaultArrangement() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000004003")!
        let tabId = UUID(uuidString: "00000000-0000-0000-0000-000000004103")!
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000004205")!
        try seedWorkspaceShellAndPanes(
            repository,
            workspaceId: workspaceId,
            tabId: tabId,
            panes: [makeFloatingPane(id: paneId)]
        )

        #expect(
            throws: WorkspaceCoreRepositoryError.tabHasInvalidDefaultArrangementCount(tabId: tabId, count: 0)
        ) {
            try repository.replaceTabGraph(
                workspaceId: workspaceId,
                graph: .init(tabs: [
                    .init(
                        tabId: tabId,
                        allPaneIds: [paneId],
                        arrangements: [
                            makeArrangement(
                                id: UUID(uuidString: "00000000-0000-0000-0000-000000004303")!,
                                isDefault: false,
                                layout: Layout(paneId: paneId)
                            )
                        ]
                    )
                ])
            )
        }
    }

    @Test("tab graph replace rejects pane assigned to multiple tabs before SQL conflict")
    func tabGraphReplaceRejectsPaneAssignedToMultipleTabsBeforeSQLConflict() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000004006")!
        let firstTabId = UUID(uuidString: "00000000-0000-0000-0000-000000004106")!
        let secondTabId = UUID(uuidString: "00000000-0000-0000-0000-000000004107")!
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000004209")!
        let seedPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000004220")!
        try seedWorkspaceShellsAndPanes(
            repository,
            workspaceId: workspaceId,
            tabIds: [firstTabId, secondTabId],
            panes: [makeFloatingPane(id: paneId), makeFloatingPane(id: seedPaneId)]
        )

        #expect(
            throws: WorkspaceCoreRepositoryError.duplicateTabPaneId(tabId: secondTabId, paneId: paneId)
        ) {
            try repository.replaceTabGraph(
                workspaceId: workspaceId,
                graph: .init(tabs: [
                    .init(
                        tabId: firstTabId,
                        allPaneIds: [paneId],
                        arrangements: [
                            makeArrangement(
                                id: UUID(uuidString: "00000000-0000-0000-0000-000000004306")!,
                                layout: Layout(paneId: paneId)
                            )
                        ]
                    ),
                    .init(
                        tabId: secondTabId,
                        allPaneIds: [paneId],
                        arrangements: [
                            makeArrangement(
                                id: UUID(uuidString: "00000000-0000-0000-0000-000000004307")!,
                                layout: Layout(paneId: paneId)
                            )
                        ]
                    ),
                ])
            )
        }
    }

    @Test("tab graph replace rejects graph that omits an existing tab shell")
    func tabGraphReplaceRejectsGraphThatOmitsExistingTabShell() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000004007")!
        let firstTabId = UUID(uuidString: "00000000-0000-0000-0000-000000004108")!
        let omittedTabId = UUID(uuidString: "00000000-0000-0000-0000-000000004109")!
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000004210")!
        let omittedSeedPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000004221")!
        try seedWorkspaceShellsAndPanes(
            repository,
            workspaceId: workspaceId,
            tabIds: [firstTabId, omittedTabId],
            panes: [makeFloatingPane(id: paneId), makeFloatingPane(id: omittedSeedPaneId)]
        )

        #expect(throws: WorkspaceCoreRepositoryError.tabGraphMissingTabState(omittedTabId)) {
            try repository.replaceTabGraph(
                workspaceId: workspaceId,
                graph: .init(tabs: [
                    .init(
                        tabId: firstTabId,
                        allPaneIds: [paneId],
                        arrangements: [
                            makeArrangement(
                                id: UUID(uuidString: "00000000-0000-0000-0000-000000004308")!,
                                layout: Layout(paneId: paneId)
                            )
                        ]
                    )
                ])
            )
        }
    }

    @Test("tab graph replace rejects tab membership missing from arrangements")
    func tabGraphReplaceRejectsTabMembershipMissingFromArrangements() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000004008")!
        let tabId = UUID(uuidString: "00000000-0000-0000-0000-000000004110")!
        let visiblePaneId = UUID(uuidString: "00000000-0000-0000-0000-000000004211")!
        let membershipOnlyPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000004212")!
        try seedWorkspaceShellAndPanes(
            repository,
            workspaceId: workspaceId,
            tabId: tabId,
            panes: [makeFloatingPane(id: visiblePaneId), makeFloatingPane(id: membershipOnlyPaneId)]
        )

        #expect(
            throws: WorkspaceCoreRepositoryError.tabPaneMissingFromArrangements(
                tabId: tabId,
                paneId: membershipOnlyPaneId
            )
        ) {
            try repository.replaceTabGraph(
                workspaceId: workspaceId,
                graph: .init(tabs: [
                    .init(
                        tabId: tabId,
                        allPaneIds: [visiblePaneId, membershipOnlyPaneId],
                        arrangements: [
                            makeArrangement(
                                id: UUID(uuidString: "00000000-0000-0000-0000-000000004309")!,
                                layout: Layout(paneId: visiblePaneId)
                            )
                        ]
                    )
                ])
            )
        }
    }

    @Test("tab graph replace rolls back after mutation failure")
    func tabGraphReplaceRollsBackAfterMutationFailure() throws {
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let repository = fixture.repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000004004")!
        let tabId = UUID(uuidString: "00000000-0000-0000-0000-000000004104")!
        let originalPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000004206")!
        let rejectedPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000004207")!
        try seedWorkspaceShellAndPanes(
            repository,
            workspaceId: workspaceId,
            tabId: tabId,
            panes: [makeFloatingPane(id: originalPaneId), makeFloatingPane(id: rejectedPaneId)]
        )
        let originalGraph = WorkspaceCoreRepository.TabGraphRecord(tabs: [
            .init(
                tabId: tabId,
                allPaneIds: [originalPaneId],
                arrangements: [
                    makeArrangement(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000004304")!,
                        layout: Layout(paneId: originalPaneId)
                    )
                ]
            )
        ])
        try repository.replaceTabGraph(workspaceId: workspaceId, graph: originalGraph)
        try fixture.databaseQueue.write { database in
            try database.execute(
                sql: """
                    CREATE TRIGGER tab_graph_test_abort
                    BEFORE INSERT ON arrangement_layout_pane
                    WHEN NEW.pane_id = '\(rejectedPaneId.uuidString)'
                    BEGIN
                        SELECT RAISE(ABORT, 'tab graph test abort');
                    END
                    """
            )
        }

        #expect(throws: Error.self) {
            try repository.replaceTabGraph(
                workspaceId: workspaceId,
                graph: .init(tabs: [
                    .init(
                        tabId: tabId,
                        allPaneIds: [rejectedPaneId],
                        arrangements: [
                            makeArrangement(
                                id: UUID(uuidString: "00000000-0000-0000-0000-000000004305")!,
                                layout: Layout(paneId: rejectedPaneId)
                            )
                        ]
                    )
                ])
            )
        }

        #expect(try repository.fetchTabGraph(workspaceId: workspaceId) == originalGraph)
    }

    private func seedWorkspaceShellAndPanes(
        _ repository: WorkspaceCoreRepository,
        workspaceId: UUID,
        tabId: UUID,
        panes: [WorkspaceCoreRepository.PaneRecord]
    ) throws {
        try seedWorkspaceShellsAndPanes(repository, workspaceId: workspaceId, tabIds: [tabId], panes: panes)
    }

    private func seedWorkspaceShellsAndPanes(
        _ repository: WorkspaceCoreRepository,
        workspaceId: UUID,
        tabIds: [UUID],
        panes: [WorkspaceCoreRepository.PaneRecord]
    ) throws {
        guard panes.count >= tabIds.count else {
            throw TabGraphMembershipFixtureError.insufficientLayoutPanesForSeed
        }
        let seededTabStates = tabIds.enumerated().map { index, tabId in
            let tabPane = panes[index]
            return WorkspaceCoreRepository.TabGraphStateRecord(
                tabId: tabId,
                allPaneIds: [tabPane.id],
                arrangements: [
                    makeArrangement(
                        id: UUID(uuidString: "00000000-0000-0000-0000-\(String(tabId.uuidString.suffix(12)))")!,
                        layout: Layout(paneId: tabPane.id)
                    )
                ]
            )
        }
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Tab Validation",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        try repository.replacePaneGraph(workspaceId: workspaceId, graph: .init(panes: panes))
        try repository.replaceTabShellsAndGraph(
            workspaceId: workspaceId,
            shells: tabIds.map { .init(id: $0, name: "Tab") },
            graph: .init(tabs: seededTabStates)
        )
    }

    private func makeFloatingPane(
        id: UUID,
        placement: WorkspaceCoreRepository.PanePlacementRecord = .layout,
        drawer: WorkspaceCoreRepository.DrawerRecord? = nil
    ) -> WorkspaceCoreRepository.PaneRecord {
        .init(
            id: id,
            content: .terminal(provider: .zmx, lifetime: .persistent),
            metadata: .init(
                source: .floating(launchDirectory: URL(fileURLWithPath: "/tmp/agentstudio/tab-membership")),
                executionBackend: .local,
                createdAt: Date(timeIntervalSince1970: 300),
                title: "Pane",
                durableFacets: .init(cwd: URL(fileURLWithPath: "/tmp/agentstudio/tab-membership"))
            ),
            residency: .active,
            placement: placement,
            drawer: drawer,
            updatedAt: Date(timeIntervalSince1970: 500)
        )
    }

    private func makeArrangement(
        id: UUID,
        name: String = "Default",
        isDefault: Bool = true,
        layout: Layout,
        minimizedPaneIds: Set<UUID> = [],
        showsMinimizedPanes: Bool = true,
        drawerViews: [UUID: WorkspaceCoreRepository.DrawerViewGraphRecord] = [:]
    ) -> WorkspaceCoreRepository.TabArrangementGraphRecord {
        .init(
            id: id,
            name: name,
            isDefault: isDefault,
            layout: layout,
            minimizedPaneIds: minimizedPaneIds,
            showsMinimizedPanes: showsMinimizedPanes,
            drawerViews: drawerViews
        )
    }
}

private enum TabGraphMembershipFixtureError: Error {
    case insufficientLayoutPanesForSeed
}
