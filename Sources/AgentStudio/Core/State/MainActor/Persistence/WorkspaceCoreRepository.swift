import Foundation
import GRDB

struct WorkspaceCoreRepository {
    struct WorkspaceRecord: Equatable {
        let id: UUID
        var name: String
        let createdAt: Date
        let updatedAt: Date
    }

    struct LegacyImportStatusRecord: Equatable {
        let workspaceId: UUID
        var sourceStatePath: String
        var coreImportedAt: Date?
        var settingsImportedAt: Date?
        var localImportedAt: Date?
        var cacheImportedAt: Date?
        var archivedAt: Date?
        var lastError: String?
    }

    private struct WorkspaceSnapshotReplacement {
        var workspace: WorkspaceRecord
        var topology: RepositoryTopologyRecord
        var paneGraph: PaneGraphRecord
        var tabShells: [TabShellRecord]
        var tabGraph: TabGraphRecord
        var stagedAt: Date
        var completedAt: Date?
        var updatesActiveSelection: Bool
    }

    let databaseWriter: any DatabaseWriter

    func migrate() throws {
        try WorkspaceCoreMigrations.migrate(databaseWriter)
    }

    func upsertWorkspace(_ record: WorkspaceRecord) throws {
        try databaseWriter.write { database in
            try database.execute(
                sql: """
                    INSERT INTO workspace(id, name, created_at, updated_at)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name,
                        updated_at = excluded.updated_at
                    """,
                arguments: [
                    record.id.uuidString,
                    record.name,
                    record.createdAt.timeIntervalSince1970,
                    record.updatedAt.timeIntervalSince1970,
                ]
            )
        }
    }

    func fetchWorkspace(id: UUID) throws -> WorkspaceRecord? {
        try databaseWriter.read { database in
            guard
                let row = try Row.fetchOne(
                    database,
                    sql: """
                        SELECT id, name, created_at, updated_at
                        FROM workspace
                        WHERE id = ?
                        """,
                    arguments: [id.uuidString]
                )
            else {
                return nil
            }
            return try decodeWorkspaceRecord(row)
        }
    }

    func fetchWorkspaces() throws -> [WorkspaceRecord] {
        try databaseWriter.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                    SELECT id, name, created_at, updated_at
                    FROM workspace
                    ORDER BY updated_at DESC, id ASC
                    """
            )
            return try rows.map(decodeWorkspaceRecord)
        }
    }

    func renameWorkspace(_ workspaceId: UUID, name: String, updatedAt: Date) throws {
        try databaseWriter.write { database in
            try requireWorkspaceExists(database, id: workspaceId)
            try database.execute(
                sql: """
                    UPDATE workspace
                    SET name = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [
                    name,
                    updatedAt.timeIntervalSince1970,
                    workspaceId.uuidString,
                ]
            )
        }
    }

    func selectActiveWorkspace(_ workspaceId: UUID, updatedAt: Date) throws {
        try databaseWriter.write { database in
            try requireWorkspaceExists(database, id: workspaceId)
            try updateActiveWorkspaceSelection(
                database,
                workspaceId: workspaceId.uuidString,
                updatedAt: updatedAt
            )
        }
    }

    func fetchActiveWorkspaceId() throws -> UUID? {
        try databaseWriter.read { database in
            try fetchActiveWorkspaceIdFromDatabase(database)
        }
    }

    func replaceWorkspaceSnapshot(
        workspace: WorkspaceRecord,
        topology: RepositoryTopologyRecord,
        paneGraph: PaneGraphRecord,
        tabShells: [TabShellRecord],
        tabGraph: TabGraphRecord,
        completedAt: Date,
        updatesActiveSelection: Bool = true
    ) throws {
        try replaceWorkspaceSnapshot(
            .init(
                workspace: workspace,
                topology: topology,
                paneGraph: paneGraph,
                tabShells: tabShells,
                tabGraph: tabGraph,
                stagedAt: completedAt,
                completedAt: completedAt,
                updatesActiveSelection: updatesActiveSelection
            )
        )
    }

    func replaceWorkspaceSnapshotStaged(
        workspace: WorkspaceRecord,
        topology: RepositoryTopologyRecord,
        paneGraph: PaneGraphRecord,
        tabShells: [TabShellRecord],
        tabGraph: TabGraphRecord,
        stagedAt: Date,
        updatesActiveSelection: Bool = true
    ) throws {
        try replaceWorkspaceSnapshot(
            .init(
                workspace: workspace,
                topology: topology,
                paneGraph: paneGraph,
                tabShells: tabShells,
                tabGraph: tabGraph,
                stagedAt: stagedAt,
                completedAt: nil,
                updatesActiveSelection: updatesActiveSelection
            )
        )
    }

    private func replaceWorkspaceSnapshot(_ replacement: WorkspaceSnapshotReplacement) throws {
        try databaseWriter.write { database in
            try database.execute(
                sql: """
                    INSERT INTO workspace(id, name, created_at, updated_at)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name,
                        updated_at = excluded.updated_at
                    """,
                arguments: [
                    replacement.workspace.id.uuidString,
                    replacement.workspace.name,
                    replacement.workspace.createdAt.timeIntervalSince1970,
                    replacement.workspace.updatedAt.timeIntervalSince1970,
                ]
            )
            if replacement.updatesActiveSelection {
                try updateActiveWorkspaceSelection(
                    database,
                    workspaceId: replacement.workspace.id.uuidString,
                    updatedAt: replacement.workspace.updatedAt
                )
            }
            try validateTopology(replacement.topology, for: replacement.workspace.id)
            try replaceRepositoryTopologyRows(
                database,
                workspaceId: replacement.workspace.id,
                topology: replacement.topology
            )
            try validatePaneGraph(database, workspaceId: replacement.workspace.id, graph: replacement.paneGraph)
            try replacePaneGraphRows(database, workspaceId: replacement.workspace.id, graph: replacement.paneGraph)
            try validateTabShells(database, workspaceId: replacement.workspace.id, shells: replacement.tabShells)
            try replaceTabShellRows(database, workspaceId: replacement.workspace.id, shells: replacement.tabShells)
            try validateTabGraph(database, workspaceId: replacement.workspace.id, graph: replacement.tabGraph)
            try replaceTabGraphRows(database, workspaceId: replacement.workspace.id, graph: replacement.tabGraph)
            try database.execute(
                sql: """
                    INSERT INTO workspace_sqlite_snapshot_status(workspace_id, staged_at, completed_at)
                    VALUES (?, ?, ?)
                    ON CONFLICT(workspace_id) DO UPDATE SET
                        staged_at = excluded.staged_at,
                        completed_at = excluded.completed_at
                    """,
                arguments: [
                    replacement.workspace.id.uuidString,
                    replacement.stagedAt.timeIntervalSince1970,
                    replacement.completedAt?.timeIntervalSince1970,
                ]
            )
        }
    }

    func markWorkspaceSQLiteSnapshotComplete(workspaceId: UUID, completedAt: Date) throws {
        try markWorkspaceSQLiteSnapshotCommitted(workspaceId: workspaceId, committedAt: completedAt)
    }

    func markWorkspaceSQLiteSnapshotStaged(workspaceId: UUID, stagedAt: Date) throws {
        try databaseWriter.write { database in
            try requireWorkspaceExists(database, id: workspaceId)
            try database.execute(
                sql: """
                    INSERT INTO workspace_sqlite_snapshot_status(workspace_id, staged_at, completed_at)
                    VALUES (?, ?, NULL)
                    ON CONFLICT(workspace_id) DO UPDATE SET
                        staged_at = excluded.staged_at,
                        completed_at = NULL
                    """,
                arguments: [
                    workspaceId.uuidString,
                    stagedAt.timeIntervalSince1970,
                ]
            )
        }
    }

    func markWorkspaceSQLiteSnapshotCommitted(workspaceId: UUID, committedAt: Date) throws {
        try databaseWriter.write { database in
            try requireWorkspaceExists(database, id: workspaceId)
            try database.execute(
                sql: """
                    INSERT INTO workspace_sqlite_snapshot_status(workspace_id, staged_at, completed_at)
                    VALUES (?, ?, ?)
                    ON CONFLICT(workspace_id) DO UPDATE SET
                        staged_at = excluded.staged_at,
                        completed_at = excluded.completed_at
                    """,
                arguments: [
                    workspaceId.uuidString,
                    committedAt.timeIntervalSince1970,
                    committedAt.timeIntervalSince1970,
                ]
            )
        }
    }

    func clearWorkspaceSQLiteSnapshotComplete(workspaceId: UUID) throws {
        try databaseWriter.write { database in
            try database.execute(
                sql: """
                    DELETE FROM workspace_sqlite_snapshot_status
                    WHERE workspace_id = ?
                    """,
                arguments: [workspaceId.uuidString]
            )
        }
    }

    func hasCompletedWorkspaceSQLiteSnapshot(workspaceId: UUID) throws -> Bool {
        try fetchCompletedWorkspaceSQLiteSnapshotAt(workspaceId: workspaceId) != nil
    }

    func fetchCompletedWorkspaceSQLiteSnapshotAt(workspaceId: UUID) throws -> Date? {
        try databaseWriter.read { database in
            guard
                let completedAt = try Double.fetchOne(
                    database,
                    sql: """
                        SELECT completed_at
                        FROM workspace_sqlite_snapshot_status
                        WHERE workspace_id = ?
                          AND completed_at IS NOT NULL
                        """,
                    arguments: [workspaceId.uuidString]
                )
            else {
                return nil
            }
            return Date(timeIntervalSince1970: completedAt)
        }
    }

    func markLegacyWorkspaceCoreImported(
        workspaceId: UUID,
        sourceStatePath: String,
        importedAt: Date
    ) throws {
        try databaseWriter.write { database in
            try requireWorkspaceExists(database, id: workspaceId)
            try database.execute(
                sql: """
                    INSERT INTO legacy_workspace_import_status(
                        workspace_id, source_state_path, core_imported_at, last_error
                    )
                    VALUES (?, ?, ?, NULL)
                    ON CONFLICT(workspace_id) DO UPDATE SET
                        source_state_path = excluded.source_state_path,
                        core_imported_at = excluded.core_imported_at,
                        last_error = NULL
                    """,
                arguments: [
                    workspaceId.uuidString,
                    sourceStatePath,
                    importedAt.timeIntervalSince1970,
                ]
            )
        }
    }

    func markLegacyWorkspaceImportFailed(
        workspace: WorkspaceRecord,
        sourceStatePath: String,
        error: String
    ) throws {
        try databaseWriter.write { database in
            try database.execute(
                sql: """
                    INSERT INTO workspace(id, name, created_at, updated_at)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name,
                        updated_at = excluded.updated_at
                    """,
                arguments: [
                    workspace.id.uuidString,
                    workspace.name,
                    workspace.createdAt.timeIntervalSince1970,
                    workspace.updatedAt.timeIntervalSince1970,
                ]
            )
            try database.execute(
                sql: """
                    INSERT INTO legacy_workspace_import_status(
                        workspace_id, source_state_path, last_error
                    )
                    VALUES (?, ?, ?)
                    ON CONFLICT(workspace_id) DO UPDATE SET
                        source_state_path = excluded.source_state_path,
                        last_error = excluded.last_error
                    """,
                arguments: [
                    workspace.id.uuidString,
                    sourceStatePath,
                    error,
                ]
            )
        }
    }

    func markLegacyWorkspaceCompanionImportsCompleted(
        workspaceId: UUID,
        importedAt: Date
    ) throws {
        try databaseWriter.write { database in
            let statusCount =
                try Int.fetchOne(
                    database,
                    sql: """
                        SELECT count(*)
                        FROM legacy_workspace_import_status
                        WHERE workspace_id = ?
                        """,
                    arguments: [workspaceId.uuidString]
                ) ?? 0
            guard statusCount > 0 else {
                throw WorkspaceCoreRepositoryError.legacyImportStatusNotFound(workspaceId)
            }
            try database.execute(
                sql: """
                    UPDATE legacy_workspace_import_status
                    SET settings_imported_at = ?,
                        local_imported_at = ?,
                        cache_imported_at = ?,
                        last_error = NULL
                    WHERE workspace_id = ?
                    """,
                arguments: [
                    importedAt.timeIntervalSince1970,
                    importedAt.timeIntervalSince1970,
                    importedAt.timeIntervalSince1970,
                    workspaceId.uuidString,
                ]
            )
        }
    }

    func markLegacyWorkspaceArchived(workspaceId: UUID, archivedAt: Date) throws {
        try databaseWriter.write { database in
            let statusCount =
                try Int.fetchOne(
                    database,
                    sql: """
                        SELECT count(*)
                        FROM legacy_workspace_import_status
                        WHERE workspace_id = ?
                        """,
                    arguments: [workspaceId.uuidString]
                ) ?? 0
            guard statusCount > 0 else {
                throw WorkspaceCoreRepositoryError.legacyImportStatusNotFound(workspaceId)
            }
            try database.execute(
                sql: """
                    UPDATE legacy_workspace_import_status
                    SET archived_at = ?, last_error = NULL
                    WHERE workspace_id = ?
                    """,
                arguments: [
                    archivedAt.timeIntervalSince1970,
                    workspaceId.uuidString,
                ]
            )
        }
    }

    func fetchLegacyWorkspaceImportStatus(workspaceId: UUID) throws -> LegacyImportStatusRecord? {
        try databaseWriter.read { database in
            guard
                let row = try Row.fetchOne(
                    database,
                    sql: """
                        SELECT workspace_id, source_state_path, core_imported_at,
                               settings_imported_at, local_imported_at, cache_imported_at,
                               archived_at, last_error
                        FROM legacy_workspace_import_status
                        WHERE workspace_id = ?
                        """,
                    arguments: [workspaceId.uuidString]
                )
            else {
                return nil
            }
            return try decodeLegacyImportStatusRecord(row)
        }
    }

    func clearActiveWorkspaceSelection(updatedAt: Date) throws {
        try databaseWriter.write { database in
            guard try workspaceCount(database) == 0 else {
                throw WorkspaceCoreRepositoryError.cannotClearActiveWorkspaceWhileWorkspacesExist
            }
            try updateActiveWorkspaceSelection(database, workspaceId: nil, updatedAt: updatedAt)
        }
    }

    @discardableResult
    func repairActiveWorkspaceSelection(updatedAt: Date) throws -> UUID? {
        try databaseWriter.write { database in
            try repairActiveWorkspaceSelectionInDatabase(database, updatedAt: updatedAt)
        }
    }

    @discardableResult
    func repairActiveCompletedWorkspaceSelection(updatedAt: Date) throws -> UUID? {
        try databaseWriter.write { database in
            if let currentIdString = try fetchActiveWorkspaceIdStringFromDatabase(database),
                UUID(uuidString: currentIdString) != nil,
                try workspaceExists(database, id: currentIdString),
                try completedWorkspaceSQLiteSnapshotExists(database, id: currentIdString)
            {
                return UUID(uuidString: currentIdString)
            }

            let fallbackIdString = try fetchFallbackCompletedWorkspaceIdString(database)
            try updateActiveWorkspaceSelection(
                database,
                workspaceId: fallbackIdString,
                updatedAt: updatedAt
            )
            guard let fallbackIdString else { return nil }
            return UUID(uuidString: fallbackIdString)
        }
    }

    @discardableResult
    func deleteWorkspace(_ workspaceId: UUID, updatedAt: Date) throws -> UUID? {
        try databaseWriter.write { database in
            try requireWorkspaceExists(database, id: workspaceId)
            let activeWorkspaceIdStringAfterDelete = try prepareActiveWorkspaceSelectionForDelete(
                database,
                deletingWorkspaceId: workspaceId,
                updatedAt: updatedAt
            )
            try database.execute(
                sql: """
                        DELETE FROM workspace
                        WHERE id = ?
                    """,
                arguments: [workspaceId.uuidString]
            )
            guard let activeWorkspaceIdStringAfterDelete else { return nil }
            return UUID(uuidString: activeWorkspaceIdStringAfterDelete)
        }
    }

}

enum WorkspaceCoreRepositoryError: Error, Equatable {
    case workspaceNotFound(UUID)
    case repoNotFoundInWorkspace(UUID, UUID)
    case duplicateRepoId(UUID)
    case duplicateWorktreeId(UUID)
    case duplicateWatchedPathStableKey(String)
    case duplicateRepoStableKey(String)
    case duplicateWorktreeStableKey(String)
    case duplicatePaneId(UUID)
    case duplicateDrawerId(UUID)
    case duplicateTabId(UUID)
    case tabShellSetRequiresGraphReplacement(existingTabIds: Set<UUID>, incomingTabIds: Set<UUID>)
    case duplicateTabPaneId(tabId: UUID, paneId: UUID)
    case duplicateArrangementId(UUID)
    case legacyImportStatusNotFound(UUID)
    case paneBelongsToDifferentWorkspace(paneId: UUID, expectedWorkspaceId: UUID, actualWorkspaceId: UUID)
    case drawerBelongsToDifferentWorkspace(drawerId: UUID, expectedWorkspaceId: UUID, actualWorkspaceId: UUID)
    case tabBelongsToDifferentWorkspace(tabId: UUID, expectedWorkspaceId: UUID, actualWorkspaceId: UUID)
    case arrangementBelongsToDifferentWorkspace(
        arrangementId: UUID,
        expectedWorkspaceId: UUID,
        actualWorkspaceId: UUID
    )
    case paneNotFoundInWorkspace(UUID, UUID)
    case worktreeNotFoundInWorkspace(UUID, UUID)
    case tabNotFoundInWorkspace(UUID, UUID)
    case drawerNotFoundInWorkspace(UUID, UUID)
    case drawerParentPaneMissing(drawerId: UUID, parentPaneId: UUID)
    case drawerParentMismatch(drawerId: UUID, expectedParentPaneId: UUID, actualParentPaneId: UUID)
    case drawerChildPaneMissing(drawerId: UUID, childPaneId: UUID)
    case drawerChildParentMismatch(childPaneId: UUID, expectedParentPaneId: UUID, actualParentPaneId: UUID)
    case drawerChildMissingParent(childPaneId: UUID, parentPaneId: UUID)
    case drawerChildMembershipMissing(childPaneId: UUID, parentPaneId: UUID)
    case drawerChildListedMultipleTimes(childPaneId: UUID)
    case drawerChildCannotOwnDrawer(childPaneId: UUID, drawerId: UUID)
    case paneSourceFacetRepoMismatch(paneId: UUID, sourceRepoId: UUID, facetRepoId: UUID)
    case paneSourceFacetWorktreeMismatch(paneId: UUID, sourceWorktreeId: UUID, facetWorktreeId: UUID)
    case panePayloadContentTypeUnsupported(paneId: UUID, contentType: PaneContentType)
    case paneContentTypeIsImmutable(paneId: UUID, oldContentType: PaneContentType, newContentType: PaneContentType)
    case tabHasInvalidDefaultArrangementCount(tabId: UUID, count: Int)
    case tabHasNoPanes(UUID)
    case tabGraphMissingTabState(UUID)
    case tabPaneMissingFromArrangements(tabId: UUID, paneId: UUID)
    case arrangementLayoutPaneListedMultipleTimes(arrangementId: UUID, paneId: UUID)
    case layoutDividerListedMultipleTimes(arrangementId: UUID, dividerId: UUID)
    case arrangementPaneMissingFromTab(tabId: UUID, arrangementId: UUID, paneId: UUID)
    case arrangementMinimizedPaneMissingFromLayout(arrangementId: UUID, paneId: UUID)
    case defaultArrangementLayoutIsEmpty(tabId: UUID, arrangementId: UUID)
    case arrangementLayoutPaneUsesDrawerChild(arrangementId: UUID, paneId: UUID, parentPaneId: UUID)
    case drawerViewPaneNotInDrawer(drawerId: UUID, paneId: UUID)
    case drawerViewPaneListedMultipleTimes(arrangementId: UUID, paneId: UUID)
    case drawerViewDividerListedMultipleTimes(arrangementId: UUID, drawerId: UUID, dividerId: UUID)
    case drawerViewLayoutIsEmpty(arrangementId: UUID, drawerId: UUID)
    case drawerViewParentPaneMissingFromLayout(arrangementId: UUID, drawerId: UUID, parentPaneId: UUID)
    case malformedTabId(String)
    case malformedArrangementId(String)
    case malformedLayout(String)
    case unavailableRepoNotInTopology(UUID)
    case worktreeBelongsToDifferentWorkspace(
        worktreeId: UUID,
        expectedWorkspaceId: UUID,
        actualWorkspaceId: UUID
    )
    case worktreeRepoMismatch(worktreeId: UUID, expectedRepoId: UUID, actualRepoId: UUID)
    case activeWorkspaceSelectionDangling(UUID)
    case cannotClearActiveWorkspaceWhileWorkspacesExist
    case malformedWorkspaceId(String)
    case malformedRepoId(String)
    case malformedWorktreeId(String)
    case malformedWatchedPathId(String)
    case malformedPaneId(String)
    case malformedDrawerId(String)
    case malformedPaneContent(String)
}

private func decodeWorkspaceRecord(_ row: Row) throws -> WorkspaceCoreRepository.WorkspaceRecord {
    let idString: String = row["id"]
    guard let id = UUID(uuidString: idString) else {
        throw WorkspaceCoreRepositoryError.malformedWorkspaceId(idString)
    }
    let name: String = row["name"]
    let createdAt: Double = row["created_at"]
    let updatedAt: Double = row["updated_at"]
    return .init(
        id: id,
        name: name,
        createdAt: Date(timeIntervalSince1970: createdAt),
        updatedAt: Date(timeIntervalSince1970: updatedAt)
    )
}

private func decodeLegacyImportStatusRecord(_ row: Row) throws -> WorkspaceCoreRepository.LegacyImportStatusRecord {
    let workspaceIdString: String = row["workspace_id"]
    guard let workspaceId = UUID(uuidString: workspaceIdString) else {
        throw WorkspaceCoreRepositoryError.malformedWorkspaceId(workspaceIdString)
    }
    return .init(
        workspaceId: workspaceId,
        sourceStatePath: row["source_state_path"],
        coreImportedAt: optionalDate(row["core_imported_at"]),
        settingsImportedAt: optionalDate(row["settings_imported_at"]),
        localImportedAt: optionalDate(row["local_imported_at"]),
        cacheImportedAt: optionalDate(row["cache_imported_at"]),
        archivedAt: optionalDate(row["archived_at"]),
        lastError: row["last_error"]
    )
}

private func optionalDate(_ timestamp: Double?) -> Date? {
    timestamp.map { Date(timeIntervalSince1970: $0) }
}

private func fetchActiveWorkspaceIdFromDatabase(_ database: Database) throws -> UUID? {
    guard
        let idString = try fetchActiveWorkspaceIdStringFromDatabase(database)
    else {
        return nil
    }
    guard let id = UUID(uuidString: idString) else {
        throw WorkspaceCoreRepositoryError.malformedWorkspaceId(idString)
    }
    guard try workspaceExists(database, id: idString) else {
        throw WorkspaceCoreRepositoryError.activeWorkspaceSelectionDangling(id)
    }
    return id
}

private func repairActiveWorkspaceSelectionInDatabase(
    _ database: Database,
    updatedAt: Date
) throws -> UUID? {
    if let currentIdString = try fetchActiveWorkspaceIdStringFromDatabase(database),
        UUID(uuidString: currentIdString) != nil,
        try workspaceExists(database, id: currentIdString)
    {
        return UUID(uuidString: currentIdString)
    }

    let fallbackIdString = try fetchFallbackWorkspaceIdString(database)
    try updateActiveWorkspaceSelection(
        database,
        workspaceId: fallbackIdString,
        updatedAt: updatedAt
    )
    guard let fallbackIdString else { return nil }
    return UUID(uuidString: fallbackIdString)
}

private func fetchActiveWorkspaceIdStringFromDatabase(_ database: Database) throws -> String? {
    try String.fetchOne(
        database,
        sql: """
            SELECT active_workspace_id
            FROM app_workspace_selection
            WHERE singleton_id = 1
            """
    )
}

private func fetchFallbackWorkspaceIdString(
    _ database: Database,
    excluding excludedWorkspaceId: String? = nil
) throws -> String? {
    if let excludedWorkspaceId {
        return try String.fetchOne(
            database,
            sql: """
                SELECT id
                FROM workspace
                WHERE id != ?
                ORDER BY updated_at DESC, id ASC
                LIMIT 1
                """,
            arguments: [excludedWorkspaceId]
        )
    }
    return try String.fetchOne(
        database,
        sql: """
            SELECT id
            FROM workspace
            ORDER BY updated_at DESC, id ASC
            LIMIT 1
            """
    )
}

private func fetchFallbackCompletedWorkspaceIdString(_ database: Database) throws -> String? {
    try String.fetchOne(
        database,
        sql: """
            SELECT workspace.id
            FROM workspace
            JOIN workspace_sqlite_snapshot_status
              ON workspace_sqlite_snapshot_status.workspace_id = workspace.id
            WHERE workspace_sqlite_snapshot_status.completed_at IS NOT NULL
            ORDER BY workspace.updated_at DESC, workspace.id ASC
            LIMIT 1
            """
    )
}

private func completedWorkspaceSQLiteSnapshotExists(_ database: Database, id: String) throws -> Bool {
    let count =
        try Int.fetchOne(
            database,
            sql: """
                SELECT count(*)
                FROM workspace_sqlite_snapshot_status
                WHERE workspace_id = ?
                  AND completed_at IS NOT NULL
                """,
            arguments: [id]
        ) ?? 0
    return count > 0
}

private func updateActiveWorkspaceSelection(
    _ database: Database,
    workspaceId: String?,
    updatedAt: Date
) throws {
    try database.execute(
        sql: """
            INSERT INTO app_workspace_selection(singleton_id, active_workspace_id, updated_at)
            VALUES (1, ?, ?)
            ON CONFLICT(singleton_id) DO UPDATE SET
                active_workspace_id = excluded.active_workspace_id,
                updated_at = excluded.updated_at
            """,
        arguments: [
            workspaceId,
            updatedAt.timeIntervalSince1970,
        ]
    )
}

private func prepareActiveWorkspaceSelectionForDelete(
    _ database: Database,
    deletingWorkspaceId workspaceId: UUID,
    updatedAt: Date
) throws -> String? {
    guard let currentActiveWorkspaceIdString = try fetchActiveWorkspaceIdStringFromDatabase(database) else {
        return nil
    }
    guard let currentActiveWorkspaceId = UUID(uuidString: currentActiveWorkspaceIdString) else {
        throw WorkspaceCoreRepositoryError.malformedWorkspaceId(currentActiveWorkspaceIdString)
    }
    guard try workspaceExists(database, id: currentActiveWorkspaceIdString) else {
        throw WorkspaceCoreRepositoryError.activeWorkspaceSelectionDangling(currentActiveWorkspaceId)
    }
    guard currentActiveWorkspaceId == workspaceId else {
        return currentActiveWorkspaceIdString
    }

    let fallbackWorkspaceIdString = try fetchFallbackWorkspaceIdString(
        database,
        excluding: workspaceId.uuidString
    )
    try updateActiveWorkspaceSelection(
        database,
        workspaceId: fallbackWorkspaceIdString,
        updatedAt: updatedAt
    )
    return fallbackWorkspaceIdString
}

func requireWorkspaceExists(_ database: Database, id: UUID) throws {
    guard try workspaceExists(database, id: id.uuidString) else {
        throw WorkspaceCoreRepositoryError.workspaceNotFound(id)
    }
}

func workspaceExists(_ database: Database, id: String) throws -> Bool {
    let matchingCount = try Int.fetchOne(
        database,
        sql: """
            SELECT count(*)
            FROM workspace
            WHERE id = ?
            """,
        arguments: [id]
    )
    return matchingCount == 1
}

private func workspaceCount(_ database: Database) throws -> Int {
    try Int.fetchOne(
        database,
        sql: """
            SELECT count(*)
            FROM workspace
            """
    ) ?? 0
}
