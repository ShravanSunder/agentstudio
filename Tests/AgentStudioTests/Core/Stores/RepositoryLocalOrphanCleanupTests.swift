import Foundation
import GRDB
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@Suite("Repository local orphan cleanup")
struct RepositoryLocalOrphanCleanupTests {
    @Test("cleanup removes an old-family cache even when both families survive")
    func reparentedCheckoutCacheIsOrphaned() throws {
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: UUIDv7.generate())
        let oldRepositoryID = UUIDv7.generate()
        let currentRepositoryID = UUIDv7.generate()
        let movedWorktreeID = UUIDv7.generate()
        let keptWorktreeID = UUIDv7.generate()
        try fixture.databaseQueue.write { database in
            for worktreeID in [movedWorktreeID, keptWorktreeID] {
                try database.execute(
                    sql:
                        "INSERT INTO cache_worktree_enrichment(worktree_id, repo_id, is_main_worktree, updated_at) VALUES (?, ?, 0, 0)",
                    arguments: [worktreeID.uuidString, oldRepositoryID.uuidString]
                )
            }
        }
        let surviving = RepositoryRetentionSurvivingIdentity(
            repositoryIDs: [oldRepositoryID, currentRepositoryID],
            worktreeIDs: [movedWorktreeID, keptWorktreeID], repositoryKeys: [], worktreeKeys: [],
            worktreeRepositoryIDs: [movedWorktreeID: currentRepositoryID, keptWorktreeID: oldRepositoryID]
        )

        let removed = try fixture.repository.pruneOrphanedRepositoryState(surviving: surviving, limit: 64)

        #expect(removed == 1)
        let remaining = try fixture.databaseQueue.read { database in
            try String.fetchAll(database, sql: "SELECT worktree_id FROM cache_worktree_enrichment")
        }
        #expect(remaining == [keptWorktreeID.uuidString])
    }

    @Test("bounded cleanup preserves shared keys, unsettled activity, cursors and annotation history")
    func orphanCleanupPreservesIndependentOwners() throws {
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: UUIDv7.generate())
        let keptRepoID = UUIDv7.generate()
        let deadRepoID = UUIDv7.generate()
        let sessionID = UUIDv7.generate()
        try fixture.databaseQueue.write { database in
            for repoID in [keptRepoID, deadRepoID] {
                try database.execute(
                    sql:
                        "INSERT INTO cache_repo_enrichment(repo_id, state, updated_at) VALUES (?, 'awaitingOrigin', 0)",
                    arguments: [repoID.uuidString])
            }
            try database.execute(
                sql:
                    "INSERT INTO local_repository_activity_cursor(volume_identifier, last_event_id, updated_at) VALUES ('shared-volume', 42, 0)"
            )
            for key in ["shared", "obsolete", "owned"] {
                try database.execute(
                    sql:
                        "INSERT INTO local_entity_recency(entity_kind, entity_key, interaction_kind, last_interacted_at) VALUES ('repository', ?, 'opened', 0)",
                    arguments: [key])
                try database.execute(
                    sql:
                        "INSERT INTO local_repository_activity(repository_stable_key, continuous_coverage_started_at, updated_at, owned_promotion_unsettled) VALUES (?, 0, 0, ?)",
                    arguments: [key, key == "owned" ? 1 : 0])
            }
            try database.execute(
                sql: """
                    INSERT INTO annotation_session(id, repository_id, worktree_id, lifecycle, source_relationship,
                        accepted_source_fingerprint_json, created_at, updated_at)
                    VALUES (?, ?, ?, 'active', 'current', '{}', 0, 0)
                    """, arguments: [sessionID.uuidString, deadRepoID.uuidString, UUIDv7.generate().uuidString])
        }
        let surviving = RepositoryRetentionSurvivingIdentity(
            repositoryIDs: [keptRepoID], worktreeIDs: [], repositoryKeys: ["shared"], worktreeKeys: []
        )

        let removed = try fixture.repository.pruneOrphanedRepositoryState(surviving: surviving, limit: 64)
        let repeated = try fixture.repository.pruneOrphanedRepositoryState(surviving: surviving, limit: 64)

        #expect(removed > 0)
        #expect(repeated == 0)
        try fixture.databaseQueue.read { database in
            let caches = try String.fetchAll(database, sql: "SELECT repo_id FROM cache_repo_enrichment")
            let activity = try String.fetchAll(
                database,
                sql: "SELECT repository_stable_key FROM local_repository_activity ORDER BY repository_stable_key")
            let recency = try String.fetchAll(database, sql: "SELECT entity_key FROM local_entity_recency")
            let annotations = try String.fetchAll(database, sql: "SELECT id FROM annotation_session")
            #expect(caches == [keptRepoID.uuidString])
            #expect(activity == ["owned", "shared"])
            #expect(recency == ["shared"])
            #expect(annotations == [sessionID.uuidString])
            #expect(
                try Int.fetchOne(
                    database,
                    sql:
                        "SELECT last_event_id FROM local_repository_activity_cursor WHERE volume_identifier = 'shared-volume'"
                ) == 42)
        }
    }
}
