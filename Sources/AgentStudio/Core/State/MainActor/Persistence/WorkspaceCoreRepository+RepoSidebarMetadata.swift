import Foundation
import GRDB

extension WorkspaceCoreRepository {
    func updateRepoFavorite(repoId: UUID, isFavorite: Bool) throws {
        try databaseWriter.write { database in
            try requireRepoExists(database, repoId: repoId)
            try database.execute(
                sql: """
                    UPDATE repo
                    SET is_favorite = ?
                    WHERE id = ?
                    """,
                arguments: [isFavorite ? 1 : 0, repoId.uuidString]
            )
        }
    }

    func updateRepoNote(repoId: UUID, note: String?) throws {
        try databaseWriter.write { database in
            try requireRepoExists(database, repoId: repoId)
            try database.execute(
                sql: """
                    UPDATE repo
                    SET note = ?
                    WHERE id = ?
                    """,
                arguments: [normalizedSidebarNote(note), repoId.uuidString]
            )
        }
    }

    func updateWorktreeNote(worktreeId: UUID, note: String?) throws {
        try databaseWriter.write { database in
            try requireWorktreeExists(database, worktreeId: worktreeId)
            try database.execute(
                sql: """
                    UPDATE worktree
                    SET note = ?
                    WHERE id = ?
                    """,
                arguments: [normalizedSidebarNote(note), worktreeId.uuidString]
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

    func replaceRepoTags(repoId: UUID, tags: Set<String>) throws {
        try databaseWriter.write { database in
            try requireRepoExists(database, repoId: repoId)
            try database.execute(
                sql: """
                    DELETE FROM repo_tag
                    WHERE repo_id = ?
                    """,
                arguments: [repoId.uuidString]
            )
            let normalizedTags = normalizedRepoTags(tags)
            try validateRepositoryTags(normalizedTags)
            for tag in normalizedTags {
                try database.execute(
                    sql: """
                        INSERT INTO repo_tag(repo_id, tag)
                        VALUES (?, ?)
                        """,
                    arguments: [repoId.uuidString, tag]
                )
            }
        }
    }

    func fetchRepoTags(repoId: UUID) throws -> Set<String> {
        try databaseWriter.read { database in
            try requireRepoExists(database, repoId: repoId)
            let tags = try String.fetchAll(
                database,
                sql: """
                    SELECT tag
                    FROM repo_tag
                    WHERE repo_id = ?
                    ORDER BY tag ASC
                    """,
                arguments: [repoId.uuidString]
            )
            return Set(tags)
        }
    }
}

private func requireWorktreeExists(_ database: Database, worktreeId: UUID) throws {
    let matchingCount = try Int.fetchOne(
        database,
        sql: """
            SELECT count(*)
            FROM worktree
            WHERE id = ?
            """,
        arguments: [worktreeId.uuidString]
    )
    guard matchingCount == 1 else {
        throw WorkspaceCoreRepositoryError.worktreeNotFound(worktreeId)
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
