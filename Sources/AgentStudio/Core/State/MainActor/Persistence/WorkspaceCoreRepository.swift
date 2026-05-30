import Foundation
import GRDB

struct WorkspaceCoreRepository {
    struct WorkspaceRecord: Equatable {
        let id: UUID
        var name: String
        let createdAt: Date
        let updatedAt: Date
    }

    private let databaseWriter: any DatabaseWriter

    init(databaseWriter: any DatabaseWriter) {
        self.databaseWriter = databaseWriter
    }

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
    func deleteWorkspace(_ workspaceId: UUID, updatedAt: Date) throws -> UUID? {
        try databaseWriter.write { database in
            try requireWorkspaceExists(database, id: workspaceId)
            let currentActiveWorkspaceIdString = try fetchActiveWorkspaceIdStringFromDatabase(database)
            let fallbackWorkspaceIdString = try fetchFallbackWorkspaceIdString(
                database,
                excluding: workspaceId.uuidString
            )
            let activeWorkspaceIdStringAfterDelete: String?
            if try selectionShouldRepairBeforeDeleting(
                database,
                currentActiveWorkspaceIdString: currentActiveWorkspaceIdString,
                deletingWorkspaceIdString: workspaceId.uuidString
            ) {
                try updateActiveWorkspaceSelection(
                    database,
                    workspaceId: fallbackWorkspaceIdString,
                    updatedAt: updatedAt
                )
                activeWorkspaceIdStringAfterDelete = fallbackWorkspaceIdString
            } else {
                activeWorkspaceIdStringAfterDelete = currentActiveWorkspaceIdString
            }
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
    case cannotClearActiveWorkspaceWhileWorkspacesExist
    case malformedWorkspaceId(String)
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

private func fetchActiveWorkspaceIdFromDatabase(_ database: Database) throws -> UUID? {
    guard
        let idString = try fetchActiveWorkspaceIdStringFromDatabase(database)
    else {
        return nil
    }
    return UUID(uuidString: idString)
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

private func selectionShouldRepairBeforeDeleting(
    _ database: Database,
    currentActiveWorkspaceIdString: String?,
    deletingWorkspaceIdString: String
) throws -> Bool {
    guard let currentActiveWorkspaceIdString else { return true }
    if currentActiveWorkspaceIdString == deletingWorkspaceIdString {
        return true
    }
    let currentSelectionIsMalformed = UUID(uuidString: currentActiveWorkspaceIdString) == nil
    let currentSelectionExists = try workspaceExists(database, id: currentActiveWorkspaceIdString)
    return currentSelectionIsMalformed || !currentSelectionExists
}

private func requireWorkspaceExists(_ database: Database, id: UUID) throws {
    guard try workspaceExists(database, id: id.uuidString) else {
        throw WorkspaceCoreRepositoryError.workspaceNotFound(id)
    }
}

private func workspaceExists(_ database: Database, id: String) throws -> Bool {
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
