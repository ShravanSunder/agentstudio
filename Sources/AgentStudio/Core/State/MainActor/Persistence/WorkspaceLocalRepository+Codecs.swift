import CoreGraphics
import Foundation
import GRDB

enum WorkspaceLocalRepositoryCodecs {
    struct CountRow {
        let workspaceIdString: String
        let worktreeId: UUID
        let repoId: UUID?
        let count: Int
        let updatedAtValue: Double
    }

    enum CountTable {
        case pullRequest
        case notification

        var name: String {
            switch self {
            case .pullRequest:
                "cache_pull_request_count"
            case .notification:
                "cache_notification_count"
            }
        }
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

    static func fetchWindowState(
        _ database: Database,
        workspaceIdString: String
    ) throws -> WorkspaceLocalRepository.WindowStateRecord? {
        guard
            let row = try Row.fetchOne(
                database,
                sql: """
                    SELECT sidebar_width, window_frame_json
                    FROM local_workspace_window_state
                    WHERE workspace_id = ?
                    """,
                arguments: [workspaceIdString]
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

    static func fetchSidebarState(
        _ database: Database,
        workspaceIdString: String
    ) throws -> WorkspaceLocalRepository.SidebarStateRecord? {
        guard
            let row = try Row.fetchOne(
                database,
                sql: """
                    SELECT filter_text, is_filter_visible, sidebar_collapsed, sidebar_surface
                    FROM local_sidebar_state
                    WHERE workspace_id = ?
                    """,
                arguments: [workspaceIdString]
            )
        else {
            return nil
        }
        let surfaceValue: String = row["sidebar_surface"]
        return .init(
            filterText: row["filter_text"],
            isFilterVisible: (row["is_filter_visible"] as Int) == 1,
            sidebarCollapsed: (row["sidebar_collapsed"] as Int) == 1,
            sidebarSurface: try sidebarSurface(from: surfaceValue)
        )
    }

    static func sidebarSurface(from rawValue: String) throws -> SidebarSurface {
        switch rawValue {
        case SQLiteLocalUXStorage.sidebarSurfaceRepos:
            .repos
        case SQLiteLocalUXStorage.sidebarSurfaceInbox:
            .inbox
        default:
            throw WorkspaceLocalRepositoryError.unsupportedSidebarSurface(rawValue)
        }
    }

    static func insertRecentWorkspaceTarget(
        _ database: Database,
        workspaceIdString: String,
        target: RecentWorkspaceTarget
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO local_recent_workspace_target(
                    id, workspace_id, path, display_title, subtitle, repo_id, worktree_id, kind, last_opened_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                target.id,
                workspaceIdString,
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
        return try rows.map(decodeRecentWorkspaceTarget)
    }

    static func decodeRecentWorkspaceTarget(_ row: Row) throws -> RecentWorkspaceTarget {
        let kindValue: String = row["kind"]
        guard let kind = RecentWorkspaceTarget.Kind(rawValue: kindValue) else {
            throw WorkspaceLocalRepositoryError.unsupportedRecentTargetKind(kindValue)
        }
        let repoIdString: String? = row["repo_id"]
        let worktreeIdString: String? = row["worktree_id"]
        let lastOpenedAtValue: Double = row["last_opened_at"]
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
            lastOpenedAt: Date(timeIntervalSince1970: lastOpenedAtValue)
        )
        let data = try JSONEncoder().encode(payload)
        return try JSONDecoder().decode(RecentWorkspaceTarget.self, from: data)
    }

    static func insertRepoEnrichment(
        _ database: Database,
        workspaceIdString: String,
        enrichment: RepoEnrichment,
        updatedAt: Date
    ) throws {
        let payload = try encodePayload(enrichment)
        try database.execute(
            sql: """
                INSERT INTO cache_repo_enrichment(
                    repo_id, workspace_id, state, origin, upstream, group_key, remote_slug,
                    organization_name, display_name, updated_at, payload_json
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                enrichment.repoId.uuidString,
                workspaceIdString,
                repoEnrichmentState(enrichment),
                enrichment.origin,
                enrichment.upstream,
                enrichment.groupKey,
                enrichment.remoteSlug,
                enrichment.organizationName,
                enrichment.displayName,
                repoEnrichmentUpdatedAt(enrichment)?.timeIntervalSince1970 ?? updatedAt.timeIntervalSince1970,
                payload,
            ]
        )
    }

    static func insertWorktreeEnrichment(
        _ database: Database,
        workspaceIdString: String,
        enrichment: WorktreeEnrichment
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO cache_worktree_enrichment(
                    worktree_id, workspace_id, repo_id, branch, is_main_worktree, updated_at, payload_json
                )
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                enrichment.worktreeId.uuidString,
                workspaceIdString,
                enrichment.repoId.uuidString,
                enrichment.branch,
                enrichment.isMainWorktree ? 1 : 0,
                enrichment.updatedAt.timeIntervalSince1970,
                try encodePayload(enrichment),
            ]
        )
    }

    static func insertCount(
        _ database: Database,
        table: CountTable,
        row: CountRow
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO \(table.name)(worktree_id, workspace_id, repo_id, count, updated_at)
                VALUES (?, ?, ?, ?, ?)
                """,
            arguments: [
                row.worktreeId.uuidString,
                row.workspaceIdString,
                row.repoId?.uuidString,
                row.count,
                row.updatedAtValue,
            ]
        )
    }

    static func fetchRepoEnrichments(
        _ database: Database,
        workspaceIdString: String
    ) throws -> [UUID: RepoEnrichment] {
        let rows = try Row.fetchAll(
            database,
            sql: """
                SELECT repo_id, payload_json
                FROM cache_repo_enrichment
                WHERE workspace_id = ?
                """,
            arguments: [workspaceIdString]
        )
        return try Dictionary(
            uniqueKeysWithValues: rows.map { row in
                let repoId = try uuid(row["repo_id"], WorkspaceLocalRepositoryError.malformedRepoId)
                guard let payload: String = row["payload_json"] else {
                    throw WorkspaceLocalRepositoryError.missingRepoEnrichmentPayload(repoId)
                }
                return (repoId, try decodePayload(RepoEnrichment.self, payload))
            }
        )
    }

    static func fetchWorktreeEnrichments(
        _ database: Database,
        workspaceIdString: String
    ) throws -> [UUID: WorktreeEnrichment] {
        let rows = try Row.fetchAll(
            database,
            sql: """
                SELECT worktree_id, payload_json
                FROM cache_worktree_enrichment
                WHERE workspace_id = ?
                """,
            arguments: [workspaceIdString]
        )
        return try Dictionary(
            uniqueKeysWithValues: rows.map { row in
                let worktreeId = try uuid(row["worktree_id"], WorkspaceLocalRepositoryError.malformedWorktreeId)
                guard let payload: String = row["payload_json"] else {
                    throw WorkspaceLocalRepositoryError.missingWorktreeEnrichmentPayload(worktreeId)
                }
                return (worktreeId, try decodePayload(WorktreeEnrichment.self, payload))
            }
        )
    }

    static func fetchCounts(
        _ database: Database,
        table: CountTable,
        workspaceIdString: String
    ) throws -> [UUID: Int] {
        let rows = try Row.fetchAll(
            database,
            sql: """
                SELECT worktree_id, count
                FROM \(table.name)
                WHERE workspace_id = ?
                """,
            arguments: [workspaceIdString]
        )
        return try Dictionary(
            uniqueKeysWithValues: rows.map { row in
                let worktreeId = try uuid(row["worktree_id"], WorkspaceLocalRepositoryError.malformedWorktreeId)
                let count: Int = row["count"]
                return (worktreeId, count)
            }
        )
    }

    static func encodePayload<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let payload = String(data: data, encoding: .utf8) else {
            throw WorkspaceLocalRepositoryError.invalidCachePayload
        }
        return payload
    }

    static func decodePayload<T: Decodable>(_ type: T.Type, _ payload: String) throws -> T {
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
