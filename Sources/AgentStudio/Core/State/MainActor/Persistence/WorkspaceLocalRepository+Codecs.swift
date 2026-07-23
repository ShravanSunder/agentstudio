import CoreGraphics
import Foundation
import GRDB

enum WorkspaceLocalRepositoryCodecs {
    struct CountRow {
        let worktreeId: UUID
        let repoId: UUID?
        let count: Int
        let updatedAtValue: Double
    }

    static func uuid(
        _ rawValue: String,
        _ error: (String) -> WorkspaceLocalRepositoryError
    ) throws -> UUID {
        guard let value = UUID(uuidString: rawValue) else {
            throw error(rawValue)
        }
        return value
    }

    static func encodeWindowFrame(_ windowFrame: CGRect?) throws -> String? {
        guard let windowFrame else { return nil }
        let data = try JSONEncoder().encode(windowFrame)
        guard let value = String(data: data, encoding: .utf8) else {
            throw WorkspaceLocalRepositoryError.invalidWindowFramePayload
        }
        return value
    }

    static func decodeWindowFrame(_ rawValue: String?) throws -> CGRect? {
        guard let rawValue else { return nil }
        return try JSONDecoder().decode(CGRect.self, from: Data(rawValue.utf8))
    }

    static func fetchWindowState(_ database: Database) throws -> WorkspaceLocalRepository.WindowStateRecord? {
        guard
            let row = try Row.fetchOne(
                database,
                sql: """
                    SELECT sidebar_width, window_frame_json
                    FROM local_window_state
                    WHERE window_role = 'main'
                    """
            )
        else {
            return nil
        }
        let sidebarWidth: Double = row["sidebar_width"]
        let windowFrameJSON: String? = row["window_frame_json"]
        return .init(
            sidebarWidth: sidebarWidth,
            windowFrame: try decodeWindowFrame(windowFrameJSON)
        )
    }

    static func fetchSidebarState(_ database: Database) throws -> WorkspaceLocalRepository.SidebarStateRecord? {
        guard
            let row = try Row.fetchOne(
                database,
                sql: """
                    SELECT filter_text, is_filter_visible, sidebar_collapsed, sidebar_surface
                    FROM local_window_state
                    WHERE window_role = 'main'
                    """
            )
        else {
            return nil
        }
        let surfaceValue: String = row["sidebar_surface"]
        guard let sidebarSurface = SQLiteLocalUXStorage.sidebarSurface(from: surfaceValue) else {
            throw WorkspaceLocalRepositoryError.unsupportedSidebarSurface(surfaceValue)
        }
        return .init(
            filterText: row["filter_text"],
            isFilterVisible: (row["is_filter_visible"] as Int) == 1,
            sidebarCollapsed: (row["sidebar_collapsed"] as Int) == 1,
            sidebarSurface: sidebarSurface
        )
    }

    static func insertRecentWorkspaceTarget(
        _ database: Database,
        workspaceIdString: String,
        target: RecentWorkspaceTarget
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO local_recent_workspace_target(
                    workspace_id, id, path, display_title, subtitle, repo_id, worktree_id, kind, last_opened_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                workspaceIdString,
                target.id,
                target.path.standardizedFileURL.path,
                target.displayTitle,
                target.subtitle,
                target.repoId?.uuidString,
                target.worktreeId?.uuidString,
                SQLiteLocalUXStorage.storageValue(for: target.kind),
                target.lastOpenedAt.timeIntervalSince1970,
            ]
        )
    }

    static func fetchRecentWorkspaceTargets(
        _ database: Database,
        workspaceIdString: String
    ) throws -> [RecentWorkspaceTarget] {
        let rows = try Row.fetchAll(
            database,
            sql: """
                SELECT id, path, display_title, subtitle, repo_id, worktree_id, kind, last_opened_at
                FROM local_recent_workspace_target
                WHERE workspace_id = ?
                ORDER BY last_opened_at DESC, id ASC
                """,
            arguments: [workspaceIdString]
        )
        return rows.compactMap { try? decodeRecentWorkspaceTarget($0) }
    }

    static func decodeRecentWorkspaceTarget(_ row: Row) throws -> RecentWorkspaceTarget {
        let kindValue: String = row["kind"]
        guard let kind = SQLiteLocalUXStorage.recentWorkspaceTargetKind(from: kindValue) else {
            throw WorkspaceLocalRepositoryError.unsupportedRecentTargetKind(kindValue)
        }
        let repoIdString: String? = row["repo_id"]
        let worktreeIdString: String? = row["worktree_id"]
        let payload = RecentWorkspaceTargetPayload(
            id: row["id"],
            path: URL(fileURLWithPath: row["path"]).standardizedFileURL,
            displayTitle: row["display_title"],
            subtitle: row["subtitle"],
            repoId: try repoIdString.map { try uuid($0, WorkspaceLocalRepositoryError.malformedRepoId) },
            worktreeId: try worktreeIdString.map {
                try uuid($0, WorkspaceLocalRepositoryError.malformedWorktreeId)
            },
            kind: kind,
            lastOpenedAt: Date(timeIntervalSince1970: row["last_opened_at"])
        )
        return try JSONDecoder().decode(
            RecentWorkspaceTarget.self,
            from: JSONEncoder().encode(payload)
        )
    }

    static func insertRepoEnrichment(
        _ database: Database,
        enrichment: RepoEnrichment,
        updatedAt: Date
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO cache_repo_enrichment(
                    repo_id, state, origin, upstream, group_key, remote_slug,
                    organization_name, display_name, updated_at, payload_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                enrichment.repoId.uuidString,
                repoEnrichmentState(enrichment),
                enrichment.origin,
                enrichment.upstream,
                enrichment.groupKey,
                enrichment.remoteSlug,
                enrichment.organizationName,
                enrichment.displayName,
                repoEnrichmentUpdatedAt(enrichment)?.timeIntervalSince1970 ?? updatedAt.timeIntervalSince1970,
                try encodePayload(enrichment),
            ]
        )
    }

    static func insertWorktreeEnrichment(_ database: Database, enrichment: WorktreeEnrichment) throws {
        try database.execute(
            sql: """
                INSERT INTO cache_worktree_enrichment(
                    worktree_id, repo_id, branch, is_main_worktree, updated_at, payload_json
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                enrichment.worktreeId.uuidString,
                enrichment.repoId.uuidString,
                enrichment.branch,
                enrichment.isMainWorktree ? 1 : 0,
                enrichment.updatedAt.timeIntervalSince1970,
                try encodePayload(enrichment),
            ]
        )
    }

    static func insertPullRequestCount(_ database: Database, row: CountRow) throws {
        try database.execute(
            sql: """
                INSERT INTO cache_pull_request_count(worktree_id, repo_id, count, updated_at)
                VALUES (?, ?, ?, ?)
                """,
            arguments: [row.worktreeId.uuidString, row.repoId?.uuidString, row.count, row.updatedAtValue]
        )
    }

    static func fetchRepoEnrichments(_ database: Database) throws -> [UUID: RepoEnrichment] {
        let rows = try Row.fetchAll(database, sql: "SELECT repo_id, payload_json FROM cache_repo_enrichment")
        return Dictionary(
            uniqueKeysWithValues: rows.compactMap { row in
                guard
                    let repoId = try? uuid(row["repo_id"], WorkspaceLocalRepositoryError.malformedRepoId),
                    let payload: String = row["payload_json"],
                    let enrichment = try? decodePayload(RepoEnrichment.self, payload)
                else {
                    return nil
                }
                return (repoId, enrichment)
            }
        )
    }

    static func fetchWorktreeEnrichments(_ database: Database) throws -> [UUID: WorktreeEnrichment] {
        let rows = try Row.fetchAll(database, sql: "SELECT worktree_id, payload_json FROM cache_worktree_enrichment")
        return Dictionary(
            uniqueKeysWithValues: rows.compactMap { row in
                guard
                    let worktreeId = try? uuid(row["worktree_id"], WorkspaceLocalRepositoryError.malformedWorktreeId),
                    let payload: String = row["payload_json"],
                    let enrichment = try? decodePayload(WorktreeEnrichment.self, payload)
                else {
                    return nil
                }
                return (worktreeId, enrichment)
            }
        )
    }

    static func fetchPullRequestCounts(_ database: Database) throws -> [UUID: Int] {
        let rows = try Row.fetchAll(database, sql: "SELECT worktree_id, count FROM cache_pull_request_count")
        return Dictionary(
            uniqueKeysWithValues: rows.compactMap { row in
                guard let worktreeId = try? uuid(row["worktree_id"], WorkspaceLocalRepositoryError.malformedWorktreeId)
                else {
                    return nil
                }
                let count: Int = row["count"]
                return (worktreeId, count)
            }
        )
    }

    static func encodePayload<TValue: Encodable>(_ value: TValue) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let payload = String(data: data, encoding: .utf8) else {
            throw WorkspaceLocalRepositoryError.invalidCachePayload
        }
        return payload
    }

    static func decodePayload<TValue: Decodable>(_ type: TValue.Type, _ payload: String) throws -> TValue {
        try JSONDecoder().decode(type, from: Data(payload.utf8))
    }

    static func repoEnrichmentState(_ enrichment: RepoEnrichment) -> String {
        switch enrichment {
        case .awaitingOrigin:
            "awaitingOrigin"
        case .resolvedLocal:
            "resolvedLocal"
        case .resolvedRemote:
            "resolvedRemote"
        }
    }

    static func repoEnrichmentUpdatedAt(_ enrichment: RepoEnrichment) -> Date? {
        switch enrichment {
        case .awaitingOrigin:
            nil
        case .resolvedLocal(_, _, let updatedAt):
            updatedAt
        case .resolvedRemote(_, _, _, let updatedAt):
            updatedAt
        }
    }

    private struct RecentWorkspaceTargetPayload: Codable {
        let id: String
        let path: URL
        let displayTitle: String
        let subtitle: String
        let repoId: UUID?
        let worktreeId: UUID?
        let kind: RecentWorkspaceTarget.Kind
        let lastOpenedAt: Date
    }
}
