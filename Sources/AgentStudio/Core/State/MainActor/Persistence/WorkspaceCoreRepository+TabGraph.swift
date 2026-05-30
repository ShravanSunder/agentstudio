import Foundation
import GRDB

extension WorkspaceCoreRepository {
    struct TabShellRecord: Equatable {
        let id: UUID
        var name: String
    }

    struct TabGraphRecord: Equatable {
        var tabs: [TabGraphStateRecord]
    }

    struct TabGraphStateRecord: Equatable {
        let tabId: UUID
        var allPaneIds: [UUID]
        var arrangements: [TabArrangementGraphRecord]
    }

    struct TabArrangementGraphRecord: Equatable {
        let id: UUID
        var name: String
        var isDefault: Bool
        var layout: Layout
        var minimizedPaneIds: Set<UUID>
        var showsMinimizedPanes: Bool
        var drawerViews: [UUID: DrawerViewGraphRecord]
    }

    struct DrawerViewGraphRecord: Equatable {
        var layout: DrawerGridLayout
        var minimizedPaneIds: Set<UUID>
    }

    func replaceTabShells(workspaceId: UUID, shells: [TabShellRecord]) throws {
        try databaseWriter.write { database in
            try requireWorkspaceExists(database, id: workspaceId)
            try validateTabShells(database, workspaceId: workspaceId, shells: shells)
            try validateTabShellSetIsUnchanged(database, workspaceId: workspaceId, shells: shells)
            try replaceTabShellRows(database, workspaceId: workspaceId, shells: shells)
        }
    }

    func replaceTabShellsAndGraph(
        workspaceId: UUID,
        shells: [TabShellRecord],
        graph: TabGraphRecord
    ) throws {
        try databaseWriter.write { database in
            try requireWorkspaceExists(database, id: workspaceId)
            try validateTabShells(database, workspaceId: workspaceId, shells: shells)
            try replaceTabShellRows(database, workspaceId: workspaceId, shells: shells)
            try validateTabGraph(database, workspaceId: workspaceId, graph: graph)
            try replaceTabGraphRows(database, workspaceId: workspaceId, graph: graph)
        }
    }

    func fetchTabShells(workspaceId: UUID) throws -> [TabShellRecord] {
        try databaseWriter.read { database in
            try requireWorkspaceExists(database, id: workspaceId)
            let rows = try Row.fetchAll(
                database,
                sql: """
                    SELECT id, name
                    FROM tab_shell
                    WHERE workspace_id = ?
                    ORDER BY sort_index ASC
                    """,
                arguments: [workspaceId.uuidString]
            )
            return try rows.map(decodeTabShellRecord)
        }
    }

    func replaceTabGraph(workspaceId: UUID, graph: TabGraphRecord) throws {
        try databaseWriter.write { database in
            try requireWorkspaceExists(database, id: workspaceId)
            try validateTabGraph(database, workspaceId: workspaceId, graph: graph)
            try replaceTabGraphRows(database, workspaceId: workspaceId, graph: graph)
        }
    }

    func fetchTabGraph(workspaceId: UUID) throws -> TabGraphRecord {
        try databaseWriter.read { database in
            try requireWorkspaceExists(database, id: workspaceId)
            let tabRows = try Row.fetchAll(
                database,
                sql: """
                    SELECT id
                    FROM tab_shell
                    WHERE workspace_id = ?
                    ORDER BY sort_index ASC
                    """,
                arguments: [workspaceId.uuidString]
            )
            let tabs = try tabRows.map { row in
                let tabId = try decodeTabId(row["id"])
                return try decodeTabGraphState(database, tabId: tabId)
            }
            let graph = TabGraphRecord(tabs: tabs)
            try validateTabGraph(database, workspaceId: workspaceId, graph: graph)
            return graph
        }
    }
}

private func decodeTabShellRecord(_ row: Row) throws -> WorkspaceCoreRepository.TabShellRecord {
    let id = try decodeTabId(row["id"])
    let name: String = row["name"]
    return .init(id: id, name: name)
}

private func decodeTabGraphState(
    _ database: Database,
    tabId: UUID
) throws -> WorkspaceCoreRepository.TabGraphStateRecord {
    let allPaneIds = try fetchTabPaneIds(database, tabId: tabId)
    let arrangementRows = try Row.fetchAll(
        database,
        sql: """
            SELECT id, name, is_default, shows_minimized_panes
            FROM tab_arrangement
            WHERE tab_id = ?
            ORDER BY sort_index ASC
            """,
        arguments: [tabId.uuidString]
    )
    let arrangements = try arrangementRows.map { row in
        try decodeTabArrangementGraphRecord(database, row: row)
    }
    return .init(tabId: tabId, allPaneIds: allPaneIds, arrangements: arrangements)
}

private func decodeTabArrangementGraphRecord(
    _ database: Database,
    row: Row
) throws -> WorkspaceCoreRepository.TabArrangementGraphRecord {
    let arrangementId = try decodeArrangementId(row["id"])
    let name: String = row["name"]
    let isDefault: Int = row["is_default"]
    let showsMinimizedPanes: Int = row["shows_minimized_panes"]
    let layout = try fetchArrangementLayout(database, arrangementId: arrangementId)
    let minimizedPaneIds = try fetchArrangementMinimizedPaneIds(database, arrangementId: arrangementId)
    let drawerViews = try fetchDrawerViewGraphRecords(database, arrangementId: arrangementId)
    return .init(
        id: arrangementId,
        name: name,
        isDefault: isDefault == 1,
        layout: layout,
        minimizedPaneIds: minimizedPaneIds,
        showsMinimizedPanes: showsMinimizedPanes == 1,
        drawerViews: drawerViews
    )
}

private func fetchTabPaneIds(_ database: Database, tabId: UUID) throws -> [UUID] {
    let rows = try Row.fetchAll(
        database,
        sql: """
            SELECT pane_id
            FROM tab_pane
            WHERE tab_id = ?
            ORDER BY sort_index ASC
            """,
        arguments: [tabId.uuidString]
    )
    return try rows.map { row in try decodePaneId(row["pane_id"]) }
}

private func fetchArrangementLayout(_ database: Database, arrangementId: UUID) throws -> Layout {
    let paneRows = try fetchLayoutPaneRows(
        database,
        sql: """
            SELECT pane_id, ratio, sort_index
            FROM arrangement_layout_pane
            WHERE arrangement_id = ?
            ORDER BY sort_index ASC
            """,
        arguments: [arrangementId.uuidString]
    )
    let dividerRows = try fetchLayoutDividerRows(
        database,
        sql: """
            SELECT divider_id, sort_index
            FROM arrangement_layout_divider
            WHERE arrangement_id = ?
            ORDER BY sort_index ASC
            """,
        arguments: [arrangementId.uuidString]
    )
    return try makeLayout(paneRows: paneRows, dividerRows: dividerRows)
}

private func fetchArrangementMinimizedPaneIds(_ database: Database, arrangementId: UUID) throws -> Set<UUID> {
    let rows = try Row.fetchAll(
        database,
        sql: """
            SELECT pane_id
            FROM arrangement_minimized_pane
            WHERE arrangement_id = ?
            """,
        arguments: [arrangementId.uuidString]
    )
    return Set(try rows.map { row in try decodePaneId(row["pane_id"]) })
}

private func fetchDrawerViewGraphRecords(
    _ database: Database,
    arrangementId: UUID
) throws -> [UUID: WorkspaceCoreRepository.DrawerViewGraphRecord] {
    let rows = try Row.fetchAll(
        database,
        sql: """
            SELECT drawer_id, row_split_ratio
            FROM arrangement_drawer_view
            WHERE arrangement_id = ?
            ORDER BY drawer_id ASC
            """,
        arguments: [arrangementId.uuidString]
    )
    let pairs = try rows.map { row -> (UUID, WorkspaceCoreRepository.DrawerViewGraphRecord) in
        let drawerId = try decodeDrawerId(row["drawer_id"])
        let rowSplitRatio: Double = row["row_split_ratio"]
        let layout = try fetchDrawerGridLayout(
            database,
            arrangementId: arrangementId,
            drawerId: drawerId,
            rowSplitRatio: rowSplitRatio
        )
        let minimizedPaneIds = try fetchDrawerViewMinimizedPaneIds(
            database,
            arrangementId: arrangementId,
            drawerId: drawerId
        )
        return (drawerId, .init(layout: layout, minimizedPaneIds: minimizedPaneIds))
    }
    return Dictionary(uniqueKeysWithValues: pairs)
}

private func fetchDrawerGridLayout(
    _ database: Database,
    arrangementId: UUID,
    drawerId: UUID,
    rowSplitRatio: Double
) throws -> DrawerGridLayout {
    try validateDrawerViewRowKinds(database, arrangementId: arrangementId, drawerId: drawerId)
    let topRow = try fetchDrawerViewLayoutRow(
        database,
        arrangementId: arrangementId,
        drawerId: drawerId,
        rowKind: SQLiteTabGraphStorage.topRow
    )
    let bottomRow = try fetchDrawerViewLayoutRow(
        database,
        arrangementId: arrangementId,
        drawerId: drawerId,
        rowKind: SQLiteTabGraphStorage.bottomRow
    )
    return DrawerGridLayout(
        topRow: topRow,
        bottomRow: bottomRow.isEmpty ? nil : bottomRow,
        rowSplitRatio: rowSplitRatio
    )
}

private func validateDrawerViewRowKinds(
    _ database: Database,
    arrangementId: UUID,
    drawerId: UUID
) throws {
    let rows = try Row.fetchAll(
        database,
        sql: """
            SELECT row_kind
            FROM drawer_view_layout_pane
            WHERE arrangement_id = ?
            AND drawer_id = ?
            UNION
            SELECT row_kind
            FROM drawer_view_layout_divider
            WHERE arrangement_id = ?
            AND drawer_id = ?
            """,
        arguments: [
            arrangementId.uuidString,
            drawerId.uuidString,
            arrangementId.uuidString,
            drawerId.uuidString,
        ]
    )
    let rowKinds = Set(rows.map { row -> String in row["row_kind"] })
    let allowedRowKinds: Set<String> = [SQLiteTabGraphStorage.topRow, SQLiteTabGraphStorage.bottomRow]
    guard rowKinds.contains(SQLiteTabGraphStorage.topRow), rowKinds.isSubset(of: allowedRowKinds) else {
        throw WorkspaceCoreRepositoryError.malformedLayout(
            "drawer view layout row_kind must be top or bottom with a top row present"
        )
    }
}

private func fetchDrawerViewLayoutRow(
    _ database: Database,
    arrangementId: UUID,
    drawerId: UUID,
    rowKind: String
) throws -> Layout {
    let arguments: StatementArguments = [arrangementId.uuidString, drawerId.uuidString, rowKind]
    let paneRows = try fetchLayoutPaneRows(
        database,
        sql: """
            SELECT pane_id, ratio, sort_index
            FROM drawer_view_layout_pane
            WHERE arrangement_id = ?
            AND drawer_id = ?
            AND row_kind = ?
            ORDER BY sort_index ASC
            """,
        arguments: arguments
    )
    let dividerRows = try fetchLayoutDividerRows(
        database,
        sql: """
            SELECT divider_id, sort_index
            FROM drawer_view_layout_divider
            WHERE arrangement_id = ?
            AND drawer_id = ?
            AND row_kind = ?
            ORDER BY sort_index ASC
            """,
        arguments: arguments
    )
    return try makeLayout(paneRows: paneRows, dividerRows: dividerRows)
}

private func fetchDrawerViewMinimizedPaneIds(
    _ database: Database,
    arrangementId: UUID,
    drawerId: UUID
) throws -> Set<UUID> {
    let rows = try Row.fetchAll(
        database,
        sql: """
            SELECT pane_id
            FROM drawer_view_minimized_pane
            WHERE arrangement_id = ?
            AND drawer_id = ?
            """,
        arguments: [arrangementId.uuidString, drawerId.uuidString]
    )
    return Set(try rows.map { row in try decodePaneId(row["pane_id"]) })
}

private func fetchLayoutPaneRows(
    _ database: Database,
    sql: String,
    arguments: StatementArguments
) throws -> [SQLiteTabGraphLayoutRow] {
    let rows = try Row.fetchAll(database, sql: sql, arguments: arguments)
    return try rows.map { row in
        try .init(
            paneId: decodePaneId(row["pane_id"]),
            ratio: row["ratio"],
            sortIndex: row["sort_index"]
        )
    }
}

private func fetchLayoutDividerRows(
    _ database: Database,
    sql: String,
    arguments: StatementArguments
) throws -> [SQLiteTabGraphDividerRow] {
    let rows = try Row.fetchAll(database, sql: sql, arguments: arguments)
    return try rows.map { row in
        try .init(
            dividerId: decodeGenericUUID(
                row["divider_id"],
                malformedError: WorkspaceCoreRepositoryError.malformedLayout
            ),
            sortIndex: row["sort_index"]
        )
    }
}

private func makeLayout(
    paneRows: [SQLiteTabGraphLayoutRow],
    dividerRows: [SQLiteTabGraphDividerRow]
) throws -> Layout {
    guard dividerRows.count == max(paneRows.count - 1, 0) else {
        throw WorkspaceCoreRepositoryError.malformedLayout("layout divider count must equal pane count minus one")
    }
    return Layout(
        panes: paneRows.map { .init(paneId: $0.paneId, ratio: $0.ratio) },
        dividerIds: dividerRows.map(\.dividerId)
    )
}

func decodeTabId(_ value: String) throws -> UUID {
    try decodeGenericUUID(value, malformedError: WorkspaceCoreRepositoryError.malformedTabId)
}

func decodeArrangementId(_ value: String) throws -> UUID {
    try decodeGenericUUID(value, malformedError: WorkspaceCoreRepositoryError.malformedArrangementId)
}

func decodePaneId(_ value: String) throws -> UUID {
    try decodeGenericUUID(value, malformedError: WorkspaceCoreRepositoryError.malformedPaneId)
}

func decodeDrawerId(_ value: String) throws -> UUID {
    try decodeGenericUUID(value, malformedError: WorkspaceCoreRepositoryError.malformedDrawerId)
}

private func decodeGenericUUID(
    _ value: String,
    malformedError: (String) -> WorkspaceCoreRepositoryError
) throws -> UUID {
    guard let id = UUID(uuidString: value) else {
        throw malformedError(value)
    }
    return id
}
