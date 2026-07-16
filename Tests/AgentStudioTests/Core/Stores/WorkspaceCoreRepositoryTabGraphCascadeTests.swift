import Foundation
import Testing

@testable import AgentStudio

@Suite("WorkspaceCoreRepositoryTabGraphCascadeTests")
struct WorkspaceCoreRepositoryTabGraphCascadeTests {
    @Test("pane graph deletion preserves adjacent arrangement divider identity")
    func paneGraphDeletionPreservesAdjacentArrangementDividerIdentity() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000007001")!
        let tabId = UUID(uuidString: "00000000-0000-0000-0000-000000007101")!
        let firstPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000007201")!
        let secondPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000007202")!
        let thirdPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000007203")!
        let arrangementId = UUID(uuidString: "00000000-0000-0000-0000-000000007301")!
        let firstDividerId = UUID(uuidString: "00000000-0000-0000-0000-000000007401")!
        let secondDividerId = UUID(uuidString: "00000000-0000-0000-0000-000000007402")!

        try upsertWorkspace(repository, workspaceId: workspaceId)
        try repository.replacePaneGraph(
            workspaceId: workspaceId,
            graph: .init(panes: [
                makeFloatingPane(id: firstPaneId),
                makeFloatingPane(id: secondPaneId),
                makeFloatingPane(id: thirdPaneId),
            ])
        )
        try repository.replaceTabShellsAndGraph(
            workspaceId: workspaceId,
            shells: [.init(id: tabId, name: "Main")],
            graph: .init(tabs: [
                makeArrangementCascadeTab(
                    tabId: tabId,
                    arrangementId: arrangementId,
                    paneIds: [firstPaneId, secondPaneId, thirdPaneId],
                    dividerIds: [firstDividerId, secondDividerId]
                )
            ])
        )

        try repository.replacePaneGraph(
            workspaceId: workspaceId,
            graph: .init(panes: [
                makeFloatingPane(id: secondPaneId),
                makeFloatingPane(id: thirdPaneId),
            ])
        )

        #expect(
            try repository.fetchTabGraph(workspaceId: workspaceId)
                == .init(tabs: [
                    makeArrangementCascadeTab(
                        tabId: tabId,
                        arrangementId: arrangementId,
                        paneIds: [secondPaneId, thirdPaneId],
                        dividerIds: [secondDividerId]
                    )
                ])
        )
    }

    @Test("pane graph deletion preserves adjacent drawer divider identity")
    func paneGraphDeletionPreservesAdjacentDrawerDividerIdentity() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000007002")!
        let tabId = UUID(uuidString: "00000000-0000-0000-0000-000000007102")!
        let parentPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000007204")!
        let firstDrawerPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000007205")!
        let secondDrawerPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000007206")!
        let thirdDrawerPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000007207")!
        let drawerId = UUID(uuidString: "00000000-0000-0000-0000-000000007501")!
        let arrangementId = UUID(uuidString: "00000000-0000-0000-0000-000000007302")!
        let firstDividerId = UUID(uuidString: "00000000-0000-0000-0000-000000007403")!
        let secondDividerId = UUID(uuidString: "00000000-0000-0000-0000-000000007404")!

        try upsertWorkspace(repository, workspaceId: workspaceId)
        try repository.replacePaneGraph(
            workspaceId: workspaceId,
            graph: .init(panes: [
                makeFloatingPane(
                    id: parentPaneId,
                    drawer: .init(
                        drawerId: drawerId,
                        parentPaneId: parentPaneId,
                        childPaneIds: [firstDrawerPaneId, secondDrawerPaneId, thirdDrawerPaneId]
                    )
                ),
                makeFloatingPane(id: firstDrawerPaneId, placement: .drawerChild(parentPaneId: parentPaneId)),
                makeFloatingPane(id: secondDrawerPaneId, placement: .drawerChild(parentPaneId: parentPaneId)),
                makeFloatingPane(id: thirdDrawerPaneId, placement: .drawerChild(parentPaneId: parentPaneId)),
            ])
        )
        try repository.replaceTabShellsAndGraph(
            workspaceId: workspaceId,
            shells: [.init(id: tabId, name: "Main")],
            graph: .init(tabs: [
                makeDrawerCascadeTab(
                    tabId: tabId,
                    parentPaneId: parentPaneId,
                    drawerId: drawerId,
                    arrangementId: arrangementId,
                    drawerPaneIds: [firstDrawerPaneId, secondDrawerPaneId, thirdDrawerPaneId],
                    dividerIds: [firstDividerId, secondDividerId]
                )
            ])
        )

        try repository.replacePaneGraph(
            workspaceId: workspaceId,
            graph: .init(panes: [
                makeFloatingPane(
                    id: parentPaneId,
                    drawer: .init(
                        drawerId: drawerId,
                        parentPaneId: parentPaneId,
                        childPaneIds: [secondDrawerPaneId, thirdDrawerPaneId]
                    )
                ),
                makeFloatingPane(id: secondDrawerPaneId, placement: .drawerChild(parentPaneId: parentPaneId)),
                makeFloatingPane(id: thirdDrawerPaneId, placement: .drawerChild(parentPaneId: parentPaneId)),
            ])
        )

        #expect(
            try repository.fetchTabGraph(workspaceId: workspaceId)
                == .init(tabs: [
                    makeDrawerCascadeTab(
                        tabId: tabId,
                        parentPaneId: parentPaneId,
                        drawerId: drawerId,
                        arrangementId: arrangementId,
                        drawerPaneIds: [secondDrawerPaneId, thirdDrawerPaneId],
                        dividerIds: [secondDividerId]
                    )
                ])
        )
    }

    private func makeArrangementCascadeTab(
        tabId: UUID,
        arrangementId: UUID,
        paneIds: [UUID],
        dividerIds: [UUID]
    ) -> WorkspaceCoreRepository.TabGraphStateRecord {
        .init(
            tabId: tabId,
            allPaneIds: paneIds,
            arrangements: [
                .init(
                    id: arrangementId,
                    name: "Default",
                    isDefault: true,
                    layout: makeLayout(paneIds: paneIds, dividerIds: dividerIds),
                    minimizedPaneIds: [],
                    showsMinimizedPanes: true,
                    drawerViews: [:]
                )
            ]
        )
    }

    private func makeDrawerCascadeTab(
        tabId: UUID,
        parentPaneId: UUID,
        drawerId: UUID,
        arrangementId: UUID,
        drawerPaneIds: [UUID],
        dividerIds: [UUID]
    ) -> WorkspaceCoreRepository.TabGraphStateRecord {
        .init(
            tabId: tabId,
            allPaneIds: [parentPaneId] + drawerPaneIds,
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
                            layout: DrawerGridLayout(
                                topRow: makeLayout(paneIds: drawerPaneIds, dividerIds: dividerIds)
                            ),
                            minimizedPaneIds: []
                        )
                    ]
                )
            ]
        )
    }

    private func makeLayout(paneIds: [UUID], dividerIds: [UUID]) -> Layout {
        let ratio = 1.0 / Double(paneIds.count)
        return Layout(
            panes: paneIds.map { .init(paneId: $0, ratio: ratio) },
            dividerIds: dividerIds
        )
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
                durableFacets: .init(cwd: URL(fileURLWithPath: "/tmp/agentstudio/tab-cascade"))
            ),
            residency: .active,
            placement: placement,
            drawer: drawer,
            updatedAt: Date(timeIntervalSince1970: 500)
        )
    }

    private func upsertWorkspace(_ repository: WorkspaceCoreRepository, workspaceId: UUID) throws {
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Cascade",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
    }
}
