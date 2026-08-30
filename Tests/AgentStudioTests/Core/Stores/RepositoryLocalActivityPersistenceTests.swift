import Foundation
import GRDB
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@Suite("Repository local activity persistence")
struct RepositoryLocalActivityPersistenceTests {
    @Test("activity and cursor advancement commit atomically")
    func activityAndCursorAdvancementCommitAtomically() throws {
        // Arrange
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)
        let repository = WorkspaceLocalRepository(workspaceId: UUIDv7.generate(), databaseWriter: databaseQueue)
        let stableKey = "aaaaaaaaaaaaaaaa"
        let initialCommit = try RepositoryLocalActivityCommit(
            repositoryUpdates: [
                .init(
                    repositoryStableKey: stableKey,
                    qualifyingActivityAt: Date(timeIntervalSince1970: 120),
                    coverageChange: .restart(at: Date(timeIntervalSince1970: 100))
                )
            ],
            cursorWatermarks: [
                try RepositoryLocalActivityCursor(
                    volumeIdentifier: "volume-a",
                    lastEventID: 10,
                    updatedAt: Date(timeIntervalSince1970: 130)
                )
            ],
            updatedAt: Date(timeIntervalSince1970: 130)
        )
        _ = try repository.commitRepositoryLocalActivity(initialCommit)
        try databaseQueue.write { database in
            try database.execute(
                sql: """
                    CREATE TRIGGER reject_activity_advance
                    BEFORE UPDATE ON local_repository_activity
                    WHEN NEW.last_qualifying_activity_at = 200
                    BEGIN
                        SELECT RAISE(ABORT, 'reject activity advance');
                    END
                    """
            )
        }
        let rejectedCommit = try RepositoryLocalActivityCommit(
            repositoryUpdates: [
                .init(
                    repositoryStableKey: stableKey,
                    qualifyingActivityAt: Date(timeIntervalSince1970: 200)
                )
            ],
            cursorWatermarks: [
                try RepositoryLocalActivityCursor(
                    volumeIdentifier: "volume-a",
                    lastEventID: 20,
                    updatedAt: Date(timeIntervalSince1970: 210)
                )
            ],
            updatedAt: Date(timeIntervalSince1970: 210)
        )

        // Act / Assert
        #expect(throws: (any Error).self) {
            _ = try repository.commitRepositoryLocalActivity(rejectedCommit)
        }
        let accepted = try repository.fetchRepositoryLocalActivitySnapshot()
        #expect(
            accepted.activityByRepositoryStableKey[stableKey]?.lastQualifyingActivityAt
                == Date(timeIntervalSince1970: 120))
        #expect(accepted.cursorByVolumeIdentifier["volume-a"]?.lastEventID == 10)
    }

    @Test("older evidence and cursors do not rewrite accepted facts")
    func olderEvidenceAndCursorsDoNotRewriteAcceptedFacts() throws {
        // Arrange
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)
        let repository = WorkspaceLocalRepository(workspaceId: UUIDv7.generate(), databaseWriter: databaseQueue)
        let stableKey = "bbbbbbbbbbbbbbbb"
        _ = try repository.commitRepositoryLocalActivity(
            try RepositoryLocalActivityCommit(
                repositoryUpdates: [
                    .init(
                        repositoryStableKey: stableKey,
                        qualifyingActivityAt: Date(timeIntervalSince1970: 200),
                        coverageChange: .restart(at: Date(timeIntervalSince1970: 100))
                    )
                ],
                cursorWatermarks: [
                    try RepositoryLocalActivityCursor(
                        volumeIdentifier: "volume-b",
                        lastEventID: 20,
                        updatedAt: Date(timeIntervalSince1970: 210)
                    )
                ],
                updatedAt: Date(timeIntervalSince1970: 210)
            )
        )

        // Act
        let accepted = try repository.commitRepositoryLocalActivity(
            try RepositoryLocalActivityCommit(
                repositoryUpdates: [
                    .init(
                        repositoryStableKey: stableKey,
                        qualifyingActivityAt: Date(timeIntervalSince1970: 150)
                    )
                ],
                cursorWatermarks: [
                    try RepositoryLocalActivityCursor(
                        volumeIdentifier: "volume-b",
                        lastEventID: 19,
                        updatedAt: Date(timeIntervalSince1970: 300)
                    )
                ],
                updatedAt: Date(timeIntervalSince1970: 300)
            )
        )

        // Assert
        #expect(
            accepted.activityByRepositoryStableKey[stableKey]?.lastQualifyingActivityAt
                == Date(timeIntervalSince1970: 200))
        #expect(accepted.activityByRepositoryStableKey[stableKey]?.updatedAt == Date(timeIntervalSince1970: 210))
        #expect(accepted.cursorByVolumeIdentifier["volume-b"]?.lastEventID == 20)
        #expect(accepted.cursorByVolumeIdentifier["volume-b"]?.updatedAt == Date(timeIntervalSince1970: 210))
    }

    @Test("owned promotion marker is factual and collision safe")
    func ownedPromotionMarkerIsFactualAndCollisionSafe() throws {
        // Arrange
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)
        let repository = WorkspaceLocalRepository(workspaceId: UUIDv7.generate(), databaseWriter: databaseQueue)
        let stableKey = "cccccccccccccccc"
        let attemptID = UUIDv7.generate()
        _ = try repository.commitRepositoryLocalActivity(
            try RepositoryLocalActivityCommit(
                repositoryUpdates: [
                    .init(
                        repositoryStableKey: stableKey,
                        coverageChange: .restart(at: Date(timeIntervalSince1970: 100)),
                        ownedPromotionChange: .begin(
                            attemptID: attemptID,
                            startedAt: Date(timeIntervalSince1970: 110)
                        )
                    )
                ],
                updatedAt: Date(timeIntervalSince1970: 110)
            )
        )

        // Act / Assert
        #expect(throws: RepositoryLocalActivityPersistenceError.self) {
            _ = try repository.commitRepositoryLocalActivity(
                try RepositoryLocalActivityCommit(
                    repositoryUpdates: [
                        .init(
                            repositoryStableKey: stableKey,
                            ownedPromotionChange: .clear(expectedAttemptID: UUIDv7.generate())
                        )
                    ],
                    updatedAt: Date(timeIntervalSince1970: 120)
                )
            )
        }
        let unsettled = try repository.fetchRepositoryLocalActivitySnapshot()
        #expect(unsettled.activityByRepositoryStableKey[stableKey]?.ownedPromotionAttemptID == attemptID)
        #expect(unsettled.activityByRepositoryStableKey[stableKey]?.ownedPromotionUnsettled == true)

        let cleared = try repository.commitRepositoryLocalActivity(
            try RepositoryLocalActivityCommit(
                repositoryUpdates: [
                    .init(
                        repositoryStableKey: stableKey,
                        ownedPromotionChange: .clear(expectedAttemptID: attemptID)
                    )
                ],
                updatedAt: Date(timeIntervalSince1970: 130)
            )
        )
        #expect(cleared.activityByRepositoryStableKey[stableKey]?.ownedPromotionAttemptID == nil)
        #expect(cleared.activityByRepositoryStableKey[stableKey]?.ownedPromotionUnsettled == false)
    }
}

@MainActor
@Suite("Repository local activity store", .serialized)
struct RepositoryLocalActivityStoreTests {
    @Test("restart keeps persisted activity unknown until a live coverage checkpoint")
    func restartKeepsPersistedActivityUnknownUntilLiveCheckpoint() async throws {
        // Arrange
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: UUIDv7.generate())
        let datastore = try await preparedWorkspaceSQLiteDatastore(from: fixture.sqliteBackend)
        let stableKey = "cccccccccccccccc"
        let untouchedStableKey = "eeeeeeeeeeeeeeee"
        let seedingStore = RepositoryLocalActivityStore(
            atom: RepositoryLocalActivityAtom(),
            sqliteDatastore: datastore
        )
        _ = try await seedingStore.commitAsync(
            try RepositoryLocalActivityCommit(
                repositoryUpdates: [
                    .init(
                        repositoryStableKey: stableKey,
                        qualifyingActivityAt: Date(timeIntervalSince1970: 120),
                        coverageChange: .restart(at: Date(timeIntervalSince1970: 100))
                    ),
                    .init(
                        repositoryStableKey: untouchedStableKey,
                        qualifyingActivityAt: Date(timeIntervalSince1970: 110),
                        coverageChange: .restart(at: Date(timeIntervalSince1970: 90))
                    ),
                ],
                updatedAt: Date(timeIntervalSince1970: 130)
            )
        )
        let restartedAtom = RepositoryLocalActivityAtom()
        let restartedStore = RepositoryLocalActivityStore(
            atom: restartedAtom,
            sqliteDatastore: datastore
        )

        // Act
        await restartedStore.restoreAsync()

        // Assert
        #expect(restartedStore.isHydrated)
        #expect(restartedAtom.hydrationDisposition == .unavailable)
        #expect(restartedAtom.activity(for: stableKey) == nil)

        // A live checkpoint restarts coverage and returns authoritative facts.
        _ = try await restartedStore.commitAsync(
            try RepositoryLocalActivityCommit(
                repositoryUpdates: [
                    .init(
                        repositoryStableKey: stableKey,
                        coverageChange: .restart(at: Date(timeIntervalSince1970: 200))
                    )
                ],
                updatedAt: Date(timeIntervalSince1970: 210)
            )
        )
        #expect(restartedAtom.hydrationDisposition == .authoritative)
        #expect(
            restartedAtom.activity(for: stableKey)?.continuousCoverageStartedAt
                == Date(timeIntervalSince1970: 200)
        )
        #expect(restartedAtom.activity(for: untouchedStableKey) == nil)
    }

    @Test("publishes only the snapshot acknowledged by SQLite")
    func publishesOnlySnapshotAcknowledgedBySQLite() async throws {
        // Arrange
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: UUIDv7.generate())
        let datastore = try await preparedWorkspaceSQLiteDatastore(from: fixture.sqliteBackend)
        let atom = RepositoryLocalActivityAtom()
        let store = RepositoryLocalActivityStore(atom: atom, sqliteDatastore: datastore)
        let stableKey = "dddddddddddddddd"
        let acceptedCommit = try RepositoryLocalActivityCommit(
            repositoryUpdates: [
                .init(
                    repositoryStableKey: stableKey,
                    qualifyingActivityAt: Date(timeIntervalSince1970: 120),
                    coverageChange: .restart(at: Date(timeIntervalSince1970: 100))
                )
            ],
            updatedAt: Date(timeIntervalSince1970: 130)
        )
        _ = try await store.commitAsync(acceptedCommit)
        let acceptedActivity = atom.activity(for: stableKey)
        try await fixture.databaseQueue.write { database in
            try database.execute(
                sql: """
                    CREATE TRIGGER reject_store_activity_advance
                    BEFORE UPDATE ON local_repository_activity
                    BEGIN
                        SELECT RAISE(ABORT, 'reject store activity advance');
                    END
                    """
            )
        }

        // Act / Assert
        await #expect(throws: (any Error).self) {
            _ = try await store.commitAsync(
                try RepositoryLocalActivityCommit(
                    repositoryUpdates: [
                        .init(
                            repositoryStableKey: stableKey,
                            qualifyingActivityAt: Date(timeIntervalSince1970: 200)
                        )
                    ],
                    updatedAt: Date(timeIntervalSince1970: 210)
                )
            )
        }
        #expect(atom.activity(for: stableKey) == acceptedActivity)
    }

    @Test("unavailable local database remains unknown at the atom boundary")
    func unavailableLocalDatabaseRemainsUnknownAtAtomBoundary() async throws {
        // Arrange
        let coreDatabaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceCoreMigrations.migrate(coreDatabaseQueue)
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreDatabaseQueue)
        let datastore = try await preparedWorkspaceSQLiteDatastore(
            coreRepository: coreRepository,
            localUnavailable: .init(CocoaError(.fileNoSuchFile))
        )
        let atom = RepositoryLocalActivityAtom()
        let store = RepositoryLocalActivityStore(atom: atom, sqliteDatastore: datastore)

        // Act
        await store.restoreAsync()

        // Assert
        #expect(store.isHydrated)
        #expect(atom.hydrationDisposition == .unavailable)
        #expect(atom.snapshot().isEmpty)
    }
}
