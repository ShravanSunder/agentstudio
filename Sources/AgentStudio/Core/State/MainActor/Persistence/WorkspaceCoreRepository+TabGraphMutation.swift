import Foundation
import GRDB

func replaceTabShellRows(
    _ database: Database,
    workspaceId: UUID,
    shells: [WorkspaceCoreRepository.TabShellRecord]
) throws {
    let retainedIds = Set(shells.map(\.id))
    try deleteTabShellRowsNotIn(database, workspaceId: workspaceId, tabIds: retainedIds)
    try stageTabShellSortIndexes(database, workspaceId: workspaceId)
    for (index, shell) in shells.enumerated() {
        try upsertTabShell(database, workspaceId: workspaceId, shell: shell, sortIndex: index)
    }
}

func replaceTabGraphRows(
    _ database: Database,
    workspaceId: UUID,
    graph: WorkspaceCoreRepository.TabGraphRecord
) throws {
    try deleteTabGraphRows(database, workspaceId: workspaceId)
    for tab in graph.tabs {
        try insertTabPaneRows(database, tab: tab)
        try insertArrangementRows(database, tab: tab)
    }
}

private func deleteTabShellRowsNotIn(_ database: Database, workspaceId: UUID, tabIds: Set<UUID>) throws {
    if tabIds.isEmpty {
        try database.execute(
            sql: """
                DELETE FROM tab_shell
                WHERE workspace_id = ?
                """,
            arguments: [workspaceId.uuidString]
        )
        return
    }

    try database.execute(
        sql: """
            DELETE FROM tab_shell
            WHERE workspace_id = ?
            AND id NOT IN (\(SQLiteTabGraphStorage.placeholders(count: tabIds.count)))
            """,
        arguments: StatementArguments([workspaceId.uuidString] + SQLiteTabGraphStorage.sortedUUIDStrings(tabIds))
    )
}

private func stageTabShellSortIndexes(_ database: Database, workspaceId: UUID) throws {
    try database.execute(
        sql: """
            UPDATE tab_shell
            SET sort_index = -rowid - 1
            WHERE workspace_id = ?
            """,
        arguments: [workspaceId.uuidString]
    )
}

private func upsertTabShell(
    _ database: Database,
    workspaceId: UUID,
    shell: WorkspaceCoreRepository.TabShellRecord,
    sortIndex: Int
) throws {
    try database.execute(
        sql: """
            INSERT INTO tab_shell(id, workspace_id, name, color_hex, sort_index)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                color_hex = excluded.color_hex,
                sort_index = excluded.sort_index
            """,
        arguments: [shell.id.uuidString, workspaceId.uuidString, shell.name, shell.colorHex, sortIndex]
    )
}

private func deleteTabGraphRows(_ database: Database, workspaceId: UUID) throws {
    try database.execute(
        sql: """
            DELETE FROM tab_arrangement
            WHERE tab_id IN (
                SELECT id
                FROM tab_shell
                WHERE workspace_id = ?
            )
            """,
        arguments: [workspaceId.uuidString]
    )
    try database.execute(
        sql: """
            DELETE FROM tab_pane
            WHERE tab_id IN (
                SELECT id
                FROM tab_shell
                WHERE workspace_id = ?
            )
            """,
        arguments: [workspaceId.uuidString]
    )
}

private func insertTabPaneRows(
    _ database: Database,
    tab: WorkspaceCoreRepository.TabGraphStateRecord
) throws {
    for (index, paneId) in tab.allPaneIds.enumerated() {
        try database.execute(
            sql: """
                INSERT INTO tab_pane(tab_id, pane_id, sort_index)
                VALUES (?, ?, ?)
                """,
            arguments: [tab.tabId.uuidString, paneId.uuidString, index]
        )
    }
}

private func insertArrangementRows(
    _ database: Database,
    tab: WorkspaceCoreRepository.TabGraphStateRecord
) throws {
    for (index, arrangement) in tab.arrangements.enumerated() {
        try insertArrangement(database, tabId: tab.tabId, arrangement: arrangement, sortIndex: index)
        try insertArrangementLayout(database, arrangement: arrangement)
        try insertArrangementMinimizedPanes(database, arrangement: arrangement)
        try insertArrangementDrawerViews(database, arrangement: arrangement)
    }
}

private func insertArrangement(
    _ database: Database,
    tabId: UUID,
    arrangement: WorkspaceCoreRepository.TabArrangementGraphRecord,
    sortIndex: Int
) throws {
    try database.execute(
        sql: """
            INSERT INTO tab_arrangement(
                id, tab_id, name, is_default, shows_minimized_panes, sort_index
            )
            VALUES (?, ?, ?, ?, ?, ?)
            """,
        arguments: [
            arrangement.id.uuidString,
            tabId.uuidString,
            arrangement.name,
            arrangement.isDefault ? 1 : 0,
            arrangement.showsMinimizedPanes ? 1 : 0,
            sortIndex,
        ]
    )
}

private func insertArrangementLayout(
    _ database: Database,
    arrangement: WorkspaceCoreRepository.TabArrangementGraphRecord
) throws {
    try insertLayout(
        database,
        paneTable: "arrangement_layout_pane",
        dividerTable: "arrangement_layout_divider",
        ownerColumns: ["arrangement_id"],
        ownerValues: [arrangement.id.uuidString],
        layout: arrangement.layout
    )
}

private func insertArrangementMinimizedPanes(
    _ database: Database,
    arrangement: WorkspaceCoreRepository.TabArrangementGraphRecord
) throws {
    for paneId in arrangement.minimizedPaneIds.sorted(by: { $0.uuidString < $1.uuidString }) {
        try database.execute(
            sql: """
                INSERT INTO arrangement_minimized_pane(arrangement_id, pane_id)
                VALUES (?, ?)
                """,
            arguments: [arrangement.id.uuidString, paneId.uuidString]
        )
    }
}

private func insertArrangementDrawerViews(
    _ database: Database,
    arrangement: WorkspaceCoreRepository.TabArrangementGraphRecord
) throws {
    for drawerId in arrangement.drawerViews.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
        guard let drawerView = arrangement.drawerViews[drawerId] else { continue }
        try database.execute(
            sql: """
                INSERT INTO arrangement_drawer_view(arrangement_id, drawer_id, row_split_ratio)
                VALUES (?, ?, ?)
                """,
            arguments: [arrangement.id.uuidString, drawerId.uuidString, drawerView.layout.rowSplitRatio]
        )
        try insertDrawerGridLayout(
            database,
            arrangementId: arrangement.id,
            drawerId: drawerId,
            layout: drawerView.layout
        )
        try insertDrawerViewMinimizedPanes(
            database,
            arrangementId: arrangement.id,
            drawerId: drawerId,
            minimizedPaneIds: drawerView.minimizedPaneIds
        )
    }
}

private func insertDrawerGridLayout(
    _ database: Database,
    arrangementId: UUID,
    drawerId: UUID,
    layout: DrawerGridLayout
) throws {
    try insertDrawerLayoutRow(
        database,
        arrangementId: arrangementId,
        drawerId: drawerId,
        rowKind: SQLiteTabGraphStorage.topRow,
        layout: layout.topRow
    )
    if let bottomRow = layout.bottomRow {
        try insertDrawerLayoutRow(
            database,
            arrangementId: arrangementId,
            drawerId: drawerId,
            rowKind: SQLiteTabGraphStorage.bottomRow,
            layout: bottomRow
        )
    }
}

private func insertDrawerLayoutRow(
    _ database: Database,
    arrangementId: UUID,
    drawerId: UUID,
    rowKind: String,
    layout: Layout
) throws {
    try insertLayout(
        database,
        paneTable: "drawer_view_layout_pane",
        dividerTable: "drawer_view_layout_divider",
        ownerColumns: ["arrangement_id", "drawer_id", "row_kind"],
        ownerValues: [arrangementId.uuidString, drawerId.uuidString, rowKind],
        layout: layout
    )
}

private func insertDrawerViewMinimizedPanes(
    _ database: Database,
    arrangementId: UUID,
    drawerId: UUID,
    minimizedPaneIds: Set<UUID>
) throws {
    for paneId in minimizedPaneIds.sorted(by: { $0.uuidString < $1.uuidString }) {
        try database.execute(
            sql: """
                INSERT INTO drawer_view_minimized_pane(arrangement_id, drawer_id, pane_id)
                VALUES (?, ?, ?)
                """,
            arguments: [arrangementId.uuidString, drawerId.uuidString, paneId.uuidString]
        )
    }
}

private func insertLayout(
    _ database: Database,
    paneTable: String,
    dividerTable: String,
    ownerColumns: [String],
    ownerValues: [String],
    layout: Layout
) throws {
    let ownerColumnList = ownerColumns.joined(separator: ", ")
    let ownerPlaceholders = SQLiteTabGraphStorage.placeholders(count: ownerColumns.count)
    for (index, pane) in layout.panes.enumerated() {
        try database.execute(
            sql: """
                INSERT INTO \(paneTable)(\(ownerColumnList), pane_id, sort_index, ratio)
                VALUES (\(ownerPlaceholders), ?, ?, ?)
                """,
            arguments: tabGraphStatementArguments(
                ownerValues: ownerValues,
                additionalValues: [pane.paneId.uuidString, index, pane.ratio]
            )
        )
    }
    for (index, dividerId) in layout.dividerIds.enumerated() {
        try database.execute(
            sql: """
                INSERT INTO \(dividerTable)(\(ownerColumnList), divider_id, sort_index)
                VALUES (\(ownerPlaceholders), ?, ?)
                """,
            arguments: tabGraphStatementArguments(
                ownerValues: ownerValues,
                additionalValues: [dividerId.uuidString, index]
            )
        )
    }
}

private func tabGraphStatementArguments(
    ownerValues: [String],
    additionalValues: [(any DatabaseValueConvertible)?]
) -> StatementArguments {
    var values: [(any DatabaseValueConvertible)?] = ownerValues.map { $0 }
    values.append(contentsOf: additionalValues)
    return StatementArguments(values)
}
