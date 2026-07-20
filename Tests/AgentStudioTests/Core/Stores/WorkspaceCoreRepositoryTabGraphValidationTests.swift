import Foundation
import GRDB
import Testing

@testable import AgentStudio

@Suite("WorkspaceCoreRepositoryTabGraphValidationTests")
struct WorkspaceCoreRepositoryTabGraphValidationTests {
    @Test("tab graph replace rejects arrangement pane missing from tab membership")
    func tabGraphReplaceRejectsArrangementPaneMissingFromTabMembership() throws {
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let repository = fixture.repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000004001")!
        let tabId = UUID(uuidString: "00000000-0000-0000-0000-000000004101")!
        let firstPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000004201")!
        let missingMembershipPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000004202")!
        let arrangementId = UUID(uuidString: "00000000-0000-0000-0000-000000004301")!
        try seedWorkspaceShellAndPanes(
            repository,
            workspaceId: workspaceId,
            tabId: tabId,
            panes: [makeFloatingPane(id: firstPaneId), makeFloatingPane(id: missingMembershipPaneId)]
        )

        #expect(
            throws: WorkspaceCoreRepositoryError.arrangementPaneMissingFromTab(
                tabId: tabId,
                arrangementId: arrangementId,
                paneId: missingMembershipPaneId
            )
        ) {
            try repository.replaceTabGraph(
                workspaceId: workspaceId,
                graph: .init(tabs: [
                    .init(
                        tabId: tabId,
                        allPaneIds: [firstPaneId],
                        arrangements: [
                            makeArrangement(
                                id: arrangementId,
                                layout: Layout(
                                    panes: [
                                        .init(paneId: firstPaneId, ratio: 0.5),
                                        .init(paneId: missingMembershipPaneId, ratio: 0.5),
                                    ],
                                    dividerIds: [UUID(uuidString: "00000000-0000-0000-0000-000000004401")!]
                                )
                            )
                        ]
                    )
                ])
            )
        }

        #expect(try fixture.fetchTabPaneCount(tabId: tabId, paneId: firstPaneId) == 1)
        #expect(try fixture.fetchTabPaneCount(tabId: tabId, paneId: missingMembershipPaneId) == 0)
    }

    @Test("tab graph replace rejects duplicate pane in arrangement layout before SQL conflict")
    func tabGraphReplaceRejectsDuplicatePaneInArrangementLayoutBeforeSQLConflict() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000004010")!
        let tabId = UUID(uuidString: "00000000-0000-0000-0000-000000004112")!
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000004216")!
        let arrangementId = UUID(uuidString: "00000000-0000-0000-0000-000000004311")!
        try seedWorkspaceShellAndPanes(
            repository,
            workspaceId: workspaceId,
            tabId: tabId,
            panes: [makeFloatingPane(id: paneId)]
        )

        #expect(
            throws: WorkspaceCoreRepositoryError.arrangementLayoutPaneListedMultipleTimes(
                arrangementId: arrangementId,
                paneId: paneId
            )
        ) {
            try repository.replaceTabGraph(
                workspaceId: workspaceId,
                graph: .init(tabs: [
                    .init(
                        tabId: tabId,
                        allPaneIds: [paneId],
                        arrangements: [
                            makeArrangement(
                                id: arrangementId,
                                layout: Layout(
                                    panes: [
                                        .init(paneId: paneId, ratio: 0.5),
                                        .init(paneId: paneId, ratio: 0.5),
                                    ],
                                    dividerIds: [UUID(uuidString: "00000000-0000-0000-0000-000000004403")!]
                                )
                            )
                        ]
                    )
                ])
            )
        }
    }

    @Test("tab graph replace rejects duplicate divider in arrangement layout before SQL conflict")
    func tabGraphReplaceRejectsDuplicateDividerInArrangementLayoutBeforeSQLConflict() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000004011")!
        let tabId = UUID(uuidString: "00000000-0000-0000-0000-000000004113")!
        let firstPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000004217")!
        let secondPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000004218")!
        let thirdPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000004219")!
        let arrangementId = UUID(uuidString: "00000000-0000-0000-0000-000000004312")!
        let dividerId = UUID(uuidString: "00000000-0000-0000-0000-000000004404")!
        try seedWorkspaceShellAndPanes(
            repository,
            workspaceId: workspaceId,
            tabId: tabId,
            panes: [
                makeFloatingPane(id: firstPaneId),
                makeFloatingPane(id: secondPaneId),
                makeFloatingPane(id: thirdPaneId),
            ]
        )

        #expect(
            throws: WorkspaceCoreRepositoryError.layoutDividerListedMultipleTimes(
                arrangementId: arrangementId,
                dividerId: dividerId
            )
        ) {
            try repository.replaceTabGraph(
                workspaceId: workspaceId,
                graph: .init(tabs: [
                    .init(
                        tabId: tabId,
                        allPaneIds: [firstPaneId, secondPaneId, thirdPaneId],
                        arrangements: [
                            makeArrangement(
                                id: arrangementId,
                                layout: Layout(
                                    panes: [
                                        .init(paneId: firstPaneId, ratio: 0.34),
                                        .init(paneId: secondPaneId, ratio: 0.33),
                                        .init(paneId: thirdPaneId, ratio: 0.33),
                                    ],
                                    dividerIds: [dividerId, dividerId]
                                )
                            )
                        ]
                    )
                ])
            )
        }
    }

    @Test("tab graph replace rejects empty tab state")
    func tabGraphReplaceRejectsEmptyTabState() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000004012")!
        let tabId = UUID(uuidString: "00000000-0000-0000-0000-000000004114")!
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000004222")!
        let arrangementId = UUID(uuidString: "00000000-0000-0000-0000-000000004313")!
        try seedWorkspaceShellAndPanes(
            repository,
            workspaceId: workspaceId,
            tabId: tabId,
            panes: [makeFloatingPane(id: paneId)]
        )

        #expect(throws: WorkspaceCoreRepositoryError.tabHasNoPanes(tabId)) {
            try repository.replaceTabGraph(
                workspaceId: workspaceId,
                graph: .init(tabs: [
                    .init(
                        tabId: tabId,
                        allPaneIds: [],
                        arrangements: [
                            makeArrangement(id: arrangementId, layout: Layout())
                        ]
                    )
                ])
            )
        }
    }

    @Test("tab graph replace rejects empty default arrangement layout")
    func tabGraphReplaceRejectsEmptyDefaultArrangementLayout() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000004013")!
        let tabId = UUID(uuidString: "00000000-0000-0000-0000-000000004115")!
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000004223")!
        let arrangementId = UUID(uuidString: "00000000-0000-0000-0000-000000004314")!
        try seedWorkspaceShellAndPanes(
            repository,
            workspaceId: workspaceId,
            tabId: tabId,
            panes: [makeFloatingPane(id: paneId)]
        )

        #expect(
            throws: WorkspaceCoreRepositoryError.defaultArrangementLayoutIsEmpty(
                tabId: tabId,
                arrangementId: arrangementId
            )
        ) {
            try repository.replaceTabGraph(
                workspaceId: workspaceId,
                graph: .init(tabs: [
                    .init(
                        tabId: tabId,
                        allPaneIds: [paneId],
                        arrangements: [
                            makeArrangement(id: arrangementId, layout: Layout())
                        ]
                    )
                ])
            )
        }
    }

    @Test("tab graph replace rejects empty drawer view layout")
    func tabGraphReplaceRejectsEmptyDrawerViewLayout() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000004015")!
        let tabId = UUID(uuidString: "00000000-0000-0000-0000-000000004117")!
        let parentPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000004229")!
        let drawerPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000004230")!
        let drawerId = UUID(uuidString: "00000000-0000-0000-0000-000000004504")!
        let defaultArrangementId = UUID(uuidString: "00000000-0000-0000-0000-000000004316")!
        let alternateArrangementId = UUID(uuidString: "00000000-0000-0000-0000-000000004317")!
        try seedWorkspaceShellAndPanes(
            repository,
            workspaceId: workspaceId,
            tabId: tabId,
            panes: [
                makeFloatingPane(
                    id: parentPaneId,
                    drawer: .init(drawerId: drawerId, parentPaneId: parentPaneId, childPaneIds: [drawerPaneId])
                ),
                makeFloatingPane(id: drawerPaneId, placement: .drawerChild(parentPaneId: parentPaneId)),
            ]
        )

        #expect(
            throws: WorkspaceCoreRepositoryError.drawerViewLayoutIsEmpty(
                arrangementId: alternateArrangementId,
                drawerId: drawerId
            )
        ) {
            try repository.replaceTabGraph(
                workspaceId: workspaceId,
                graph: .init(tabs: [
                    .init(
                        tabId: tabId,
                        allPaneIds: [parentPaneId, drawerPaneId],
                        arrangements: [
                            makeArrangement(
                                id: defaultArrangementId,
                                layout: Layout(paneId: parentPaneId),
                                drawerViews: [
                                    drawerId: .init(
                                        layout: DrawerGridLayout(topRow: Layout(paneId: drawerPaneId)),
                                        minimizedPaneIds: []
                                    )
                                ]
                            ),
                            makeArrangement(
                                id: alternateArrangementId,
                                name: "Alternate",
                                isDefault: false,
                                layout: Layout(paneId: parentPaneId),
                                drawerViews: [
                                    drawerId: .init(layout: DrawerGridLayout(), minimizedPaneIds: [])
                                ]
                            ),
                        ]
                    )
                ])
            )
        }
    }

    @Test("tab graph replace rejects drawer child in main arrangement layout")
    func tabGraphReplaceRejectsDrawerChildInMainArrangementLayout() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000004002")!
        let tabId = UUID(uuidString: "00000000-0000-0000-0000-000000004102")!
        let parentPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000004203")!
        let drawerPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000004204")!
        let drawerId = UUID(uuidString: "00000000-0000-0000-0000-000000004501")!
        let arrangementId = UUID(uuidString: "00000000-0000-0000-0000-000000004302")!
        try seedWorkspaceShellAndPanes(
            repository,
            workspaceId: workspaceId,
            tabId: tabId,
            panes: [
                makeFloatingPane(
                    id: parentPaneId,
                    drawer: .init(drawerId: drawerId, parentPaneId: parentPaneId, childPaneIds: [drawerPaneId])
                ),
                makeFloatingPane(id: drawerPaneId, placement: .drawerChild(parentPaneId: parentPaneId)),
            ]
        )

        #expect(
            throws: WorkspaceCoreRepositoryError.arrangementLayoutPaneUsesDrawerChild(
                arrangementId: arrangementId,
                paneId: drawerPaneId,
                parentPaneId: parentPaneId
            )
        ) {
            try repository.replaceTabGraph(
                workspaceId: workspaceId,
                graph: .init(tabs: [
                    .init(
                        tabId: tabId,
                        allPaneIds: [parentPaneId, drawerPaneId],
                        arrangements: [
                            makeArrangement(
                                id: arrangementId,
                                layout: Layout(
                                    panes: [
                                        .init(paneId: parentPaneId, ratio: 0.5),
                                        .init(paneId: drawerPaneId, ratio: 0.5),
                                    ],
                                    dividerIds: [UUID(uuidString: "00000000-0000-0000-0000-000000004402")!]
                                ),
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
        }
    }

    @Test("tab graph replace rejects duplicate drawer divider across rows")
    func tabGraphReplaceRejectsDuplicateDrawerDividerAcrossRows() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000004014")!
        let tabId = UUID(uuidString: "00000000-0000-0000-0000-000000004116")!
        let parentPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000004224")!
        let topFirstPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000004225")!
        let topSecondPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000004226")!
        let bottomFirstPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000004227")!
        let bottomSecondPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000004228")!
        let drawerId = UUID(uuidString: "00000000-0000-0000-0000-000000004503")!
        let arrangementId = UUID(uuidString: "00000000-0000-0000-0000-000000004315")!
        let duplicateDividerId = UUID(uuidString: "00000000-0000-0000-0000-000000004405")!
        let drawerPaneIds = [topFirstPaneId, topSecondPaneId, bottomFirstPaneId, bottomSecondPaneId]
        let parentPane = makeFloatingPane(
            id: parentPaneId,
            drawer: .init(drawerId: drawerId, parentPaneId: parentPaneId, childPaneIds: drawerPaneIds)
        )
        let drawerChildPanes = drawerPaneIds.map {
            makeFloatingPane(id: $0, placement: .drawerChild(parentPaneId: parentPaneId))
        }
        try seedWorkspaceShellAndPanes(
            repository,
            workspaceId: workspaceId,
            tabId: tabId,
            panes: [parentPane] + drawerChildPanes
        )

        #expect(
            throws: WorkspaceCoreRepositoryError.drawerViewDividerListedMultipleTimes(
                arrangementId: arrangementId,
                drawerId: drawerId,
                dividerId: duplicateDividerId
            )
        ) {
            try repository.replaceTabGraph(
                workspaceId: workspaceId,
                graph: .init(tabs: [
                    .init(
                        tabId: tabId,
                        allPaneIds: [parentPaneId] + drawerPaneIds,
                        arrangements: [
                            makeArrangement(
                                id: arrangementId,
                                layout: Layout(paneId: parentPaneId),
                                drawerViews: [
                                    drawerId: .init(
                                        layout: DrawerGridLayout(
                                            topRow: Layout(
                                                panes: [
                                                    .init(paneId: topFirstPaneId, ratio: 0.5),
                                                    .init(paneId: topSecondPaneId, ratio: 0.5),
                                                ],
                                                dividerIds: [duplicateDividerId]
                                            ),
                                            bottomRow: Layout(
                                                panes: [
                                                    .init(paneId: bottomFirstPaneId, ratio: 0.5),
                                                    .init(paneId: bottomSecondPaneId, ratio: 0.5),
                                                ],
                                                dividerIds: [duplicateDividerId]
                                            )
                                        ),
                                        minimizedPaneIds: []
                                    )
                                ]
                            )
                        ]
                    )
                ])
            )
        }
    }

    @Test("tab graph replace rejects drawer view whose parent is absent from arrangement layout")
    func tabGraphReplaceRejectsDrawerViewWhoseParentIsAbsentFromArrangementLayout() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000004009")!
        let tabId = UUID(uuidString: "00000000-0000-0000-0000-000000004111")!
        let parentPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000004213")!
        let siblingPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000004214")!
        let drawerPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000004215")!
        let drawerId = UUID(uuidString: "00000000-0000-0000-0000-000000004502")!
        let arrangementId = UUID(uuidString: "00000000-0000-0000-0000-000000004310")!
        try seedWorkspaceShellAndPanes(
            repository,
            workspaceId: workspaceId,
            tabId: tabId,
            panes: [
                makeFloatingPane(
                    id: parentPaneId,
                    drawer: .init(drawerId: drawerId, parentPaneId: parentPaneId, childPaneIds: [drawerPaneId])
                ),
                makeFloatingPane(id: siblingPaneId),
                makeFloatingPane(id: drawerPaneId, placement: .drawerChild(parentPaneId: parentPaneId)),
            ]
        )

        #expect(
            throws: WorkspaceCoreRepositoryError.drawerViewParentPaneMissingFromLayout(
                arrangementId: arrangementId,
                drawerId: drawerId,
                parentPaneId: parentPaneId
            )
        ) {
            try repository.replaceTabGraph(
                workspaceId: workspaceId,
                graph: .init(tabs: [
                    .init(
                        tabId: tabId,
                        allPaneIds: [siblingPaneId, drawerPaneId],
                        arrangements: [
                            makeArrangement(
                                id: arrangementId,
                                layout: Layout(paneId: siblingPaneId),
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
        }
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
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Tab Graph Validation",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        try repository.replacePaneGraph(workspaceId: workspaceId, graph: .init(panes: panes))
        let layoutPaneIds = panes.compactMap { pane -> UUID? in
            switch pane.placement {
            case .layout:
                return pane.id
            case .drawerChild:
                return nil
            }
        }
        guard layoutPaneIds.count >= tabIds.count else {
            throw WorkspaceCoreRepositoryTabGraphFixtureError.insufficientLayoutPanesForSeed
        }
        let shells = tabIds.enumerated().map { index, tabId in
            WorkspaceCoreRepository.TabShellRecord(id: tabId, name: "Tab \(index + 1)")
        }
        let seedTabs = zip(tabIds, layoutPaneIds).map { tabId, paneId in
            WorkspaceCoreRepository.TabGraphStateRecord(
                tabId: tabId,
                allPaneIds: [paneId],
                arrangements: [
                    makeArrangement(
                        id: UUID(uuidString: "10000000-0000-0000-0000-\(String(tabId.uuidString.suffix(12)))")!,
                        layout: Layout(paneId: paneId)
                    )
                ]
            )
        }
        try repository.replaceTabShellsAndGraph(
            workspaceId: workspaceId,
            shells: shells,
            graph: .init(tabs: seedTabs)
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
                durableFacets: .init(cwd: URL(fileURLWithPath: "/tmp/agentstudio/tab-validation"))
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

private enum WorkspaceCoreRepositoryTabGraphFixtureError: Error {
    case insufficientLayoutPanesForSeed
}
