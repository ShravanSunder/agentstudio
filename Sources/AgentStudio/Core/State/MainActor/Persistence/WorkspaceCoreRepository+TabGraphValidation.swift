import Foundation
import GRDB

func validateTabShells(
    _ database: Database,
    workspaceId: UUID,
    shells: [WorkspaceCoreRepository.TabShellRecord]
) throws {
    var seenIds = Set<UUID>()
    for shell in shells {
        guard seenIds.insert(shell.id).inserted else {
            throw WorkspaceCoreRepositoryError.duplicateTabId(shell.id)
        }
        if let colorHex = shell.colorHex {
            try validateTabColorHex(colorHex)
        }
        try validateExistingTabBelongsToWorkspace(database, workspaceId: workspaceId, tabId: shell.id)
    }
}

private func validateTabColorHex(_ colorHex: String) throws {
    guard colorHex.range(of: "^#[0-9A-F]{6}$", options: .regularExpression) != nil else {
        throw WorkspaceCoreRepositoryError.invalidTabColorHex(colorHex)
    }
}

func validateTabShellSetIsUnchanged(
    _ database: Database,
    workspaceId: UUID,
    shells: [WorkspaceCoreRepository.TabShellRecord]
) throws {
    let existingTabIds = Set(try fetchWorkspaceTabIds(database, workspaceId: workspaceId))
    let incomingTabIds = Set(shells.map(\.id))
    guard existingTabIds == incomingTabIds else {
        throw WorkspaceCoreRepositoryError.tabShellSetRequiresGraphReplacement(
            existingTabIds: existingTabIds,
            incomingTabIds: incomingTabIds
        )
    }
}

func validateTabGraph(
    _ database: Database,
    workspaceId: UUID,
    graph: WorkspaceCoreRepository.TabGraphRecord
) throws {
    try validateUniqueTabIds(graph.tabs)
    try validateTabGraphCoversExistingShells(database, workspaceId: workspaceId, tabs: graph.tabs)
    try validatePaneIdsBelongToSingleTab(graph.tabs)
    try validateUniqueArrangementIds(database, workspaceId: workspaceId, graph: graph)

    for tab in graph.tabs {
        try requireTabExists(database, tabId: tab.tabId, workspaceId: workspaceId)
        try validateTabPaneMembership(database, workspaceId: workspaceId, tab: tab)
        try validateTabArrangements(database, workspaceId: workspaceId, tab: tab)
    }
}

private func validateUniqueTabIds(_ tabs: [WorkspaceCoreRepository.TabGraphStateRecord]) throws {
    var seenIds = Set<UUID>()
    for tab in tabs where !seenIds.insert(tab.tabId).inserted {
        throw WorkspaceCoreRepositoryError.duplicateTabId(tab.tabId)
    }
}

private func validateTabGraphCoversExistingShells(
    _ database: Database,
    workspaceId: UUID,
    tabs: [WorkspaceCoreRepository.TabGraphStateRecord]
) throws {
    let existingTabIds = try fetchWorkspaceTabIds(database, workspaceId: workspaceId)
    let incomingTabIds = Set(tabs.map(\.tabId))
    for tabId in existingTabIds where !incomingTabIds.contains(tabId) {
        throw WorkspaceCoreRepositoryError.tabGraphMissingTabState(tabId)
    }
}

private func validatePaneIdsBelongToSingleTab(
    _ tabs: [WorkspaceCoreRepository.TabGraphStateRecord]
) throws {
    var ownerByPaneId: [UUID: UUID] = [:]
    for tab in tabs {
        for paneId in tab.allPaneIds {
            if let ownerTabId = ownerByPaneId[paneId], ownerTabId != tab.tabId {
                throw WorkspaceCoreRepositoryError.duplicateTabPaneId(tabId: tab.tabId, paneId: paneId)
            }
            ownerByPaneId[paneId] = tab.tabId
        }
    }
}

private func validateUniqueArrangementIds(
    _ database: Database,
    workspaceId: UUID,
    graph: WorkspaceCoreRepository.TabGraphRecord
) throws {
    var seenIds = Set<UUID>()
    for arrangement in graph.tabs.flatMap(\.arrangements) {
        guard seenIds.insert(arrangement.id).inserted else {
            throw WorkspaceCoreRepositoryError.duplicateArrangementId(arrangement.id)
        }
        try validateExistingArrangementBelongsToWorkspace(
            database,
            workspaceId: workspaceId,
            arrangementId: arrangement.id
        )
    }
}

private func validateTabPaneMembership(
    _ database: Database,
    workspaceId: UUID,
    tab: WorkspaceCoreRepository.TabGraphStateRecord
) throws {
    var seenPaneIds = Set<UUID>()
    for paneId in tab.allPaneIds {
        guard seenPaneIds.insert(paneId).inserted else {
            throw WorkspaceCoreRepositoryError.duplicateTabPaneId(tabId: tab.tabId, paneId: paneId)
        }
        try requirePaneExists(database, paneId: paneId, workspaceId: workspaceId)
    }
}

private func validateTabArrangements(
    _ database: Database,
    workspaceId: UUID,
    tab: WorkspaceCoreRepository.TabGraphStateRecord
) throws {
    guard !tab.allPaneIds.isEmpty else {
        throw WorkspaceCoreRepositoryError.tabHasNoPanes(tab.tabId)
    }
    let defaultCount = tab.arrangements.filter(\.isDefault).count
    guard defaultCount == 1 else {
        throw WorkspaceCoreRepositoryError.tabHasInvalidDefaultArrangementCount(
            tabId: tab.tabId,
            count: defaultCount
        )
    }
    let defaultArrangement = try requireDefaultArrangement(tab)
    guard !defaultArrangement.layout.isEmpty else {
        throw WorkspaceCoreRepositoryError.defaultArrangementLayoutIsEmpty(
            tabId: tab.tabId,
            arrangementId: defaultArrangement.id
        )
    }
    try validateTabMembershipMatchesArrangementUnion(tab)
    let tabPaneIds = Set(tab.allPaneIds)
    for arrangement in tab.arrangements {
        try validateArrangement(
            database,
            workspaceId: workspaceId,
            tabId: tab.tabId,
            tabPaneIds: tabPaneIds,
            arrangement: arrangement
        )
    }
}

private func requireDefaultArrangement(
    _ tab: WorkspaceCoreRepository.TabGraphStateRecord
) throws -> WorkspaceCoreRepository.TabArrangementGraphRecord {
    guard let defaultArrangement = tab.arrangements.first(where: \.isDefault) else {
        throw WorkspaceCoreRepositoryError.tabHasInvalidDefaultArrangementCount(tabId: tab.tabId, count: 0)
    }
    return defaultArrangement
}

private func validateTabMembershipMatchesArrangementUnion(
    _ tab: WorkspaceCoreRepository.TabGraphStateRecord
) throws {
    let arrangementPaneIds = Set(
        tab.arrangements.flatMap { arrangement in
            arrangement.layout.paneIds + arrangement.drawerViews.flatMap { $0.value.layout.paneIds }
        }
    )
    for paneId in tab.allPaneIds where !arrangementPaneIds.contains(paneId) {
        throw WorkspaceCoreRepositoryError.tabPaneMissingFromArrangements(tabId: tab.tabId, paneId: paneId)
    }
}

private func validateArrangement(
    _ database: Database,
    workspaceId: UUID,
    tabId: UUID,
    tabPaneIds: Set<UUID>,
    arrangement: WorkspaceCoreRepository.TabArrangementGraphRecord
) throws {
    try validateArrangementLayoutRowsAreUnique(arrangementId: arrangement.id, layout: arrangement.layout)
    try validateLayoutPaneIdsBelongToTab(
        tabId: tabId,
        arrangementId: arrangement.id,
        tabPaneIds: tabPaneIds,
        paneIds: arrangement.layout.paneIds
    )
    try validateArrangementLayoutPanePlacements(
        database,
        workspaceId: workspaceId,
        arrangementId: arrangement.id,
        paneIds: arrangement.layout.paneIds
    )
    for paneId in arrangement.minimizedPaneIds {
        guard arrangement.layout.contains(paneId) else {
            throw WorkspaceCoreRepositoryError.arrangementMinimizedPaneMissingFromLayout(
                arrangementId: arrangement.id,
                paneId: paneId
            )
        }
    }
    for (drawerId, drawerView) in arrangement.drawerViews {
        try requireDrawerExists(database, drawerId: drawerId, workspaceId: workspaceId)
        let parentPaneId = try requireDrawerParentPaneId(
            database,
            drawerId: drawerId,
            workspaceId: workspaceId
        )
        guard arrangement.layout.contains(parentPaneId) else {
            throw WorkspaceCoreRepositoryError.drawerViewParentPaneMissingFromLayout(
                arrangementId: arrangement.id,
                drawerId: drawerId,
                parentPaneId: parentPaneId
            )
        }
        try validateDrawerView(
            database,
            context: .init(
                workspaceId: workspaceId,
                tabId: tabId,
                arrangementId: arrangement.id,
                tabPaneIds: tabPaneIds,
                mainLayoutPaneIds: Set(arrangement.layout.paneIds)
            ),
            drawerId: drawerId,
            drawerView: drawerView
        )
    }
}

private func validateArrangementLayoutPanePlacements(
    _ database: Database,
    workspaceId: UUID,
    arrangementId: UUID,
    paneIds: [UUID]
) throws {
    for paneId in paneIds {
        switch try requirePanePlacement(database, paneId: paneId, workspaceId: workspaceId) {
        case .layout:
            continue
        case .drawerChild(let parentPaneId):
            throw WorkspaceCoreRepositoryError.arrangementLayoutPaneUsesDrawerChild(
                arrangementId: arrangementId,
                paneId: paneId,
                parentPaneId: parentPaneId
            )
        }
    }
}

private func requireDrawerParentPaneId(
    _ database: Database,
    drawerId: UUID,
    workspaceId: UUID
) throws -> UUID {
    guard let parentPaneId = try fetchDrawerParentPaneId(database, drawerId: drawerId, workspaceId: workspaceId) else {
        throw WorkspaceCoreRepositoryError.drawerNotFoundInWorkspace(drawerId, workspaceId)
    }
    return parentPaneId
}

private func requirePanePlacement(
    _ database: Database,
    paneId: UUID,
    workspaceId: UUID
) throws -> WorkspaceCoreRepository.PanePlacementRecord {
    guard let placement = try fetchPanePlacement(database, paneId: paneId, workspaceId: workspaceId) else {
        throw WorkspaceCoreRepositoryError.paneNotFoundInWorkspace(paneId, workspaceId)
    }
    return placement
}

private func validateArrangementLayoutRowsAreUnique(arrangementId: UUID, layout: Layout) throws {
    var seenPaneIds = Set<UUID>()
    for paneId in layout.paneIds where !seenPaneIds.insert(paneId).inserted {
        throw WorkspaceCoreRepositoryError.arrangementLayoutPaneListedMultipleTimes(
            arrangementId: arrangementId,
            paneId: paneId
        )
    }
    try validateLayoutDividerIdsAreUnique(arrangementId: arrangementId, layout: layout)
}

private func validateLayoutDividerIdsAreUnique(arrangementId: UUID, layout: Layout) throws {
    var seenDividerIds = Set<UUID>()
    for dividerId in layout.dividerIds where !seenDividerIds.insert(dividerId).inserted {
        throw WorkspaceCoreRepositoryError.layoutDividerListedMultipleTimes(
            arrangementId: arrangementId,
            dividerId: dividerId
        )
    }
}

func validateLayoutPaneIdsBelongToTab(
    tabId: UUID,
    arrangementId: UUID,
    tabPaneIds: Set<UUID>,
    paneIds: [UUID]
) throws {
    for paneId in paneIds where !tabPaneIds.contains(paneId) {
        throw WorkspaceCoreRepositoryError.arrangementPaneMissingFromTab(
            tabId: tabId,
            arrangementId: arrangementId,
            paneId: paneId
        )
    }
}

private func validateExistingTabBelongsToWorkspace(
    _ database: Database,
    workspaceId: UUID,
    tabId: UUID
) throws {
    guard
        let actualWorkspaceId = try fetchTabWorkspaceId(database, tabId: tabId),
        actualWorkspaceId != workspaceId
    else {
        return
    }
    throw WorkspaceCoreRepositoryError.tabBelongsToDifferentWorkspace(
        tabId: tabId,
        expectedWorkspaceId: workspaceId,
        actualWorkspaceId: actualWorkspaceId
    )
}

private func validateExistingArrangementBelongsToWorkspace(
    _ database: Database,
    workspaceId: UUID,
    arrangementId: UUID
) throws {
    guard
        let actualWorkspaceId = try fetchArrangementWorkspaceId(database, arrangementId: arrangementId),
        actualWorkspaceId != workspaceId
    else {
        return
    }
    throw WorkspaceCoreRepositoryError.arrangementBelongsToDifferentWorkspace(
        arrangementId: arrangementId,
        expectedWorkspaceId: workspaceId,
        actualWorkspaceId: actualWorkspaceId
    )
}

private func requireTabExists(_ database: Database, tabId: UUID, workspaceId: UUID) throws {
    guard let actualWorkspaceId = try fetchTabWorkspaceId(database, tabId: tabId) else {
        throw WorkspaceCoreRepositoryError.tabNotFoundInWorkspace(tabId, workspaceId)
    }
    guard actualWorkspaceId == workspaceId else {
        throw WorkspaceCoreRepositoryError.tabBelongsToDifferentWorkspace(
            tabId: tabId,
            expectedWorkspaceId: workspaceId,
            actualWorkspaceId: actualWorkspaceId
        )
    }
}

private func requirePaneExists(_ database: Database, paneId: UUID, workspaceId: UUID) throws {
    guard let actualWorkspaceId = try fetchPaneWorkspaceId(database, paneId: paneId) else {
        throw WorkspaceCoreRepositoryError.paneNotFoundInWorkspace(paneId, workspaceId)
    }
    guard actualWorkspaceId == workspaceId else {
        throw WorkspaceCoreRepositoryError.paneBelongsToDifferentWorkspace(
            paneId: paneId,
            expectedWorkspaceId: workspaceId,
            actualWorkspaceId: actualWorkspaceId
        )
    }
}

private func requireDrawerExists(_ database: Database, drawerId: UUID, workspaceId: UUID) throws {
    guard let actualWorkspaceId = try fetchDrawerWorkspaceId(database, drawerId: drawerId) else {
        throw WorkspaceCoreRepositoryError.drawerNotFoundInWorkspace(drawerId, workspaceId)
    }
    guard actualWorkspaceId == workspaceId else {
        throw WorkspaceCoreRepositoryError.drawerBelongsToDifferentWorkspace(
            drawerId: drawerId,
            expectedWorkspaceId: workspaceId,
            actualWorkspaceId: actualWorkspaceId
        )
    }
}

private func fetchTabWorkspaceId(_ database: Database, tabId: UUID) throws -> UUID? {
    guard
        let workspaceIdString = try String.fetchOne(
            database,
            sql: """
                SELECT workspace_id
                FROM tab_shell
                WHERE id = ?
                """,
            arguments: [tabId.uuidString]
        )
    else {
        return nil
    }
    return try decodeWorkspaceId(workspaceIdString)
}

private func fetchWorkspaceTabIds(_ database: Database, workspaceId: UUID) throws -> [UUID] {
    let rows = try Row.fetchAll(
        database,
        sql: """
            SELECT id
            FROM tab_shell
            WHERE workspace_id = ?
            ORDER BY sort_index ASC
            """,
        arguments: [workspaceId.uuidString]
    )
    return try rows.map { row in try decodeTabId(row["id"]) }
}

private func fetchArrangementWorkspaceId(_ database: Database, arrangementId: UUID) throws -> UUID? {
    guard
        let workspaceIdString = try String.fetchOne(
            database,
            sql: """
                SELECT tab_shell.workspace_id
                FROM tab_arrangement
                JOIN tab_shell ON tab_shell.id = tab_arrangement.tab_id
                WHERE tab_arrangement.id = ?
                """,
            arguments: [arrangementId.uuidString]
        )
    else {
        return nil
    }
    return try decodeWorkspaceId(workspaceIdString)
}

private func fetchPaneWorkspaceId(_ database: Database, paneId: UUID) throws -> UUID? {
    guard
        let workspaceIdString = try String.fetchOne(
            database,
            sql: """
                SELECT workspace_id
                FROM pane
                WHERE id = ?
                """,
            arguments: [paneId.uuidString]
        )
    else {
        return nil
    }
    return try decodeWorkspaceId(workspaceIdString)
}

private func fetchPanePlacement(
    _ database: Database,
    paneId: UUID,
    workspaceId: UUID
) throws -> WorkspaceCoreRepository.PanePlacementRecord? {
    guard
        let row = try Row.fetchOne(
            database,
            sql: """
                SELECT kind, parent_pane_id
                FROM pane
                WHERE id = ?
                AND workspace_id = ?
                """,
            arguments: [paneId.uuidString, workspaceId.uuidString]
        )
    else {
        return nil
    }
    return try decodePanePlacement(row)
}

private func fetchDrawerWorkspaceId(_ database: Database, drawerId: UUID) throws -> UUID? {
    guard
        let workspaceIdString = try String.fetchOne(
            database,
            sql: """
                SELECT pane.workspace_id
                FROM drawer
                JOIN pane ON pane.id = drawer.parent_pane_id
                WHERE drawer.id = ?
                """,
            arguments: [drawerId.uuidString]
        )
    else {
        return nil
    }
    return try decodeWorkspaceId(workspaceIdString)
}

private func fetchDrawerParentPaneId(_ database: Database, drawerId: UUID, workspaceId: UUID) throws -> UUID? {
    guard
        let paneIdString = try String.fetchOne(
            database,
            sql: """
                SELECT drawer.parent_pane_id
                FROM drawer
                JOIN pane ON pane.id = drawer.parent_pane_id
                WHERE drawer.id = ?
                AND pane.workspace_id = ?
                """,
            arguments: [drawerId.uuidString, workspaceId.uuidString]
        )
    else {
        return nil
    }
    return try decodePaneId(paneIdString)
}

private func decodeWorkspaceId(_ value: String) throws -> UUID {
    guard let id = UUID(uuidString: value) else {
        throw WorkspaceCoreRepositoryError.malformedWorkspaceId(value)
    }
    return id
}
