import Foundation
import GRDB
import Testing

@testable import AgentStudio

@Suite("WorkspaceCoreRepositoryTabGraphTests")
struct WorkspaceCoreRepositoryTabGraphTests {
    @Test("tab shells round trip names and order independently from graph rows")
    func tabShellsRoundTripNamesAndOrderIndependentlyFromGraphRows() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000003001")!
        let firstTabId = UUID(uuidString: "00000000-0000-0000-0000-000000003101")!
        let secondTabId = UUID(uuidString: "00000000-0000-0000-0000-000000003102")!
        let firstPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000003207")!
        let secondPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000003208")!
        try upsertWorkspace(repository, workspaceId: workspaceId, name: "Tabs")
        try repository.replacePaneGraph(
            workspaceId: workspaceId,
            graph: .init(panes: [
                makeFloatingPane(id: firstPaneId),
                makeFloatingPane(id: secondPaneId),
            ])
        )

        try repository.replaceTabShellsAndGraph(
            workspaceId: workspaceId,
            shells: [
                .init(id: firstTabId, name: "First"),
                .init(id: secondTabId, name: "Second"),
            ],
            graph: .init(tabs: [
                makeSinglePaneTabGraph(tabId: firstTabId, paneId: firstPaneId),
                makeSinglePaneTabGraph(tabId: secondTabId, paneId: secondPaneId),
            ])
        )

        #expect(
            try repository.fetchTabShells(workspaceId: workspaceId) == [
                .init(id: firstTabId, name: "First"),
                .init(id: secondTabId, name: "Second"),
            ]
        )
    }

    @Test("tab graph round trips memberships layouts minimized panes and drawer views")
    func tabGraphRoundTripsMembershipsLayoutsMinimizedPanesAndDrawerViews() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000003002")!
        let tabId = UUID(uuidString: "00000000-0000-0000-0000-000000003103")!
        let parentPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000003201")!
        let secondPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000003202")!
        let drawerPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000003203")!
        let drawerBottomPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000003204")!
        let drawerId = UUID(uuidString: "00000000-0000-0000-0000-000000003301")!
        let arrangementId = UUID(uuidString: "00000000-0000-0000-0000-000000003401")!
        let dividerId = UUID(uuidString: "00000000-0000-0000-0000-000000003501")!
        try upsertWorkspace(repository, workspaceId: workspaceId, name: "Tab Graph")
        try repository.replacePaneGraph(
            workspaceId: workspaceId,
            graph: .init(panes: [
                makeFloatingPane(
                    id: parentPaneId,
                    drawer: .init(
                        drawerId: drawerId,
                        parentPaneId: parentPaneId,
                        childPaneIds: [drawerPaneId, drawerBottomPaneId]
                    )
                ),
                makeFloatingPane(id: secondPaneId),
                makeFloatingPane(id: drawerPaneId, placement: .drawerChild(parentPaneId: parentPaneId)),
                makeFloatingPane(id: drawerBottomPaneId, placement: .drawerChild(parentPaneId: parentPaneId)),
            ])
        )
        let graph = WorkspaceCoreRepository.TabGraphRecord(
            tabs: [
                .init(
                    tabId: tabId,
                    allPaneIds: [parentPaneId, secondPaneId, drawerPaneId, drawerBottomPaneId],
                    arrangements: [
                        .init(
                            id: arrangementId,
                            name: "Default",
                            isDefault: true,
                            layout: .init(
                                panes: [
                                    .init(paneId: parentPaneId, ratio: 0.4),
                                    .init(paneId: secondPaneId, ratio: 0.6),
                                ],
                                dividerIds: [dividerId]
                            ),
                            minimizedPaneIds: [secondPaneId],
                            showsMinimizedPanes: false,
                            drawerViews: [
                                drawerId: .init(
                                    layout: .init(
                                        topRow: .init(
                                            panes: [
                                                .init(paneId: drawerPaneId, ratio: 1.0)
                                            ],
                                            dividerIds: []
                                        ),
                                        bottomRow: .init(
                                            panes: [
                                                .init(paneId: drawerBottomPaneId, ratio: 1.0)
                                            ],
                                            dividerIds: []
                                        ),
                                        rowSplitRatio: 0.35
                                    ),
                                    minimizedPaneIds: [drawerPaneId]
                                )
                            ]
                        )
                    ]
                )
            ]
        )

        try repository.replaceTabShellsAndGraph(
            workspaceId: workspaceId,
            shells: [.init(id: tabId, name: "Main")],
            graph: graph
        )
        let restoredGraph = try repository.fetchTabGraph(workspaceId: workspaceId)

        #expect(restoredGraph == graph)
    }

    @Test("tab shell reorder preserves graph rows for retained tabs")
    func tabShellReorderPreservesGraphRowsForRetainedTabs() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000003003")!
        let firstTabId = UUID(uuidString: "00000000-0000-0000-0000-000000003104")!
        let secondTabId = UUID(uuidString: "00000000-0000-0000-0000-000000003105")!
        let firstPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000003205")!
        let secondPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000003206")!
        try upsertWorkspace(repository, workspaceId: workspaceId, name: "Reorder Tabs")
        try repository.replacePaneGraph(
            workspaceId: workspaceId,
            graph: .init(panes: [
                makeFloatingPane(id: firstPaneId),
                makeFloatingPane(id: secondPaneId),
            ])
        )
        try repository.replaceTabShellsAndGraph(
            workspaceId: workspaceId,
            shells: [
                .init(id: firstTabId, name: "First"),
                .init(id: secondTabId, name: "Second"),
            ],
            graph: .init(tabs: [
                makeSinglePaneTabGraph(tabId: firstTabId, paneId: firstPaneId),
                makeSinglePaneTabGraph(tabId: secondTabId, paneId: secondPaneId),
            ])
        )
        let firstTabGraph = makeSinglePaneTabGraph(tabId: firstTabId, paneId: firstPaneId)
        let secondTabGraph = makeSinglePaneTabGraph(tabId: secondTabId, paneId: secondPaneId)

        try repository.replaceTabShells(
            workspaceId: workspaceId,
            shells: [
                .init(id: secondTabId, name: "Second Renamed"),
                .init(id: firstTabId, name: "First Renamed"),
            ]
        )

        #expect(
            try repository.fetchTabShells(workspaceId: workspaceId) == [
                .init(id: secondTabId, name: "Second Renamed"),
                .init(id: firstTabId, name: "First Renamed"),
            ]
        )
        #expect(
            try repository.fetchTabGraph(workspaceId: workspaceId)
                == .init(tabs: [secondTabGraph, firstTabGraph])
        )
    }

    @Test("tab shell replacement rejects identity changes without graph transaction")
    func tabShellReplacementRejectsIdentityChangesWithoutGraphTransaction() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000003004")!
        let firstTabId = UUID(uuidString: "00000000-0000-0000-0000-000000003106")!
        let secondTabId = UUID(uuidString: "00000000-0000-0000-0000-000000003107")!
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000003209")!
        try upsertWorkspace(repository, workspaceId: workspaceId, name: "Shell Guard")
        try repository.replacePaneGraph(workspaceId: workspaceId, graph: .init(panes: [makeFloatingPane(id: paneId)]))
        try repository.replaceTabShellsAndGraph(
            workspaceId: workspaceId,
            shells: [.init(id: firstTabId, name: "First")],
            graph: .init(tabs: [makeSinglePaneTabGraph(tabId: firstTabId, paneId: paneId)])
        )

        #expect(
            throws: WorkspaceCoreRepositoryError.tabShellSetRequiresGraphReplacement(
                existingTabIds: [firstTabId],
                incomingTabIds: [firstTabId, secondTabId]
            )
        ) {
            try repository.replaceTabShells(
                workspaceId: workspaceId,
                shells: [
                    .init(id: firstTabId, name: "First"),
                    .init(id: secondTabId, name: "Second"),
                ]
            )
        }
    }

    @Test("combined tab shell and graph replacement rolls back shell rows when graph is invalid")
    func combinedTabShellAndGraphReplacementRollsBackShellRowsWhenGraphIsInvalid() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000003005")!
        let firstTabId = UUID(uuidString: "00000000-0000-0000-0000-000000003108")!
        let secondTabId = UUID(uuidString: "00000000-0000-0000-0000-000000003109")!
        let firstPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000003210")!
        let secondPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000003211")!
        let originalShells = [WorkspaceCoreRepository.TabShellRecord(id: firstTabId, name: "First")]
        let originalGraph = WorkspaceCoreRepository.TabGraphRecord(tabs: [
            makeSinglePaneTabGraph(tabId: firstTabId, paneId: firstPaneId)
        ])
        try upsertWorkspace(repository, workspaceId: workspaceId, name: "Atomic Tabs")
        try repository.replacePaneGraph(
            workspaceId: workspaceId,
            graph: .init(panes: [
                makeFloatingPane(id: firstPaneId),
                makeFloatingPane(id: secondPaneId),
            ])
        )
        try repository.replaceTabShellsAndGraph(
            workspaceId: workspaceId,
            shells: originalShells,
            graph: originalGraph
        )

        #expect(throws: WorkspaceCoreRepositoryError.tabGraphMissingTabState(secondTabId)) {
            try repository.replaceTabShellsAndGraph(
                workspaceId: workspaceId,
                shells: [
                    .init(id: firstTabId, name: "First Renamed"),
                    .init(id: secondTabId, name: "Second"),
                ],
                graph: .init(tabs: [
                    makeSinglePaneTabGraph(tabId: firstTabId, paneId: firstPaneId)
                ])
            )
        }

        #expect(try repository.fetchTabShells(workspaceId: workspaceId) == originalShells)
        #expect(try repository.fetchTabGraph(workspaceId: workspaceId) == originalGraph)
    }

    @Test("fetch tab graph rejects shell without graph rows")
    func fetchTabGraphRejectsShellWithoutGraphRows() throws {
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let repository = fixture.repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000003006")!
        let tabId = UUID(uuidString: "00000000-0000-0000-0000-000000003110")!
        try upsertWorkspace(repository, workspaceId: workspaceId, name: "Dangling Shell")
        try fixture.insertTabShell(workspaceId: workspaceId, tabId: tabId)

        #expect(throws: WorkspaceCoreRepositoryError.tabHasNoPanes(tabId)) {
            try repository.fetchTabGraph(workspaceId: workspaceId)
        }
    }

    @Test("pane graph deletion prunes arrangement layout dividers")
    func paneGraphDeletionPrunesArrangementLayoutDividers() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000003008")!
        let tabId = UUID(uuidString: "00000000-0000-0000-0000-000000003112")!
        let firstPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000003214")!
        let secondPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000003215")!
        let thirdPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000003216")!
        let arrangementId = UUID(uuidString: "00000000-0000-0000-0000-000000003403")!
        let firstDividerId = UUID(uuidString: "00000000-0000-0000-0000-000000003504")!
        let secondDividerId = UUID(uuidString: "00000000-0000-0000-0000-000000003505")!
        try upsertWorkspace(repository, workspaceId: workspaceId, name: "Pane Cascade")
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
                .init(
                    tabId: tabId,
                    allPaneIds: [firstPaneId, secondPaneId, thirdPaneId],
                    arrangements: [
                        .init(
                            id: arrangementId,
                            name: "Default",
                            isDefault: true,
                            layout: Layout(
                                panes: [
                                    .init(paneId: firstPaneId, ratio: 0.34),
                                    .init(paneId: secondPaneId, ratio: 0.33),
                                    .init(paneId: thirdPaneId, ratio: 0.33),
                                ],
                                dividerIds: [firstDividerId, secondDividerId]
                            ),
                            minimizedPaneIds: [],
                            showsMinimizedPanes: true,
                            drawerViews: [:]
                        )
                    ]
                )
            ])
        )

        try repository.replacePaneGraph(
            workspaceId: workspaceId,
            graph: .init(panes: [
                makeFloatingPane(id: thirdPaneId)
            ])
        )

        #expect(
            try repository.fetchTabGraph(workspaceId: workspaceId)
                == .init(tabs: [
                    .init(
                        tabId: tabId,
                        allPaneIds: [thirdPaneId],
                        arrangements: [
                            .init(
                                id: arrangementId,
                                name: "Default",
                                isDefault: true,
                                layout: Layout(paneId: thirdPaneId),
                                minimizedPaneIds: [],
                                showsMinimizedPanes: true,
                                drawerViews: [:]
                            )
                        ]
                    )
                ])
        )
    }

    @Test("pane graph deletion prunes drawer view layout dividers")
    func paneGraphDeletionPrunesDrawerViewLayoutDividers() throws {
        let repository = try makeWorkspaceCoreRepositoryFixture().repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000003009")!
        let tabId = UUID(uuidString: "00000000-0000-0000-0000-000000003113")!
        let parentPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000003217")!
        let firstDrawerPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000003218")!
        let secondDrawerPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000003219")!
        let thirdDrawerPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000003220")!
        let scenario = DrawerCascadeScenario(
            tabId: tabId,
            parentPaneId: parentPaneId,
            drawerId: UUID(uuidString: "00000000-0000-0000-0000-000000003303")!,
            arrangementId: UUID(uuidString: "00000000-0000-0000-0000-000000003404")!
        )
        let firstDividerId = UUID(uuidString: "00000000-0000-0000-0000-000000003506")!
        let secondDividerId = UUID(uuidString: "00000000-0000-0000-0000-000000003507")!
        try seedDrawerCascadeGraph(
            repository,
            workspaceId: workspaceId,
            scenario: scenario,
            drawerPaneIds: [firstDrawerPaneId, secondDrawerPaneId, thirdDrawerPaneId],
            dividerIds: [firstDividerId, secondDividerId]
        )

        try repository.replacePaneGraph(
            workspaceId: workspaceId,
            graph: .init(panes: [
                makeFloatingPane(
                    id: parentPaneId,
                    drawer: .init(
                        drawerId: scenario.drawerId,
                        parentPaneId: parentPaneId,
                        childPaneIds: [thirdDrawerPaneId]
                    )
                ),
                makeFloatingPane(id: thirdDrawerPaneId, placement: .drawerChild(parentPaneId: parentPaneId)),
            ])
        )

        let expectedGraph = makeDrawerCascadeGraph(
            scenario: scenario,
            drawerPaneIds: [thirdDrawerPaneId],
            dividerIds: []
        )
        #expect(try repository.fetchTabGraph(workspaceId: workspaceId) == expectedGraph)
    }

    private func seedDrawerCascadeGraph(
        _ repository: WorkspaceCoreRepository,
        workspaceId: UUID,
        scenario: DrawerCascadeScenario,
        drawerPaneIds: [UUID],
        dividerIds: [UUID]
    ) throws {
        try upsertWorkspace(repository, workspaceId: workspaceId, name: "Drawer Cascade")
        let parentPane = makeFloatingPane(
            id: scenario.parentPaneId,
            drawer: .init(
                drawerId: scenario.drawerId,
                parentPaneId: scenario.parentPaneId,
                childPaneIds: drawerPaneIds
            )
        )
        let drawerChildPanes = drawerPaneIds.map {
            makeFloatingPane(id: $0, placement: .drawerChild(parentPaneId: scenario.parentPaneId))
        }
        try repository.replacePaneGraph(
            workspaceId: workspaceId,
            graph: .init(panes: [parentPane] + drawerChildPanes)
        )
        try repository.replaceTabShellsAndGraph(
            workspaceId: workspaceId,
            shells: [.init(id: scenario.tabId, name: "Main")],
            graph: makeDrawerCascadeGraph(
                scenario: scenario,
                drawerPaneIds: drawerPaneIds,
                dividerIds: dividerIds
            )
        )
    }

    private func makeDrawerCascadeGraph(
        scenario: DrawerCascadeScenario,
        drawerPaneIds: [UUID],
        dividerIds: [UUID]
    ) -> WorkspaceCoreRepository.TabGraphRecord {
        .init(tabs: [
            .init(
                tabId: scenario.tabId,
                allPaneIds: [scenario.parentPaneId] + drawerPaneIds,
                arrangements: [
                    .init(
                        id: scenario.arrangementId,
                        name: "Default",
                        isDefault: true,
                        layout: Layout(paneId: scenario.parentPaneId),
                        minimizedPaneIds: [],
                        showsMinimizedPanes: true,
                        drawerViews: [
                            scenario.drawerId: makeDrawerCascadeView(paneIds: drawerPaneIds, dividerIds: dividerIds)
                        ]
                    )
                ]
            )
        ])
    }

    private func makeDrawerCascadeView(
        paneIds: [UUID],
        dividerIds: [UUID]
    ) -> WorkspaceCoreRepository.DrawerViewGraphRecord {
        let ratio = 1.0 / Double(paneIds.count)
        return .init(
            layout: DrawerGridLayout(
                topRow: Layout(
                    panes: paneIds.map { .init(paneId: $0, ratio: ratio) },
                    dividerIds: dividerIds
                )
            ),
            minimizedPaneIds: []
        )
    }

    private struct DrawerCascadeScenario {
        let tabId: UUID
        let parentPaneId: UUID
        let drawerId: UUID
        let arrangementId: UUID
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
                source: .floating(launchDirectory: URL(fileURLWithPath: "/tmp/agentstudio/tab-graph")),
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

    private func makeSinglePaneTabGraph(
        tabId: UUID,
        paneId: UUID
    ) -> WorkspaceCoreRepository.TabGraphStateRecord {
        .init(
            tabId: tabId,
            allPaneIds: [paneId],
            arrangements: [
                .init(
                    id: UUID(uuidString: "00000000-0000-0000-0000-\(String(tabId.uuidString.suffix(12)))")!,
                    name: "Default",
                    isDefault: true,
                    layout: Layout(paneId: paneId),
                    minimizedPaneIds: [],
                    showsMinimizedPanes: true,
                    drawerViews: [:]
                )
            ]
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
