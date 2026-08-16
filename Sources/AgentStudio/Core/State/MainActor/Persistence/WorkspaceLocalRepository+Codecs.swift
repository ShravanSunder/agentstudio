import CoreGraphics
import Foundation
import GRDB

enum WorkspaceLocalRepositoryCodecs {
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

    static func insertApplicationEntityRecency(
        _ database: Database,
        recency: ApplicationEntityRecency
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO local_entity_recency(
                    entity_kind, entity_key, interaction_kind, last_interacted_at
                )
                VALUES (?, ?, ?, ?)
                """,
            arguments: [
                recency.entity.storageKind,
                recency.entity.storageKey,
                recency.interaction.rawValue,
                recency.lastInteractedAt.timeIntervalSince1970,
            ]
        )
    }

    static func fetchApplicationEntityRecency(_ database: Database) throws -> [ApplicationEntityRecency] {
        let rows = try Row.fetchAll(
            database,
            sql: """
                SELECT entity_kind, entity_key, interaction_kind, last_interacted_at
                FROM local_entity_recency
                ORDER BY last_interacted_at DESC, entity_kind ASC, entity_key ASC
                """
        )
        return rows.compactMap { try? decodeApplicationEntityRecency($0) }
    }

    static func insertWorkspaceEntityRecency(
        _ database: Database,
        recency: WorkspaceEntityRecency
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO local_workspace_entity_recency(
                    workspace_id, entity_kind, entity_key, interaction_kind, last_interacted_at
                )
                VALUES (?, ?, ?, ?, ?)
                """,
            arguments: [
                recency.workspaceID.uuidString,
                recency.entity.storageKind,
                recency.entity.storageKey,
                recency.interaction.rawValue,
                recency.lastInteractedAt.timeIntervalSince1970,
            ]
        )
    }

    static func fetchWorkspaceEntityRecency(
        _ database: Database,
        workspaceID: UUID
    ) throws -> [WorkspaceEntityRecency] {
        let rows = try Row.fetchAll(
            database,
            sql: """
                SELECT workspace_id, entity_kind, entity_key, interaction_kind, last_interacted_at
                FROM local_workspace_entity_recency
                WHERE workspace_id = ?
                ORDER BY last_interacted_at DESC, entity_kind ASC, entity_key ASC
                """,
            arguments: [workspaceID.uuidString]
        )
        return rows.compactMap { try? decodeWorkspaceEntityRecency($0) }
    }

    private static func decodeApplicationEntityRecency(_ row: Row) throws -> ApplicationEntityRecency {
        let interactionValue: String = row["interaction_kind"]
        guard let interaction = EntityRecencyInteraction(rawValue: interactionValue) else {
            throw EntityRecencyValidationError.unsupportedInteraction
        }
        return try ApplicationEntityRecency(
            entity: ApplicationRecentEntity(
                storageKind: row["entity_kind"],
                storageKey: row["entity_key"]
            ),
            interaction: interaction,
            lastInteractedAt: Date(timeIntervalSince1970: row["last_interacted_at"])
        )
    }

    private static func decodeWorkspaceEntityRecency(_ row: Row) throws -> WorkspaceEntityRecency {
        let workspaceIDString: String = row["workspace_id"]
        guard
            let workspaceID = UUID(uuidString: workspaceIDString),
            workspaceID.uuidString == workspaceIDString
        else {
            throw EntityRecencyValidationError.invalidEntityKey
        }
        let interactionValue: String = row["interaction_kind"]
        guard let interaction = EntityRecencyInteraction(rawValue: interactionValue) else {
            throw EntityRecencyValidationError.unsupportedInteraction
        }
        return try WorkspaceEntityRecency(
            workspaceID: workspaceID,
            entity: WorkspaceRecentEntity(
                storageKind: row["entity_kind"],
                storageKey: row["entity_key"]
            ),
            interaction: interaction,
            lastInteractedAt: Date(timeIntervalSince1970: row["last_interacted_at"])
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
        case .awaitingOrigin, .statusUnavailable:
            "awaitingOrigin"
        case .resolvedLocal:
            "resolvedLocal"
        case .resolvedRemote:
            "resolvedRemote"
        }
    }

    static func repoEnrichmentUpdatedAt(_ enrichment: RepoEnrichment) -> Date? {
        switch enrichment {
        case .awaitingOrigin, .statusUnavailable:
            nil
        case .resolvedLocal(_, _, let updatedAt):
            updatedAt
        case .resolvedRemote(_, _, _, let updatedAt):
            updatedAt
        }
    }

}
