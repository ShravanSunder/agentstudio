import Foundation
import GRDB

extension WorkspaceCoreRepository {
    func updateRepoFavorite(workspaceId: UUID, repoId: UUID, isFavorite: Bool) throws {
        try databaseWriter.write { database in
            try requireWorkspaceExists(database, id: workspaceId)
            try requireRepoExists(database, repoId: repoId, workspaceId: workspaceId)
            try database.execute(
                sql: """
                    UPDATE repo
                    SET is_favorite = ?
                    WHERE workspace_id = ?
                    AND id = ?
                    """,
                arguments: [isFavorite ? 1 : 0, workspaceId.uuidString, repoId.uuidString]
            )
        }
    }

    func updateRepoNote(workspaceId: UUID, repoId: UUID, note: String?) throws {
        try databaseWriter.write { database in
            try requireWorkspaceExists(database, id: workspaceId)
            try requireRepoExists(database, repoId: repoId, workspaceId: workspaceId)
            try database.execute(
                sql: """
                    UPDATE repo
                    SET note = ?
                    WHERE workspace_id = ?
                    AND id = ?
                    """,
                arguments: [normalizedSidebarNote(note), workspaceId.uuidString, repoId.uuidString]
            )
        }
    }

    func updateWorktreeNote(workspaceId: UUID, worktreeId: UUID, note: String?) throws {
        try databaseWriter.write { database in
            try requireWorkspaceExists(database, id: workspaceId)
            try requireWorktreeExists(database, worktreeId: worktreeId, workspaceId: workspaceId)
            try database.execute(
                sql: """
                    UPDATE worktree
                    SET note = ?
                    WHERE workspace_id = ?
                    AND id = ?
                    """,
                arguments: [normalizedSidebarNote(note), workspaceId.uuidString, worktreeId.uuidString]
            )
        }
    }

    func updateTabColorHex(workspaceId: UUID, tabId: UUID, colorHex: String?) throws {
        try databaseWriter.write { database in
            try requireWorkspaceExists(database, id: workspaceId)
            try requireTabExists(database, tabId: tabId, workspaceId: workspaceId)
            try database.execute(
                sql: """
                    UPDATE tab_shell
                    SET color_hex = ?
                    WHERE workspace_id = ?
                    AND id = ?
                    """,
                arguments: [normalizedSidebarNote(colorHex), workspaceId.uuidString, tabId.uuidString]
            )
        }
    }

    func replaceRepoTags(workspaceId: UUID, repoId: UUID, tags: Set<String>) throws {
        try databaseWriter.write { database in
            try requireWorkspaceExists(database, id: workspaceId)
            try requireRepoExists(database, repoId: repoId, workspaceId: workspaceId)
            try database.execute(
                sql: """
                    DELETE FROM repo_tag
                    WHERE workspace_id = ?
                    AND repo_id = ?
                    """,
                arguments: [workspaceId.uuidString, repoId.uuidString]
            )
            let normalizedTags = normalizedRepoTags(tags)
            try validateRepositoryTags(normalizedTags)
            for tag in normalizedTags {
                try database.execute(
                    sql: """
                        INSERT INTO repo_tag(repo_id, workspace_id, tag)
                        VALUES (?, ?, ?)
                        """,
                    arguments: [repoId.uuidString, workspaceId.uuidString, tag]
                )
            }
        }
    }

    func fetchRepoTags(workspaceId: UUID, repoId: UUID) throws -> Set<String> {
        try databaseWriter.read { database in
            try requireWorkspaceExists(database, id: workspaceId)
            try requireRepoExists(database, repoId: repoId, workspaceId: workspaceId)
            let tags = try String.fetchAll(
                database,
                sql: """
                    SELECT tag
                    FROM repo_tag
                    WHERE workspace_id = ?
                    AND repo_id = ?
                    ORDER BY tag ASC
                    """,
                arguments: [workspaceId.uuidString, repoId.uuidString]
            )
            return Set(tags)
        }
    }
}

private func requireWorktreeExists(_ database: Database, worktreeId: UUID, workspaceId: UUID) throws {
    let matchingCount = try Int.fetchOne(
        database,
        sql: """
            SELECT count(*)
            FROM worktree
            WHERE id = ?
            AND workspace_id = ?
            """,
        arguments: [worktreeId.uuidString, workspaceId.uuidString]
    )
    guard matchingCount == 1 else {
        throw WorkspaceCoreRepositoryError.worktreeNotFoundInWorkspace(worktreeId, workspaceId)
    }
}

private func requireTabExists(_ database: Database, tabId: UUID, workspaceId: UUID) throws {
    let matchingCount = try Int.fetchOne(
        database,
        sql: """
            SELECT count(*)
            FROM tab_shell
            WHERE id = ?
            AND workspace_id = ?
            """,
        arguments: [tabId.uuidString, workspaceId.uuidString]
    )
    guard matchingCount == 1 else {
        throw WorkspaceCoreRepositoryError.tabNotFoundInWorkspace(tabId, workspaceId)
    }
}

private func normalizedSidebarNote(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed?.isEmpty == true ? nil : trimmed
}

private func normalizedRepoTags(_ tags: Set<String>) -> [String] {
    tags.compactMap(normalizedSidebarNote).sorted()
}
