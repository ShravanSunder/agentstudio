import Foundation
import GRDB

package enum RepositoryLocalActivityPersistenceError: Error, Equatable {
    case missingCoverageForNewRepository
    case ownedPromotionAttemptMismatch
    case eventIDExceedsSQLiteRange
    case invalidPersistedEventID
}

extension WorkspaceLocalRepository {
    func commitRepositoryLocalActivity(
        _ commit: RepositoryLocalActivityCommit
    ) throws -> RepositoryLocalActivitySnapshot {
        try databaseWriter.write { database in
            for update in commit.repositoryUpdates {
                try Self.applyRepositoryLocalActivityUpdate(update, commitUpdatedAt: commit.updatedAt, in: database)
            }
            for cursor in commit.cursorWatermarks {
                try Self.applyRepositoryLocalActivityCursor(cursor, in: database)
            }
            return try Self.fetchRepositoryLocalActivitySnapshot(in: database)
        }
    }

    func fetchRepositoryLocalActivitySnapshot() throws -> RepositoryLocalActivitySnapshot {
        try databaseWriter.read { database in
            try Self.fetchRepositoryLocalActivitySnapshot(in: database)
        }
    }

    private static func applyRepositoryLocalActivityUpdate(
        _ update: RepositoryLocalActivityUpdate,
        commitUpdatedAt: Date,
        in database: Database
    ) throws {
        var activity = try fetchRepositoryLocalActivity(
            repositoryStableKey: update.repositoryStableKey,
            in: database
        )
        if activity == nil {
            guard case .restart(let coverageStartedAt) = update.coverageChange else {
                throw RepositoryLocalActivityPersistenceError.missingCoverageForNewRepository
            }
            let ownedPromotion = try resolvedOwnedPromotion(
                current: nil,
                change: update.ownedPromotionChange
            )
            activity = try RepositoryLocalActivity(
                repositoryStableKey: update.repositoryStableKey,
                lastQualifyingActivityAt: update.qualifyingActivityAt,
                continuousCoverageStartedAt: coverageStartedAt,
                updatedAt: commitUpdatedAt,
                ownedPromotionAttemptID: ownedPromotion.attemptID,
                ownedPromotionStartedAt: ownedPromotion.startedAt,
                ownedPromotionUnsettled: ownedPromotion.isUnsettled
            )
            try insertRepositoryLocalActivity(try activity.requireValue(), in: database)
            return
        }

        let current = try activity.requireValue()
        let acceptedQualifyingActivityAt = maxDate(
            current.lastQualifyingActivityAt,
            update.qualifyingActivityAt
        )
        let acceptedCoverageStartedAt: Date =
            switch update.coverageChange {
            case .unchanged:
                current.continuousCoverageStartedAt
            case .restart(let restartedAt):
                restartedAt
            }
        let ownedPromotion = try resolvedOwnedPromotion(
            current: current,
            change: update.ownedPromotionChange
        )
        let hasChanged =
            acceptedQualifyingActivityAt != current.lastQualifyingActivityAt
            || acceptedCoverageStartedAt != current.continuousCoverageStartedAt
            || ownedPromotion.attemptID != current.ownedPromotionAttemptID
            || ownedPromotion.startedAt != current.ownedPromotionStartedAt
            || ownedPromotion.isUnsettled != current.ownedPromotionUnsettled
        guard hasChanged else { return }

        let replacement = try RepositoryLocalActivity(
            repositoryStableKey: current.repositoryStableKey,
            lastQualifyingActivityAt: acceptedQualifyingActivityAt,
            continuousCoverageStartedAt: acceptedCoverageStartedAt,
            updatedAt: commitUpdatedAt,
            ownedPromotionAttemptID: ownedPromotion.attemptID,
            ownedPromotionStartedAt: ownedPromotion.startedAt,
            ownedPromotionUnsettled: ownedPromotion.isUnsettled
        )
        try insertRepositoryLocalActivity(replacement, in: database)
    }

    private static func applyRepositoryLocalActivityCursor(
        _ cursor: RepositoryLocalActivityCursor,
        in database: Database
    ) throws {
        guard cursor.lastEventID <= UInt64(Int64.max) else {
            throw RepositoryLocalActivityPersistenceError.eventIDExceedsSQLiteRange
        }
        if let current = try fetchRepositoryLocalActivityCursor(
            volumeIdentifier: cursor.volumeIdentifier,
            in: database
        ), current.lastEventID >= cursor.lastEventID {
            return
        }
        try database.execute(
            sql: """
                INSERT INTO local_repository_activity_cursor(volume_identifier, last_event_id, updated_at)
                VALUES (?, ?, ?)
                ON CONFLICT(volume_identifier) DO UPDATE SET
                    last_event_id = excluded.last_event_id,
                    updated_at = excluded.updated_at
                """,
            arguments: [
                cursor.volumeIdentifier,
                Int64(cursor.lastEventID),
                cursor.updatedAt.timeIntervalSince1970,
            ]
        )
    }

    private static func fetchRepositoryLocalActivitySnapshot(
        in database: Database
    ) throws -> RepositoryLocalActivitySnapshot {
        let activities = try Row.fetchAll(
            database,
            sql: """
                SELECT repository_stable_key, last_qualifying_activity_at,
                       continuous_coverage_started_at, updated_at,
                       owned_promotion_attempt_id, owned_promotion_started_at,
                       owned_promotion_unsettled
                FROM local_repository_activity
                ORDER BY repository_stable_key
                """
        ).map(decodeRepositoryLocalActivity)
        let cursors = try Row.fetchAll(
            database,
            sql: """
                SELECT volume_identifier, last_event_id, updated_at
                FROM local_repository_activity_cursor
                ORDER BY volume_identifier
                """
        ).map(decodeRepositoryLocalActivityCursor)
        return RepositoryLocalActivitySnapshot(
            activityByRepositoryStableKey: Dictionary(
                uniqueKeysWithValues: activities.map { ($0.repositoryStableKey, $0) }
            ),
            cursorByVolumeIdentifier: Dictionary(
                uniqueKeysWithValues: cursors.map { ($0.volumeIdentifier, $0) }
            )
        )
    }

    private static func fetchRepositoryLocalActivity(
        repositoryStableKey: String,
        in database: Database
    ) throws -> RepositoryLocalActivity? {
        try Row.fetchOne(
            database,
            sql: """
                SELECT repository_stable_key, last_qualifying_activity_at,
                       continuous_coverage_started_at, updated_at,
                       owned_promotion_attempt_id, owned_promotion_started_at,
                       owned_promotion_unsettled
                FROM local_repository_activity
                WHERE repository_stable_key = ?
                """,
            arguments: [repositoryStableKey]
        ).map(decodeRepositoryLocalActivity)
    }

    private static func fetchRepositoryLocalActivityCursor(
        volumeIdentifier: String,
        in database: Database
    ) throws -> RepositoryLocalActivityCursor? {
        try Row.fetchOne(
            database,
            sql: """
                SELECT volume_identifier, last_event_id, updated_at
                FROM local_repository_activity_cursor
                WHERE volume_identifier = ?
                """,
            arguments: [volumeIdentifier]
        ).map(decodeRepositoryLocalActivityCursor)
    }

    private static func insertRepositoryLocalActivity(
        _ activity: RepositoryLocalActivity,
        in database: Database
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO local_repository_activity(
                    repository_stable_key, last_qualifying_activity_at,
                    continuous_coverage_started_at, updated_at,
                    owned_promotion_attempt_id, owned_promotion_started_at,
                    owned_promotion_unsettled
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(repository_stable_key) DO UPDATE SET
                    last_qualifying_activity_at = excluded.last_qualifying_activity_at,
                    continuous_coverage_started_at = excluded.continuous_coverage_started_at,
                    updated_at = excluded.updated_at,
                    owned_promotion_attempt_id = excluded.owned_promotion_attempt_id,
                    owned_promotion_started_at = excluded.owned_promotion_started_at,
                    owned_promotion_unsettled = excluded.owned_promotion_unsettled
                """,
            arguments: [
                activity.repositoryStableKey,
                activity.lastQualifyingActivityAt?.timeIntervalSince1970,
                activity.continuousCoverageStartedAt.timeIntervalSince1970,
                activity.updatedAt.timeIntervalSince1970,
                activity.ownedPromotionAttemptID?.uuidString,
                activity.ownedPromotionStartedAt?.timeIntervalSince1970,
                activity.ownedPromotionUnsettled ? 1 : 0,
            ]
        )
    }

    private static func decodeRepositoryLocalActivity(_ row: Row) throws -> RepositoryLocalActivity {
        let attemptIDString: String? = row["owned_promotion_attempt_id"]
        let attemptID = try attemptIDString.map { value in
            guard let attemptID = UUID(uuidString: value), attemptID.uuidString == value else {
                throw RepositoryLocalActivityValidationError.invalidOwnedPromotion
            }
            return attemptID
        }
        let lastQualifyingActivityTimestamp: Double? = row["last_qualifying_activity_at"]
        let ownedPromotionStartedTimestamp: Double? = row["owned_promotion_started_at"]
        return try RepositoryLocalActivity(
            repositoryStableKey: row["repository_stable_key"],
            lastQualifyingActivityAt: lastQualifyingActivityTimestamp.map(Date.init(timeIntervalSince1970:)),
            continuousCoverageStartedAt: Date(
                timeIntervalSince1970: row["continuous_coverage_started_at"] as Double
            ),
            updatedAt: Date(timeIntervalSince1970: row["updated_at"] as Double),
            ownedPromotionAttemptID: attemptID,
            ownedPromotionStartedAt: ownedPromotionStartedTimestamp.map(Date.init(timeIntervalSince1970:)),
            ownedPromotionUnsettled: (row["owned_promotion_unsettled"] as Int) == 1
        )
    }

    private static func decodeRepositoryLocalActivityCursor(_ row: Row) throws -> RepositoryLocalActivityCursor {
        let signedEventID: Int64 = row["last_event_id"]
        guard signedEventID >= 0 else {
            throw RepositoryLocalActivityPersistenceError.invalidPersistedEventID
        }
        return try RepositoryLocalActivityCursor(
            volumeIdentifier: row["volume_identifier"],
            lastEventID: UInt64(signedEventID),
            updatedAt: Date(timeIntervalSince1970: row["updated_at"] as Double)
        )
    }

    private static func resolvedOwnedPromotion(
        current: RepositoryLocalActivity?,
        change: RepositoryLocalActivityOwnedPromotionChange
    ) throws -> (attemptID: UUID?, startedAt: Date?, isUnsettled: Bool) {
        switch change {
        case .unchanged:
            return (
                current?.ownedPromotionAttemptID,
                current?.ownedPromotionStartedAt,
                current?.ownedPromotionUnsettled ?? false
            )
        case .begin(let attemptID, let startedAt):
            return (attemptID, startedAt, true)
        case .clear(let expectedAttemptID):
            guard
                current?.ownedPromotionUnsettled == true,
                current?.ownedPromotionAttemptID == expectedAttemptID
            else {
                throw RepositoryLocalActivityPersistenceError.ownedPromotionAttemptMismatch
            }
            return (nil, nil, false)
        }
    }

    private static func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case (.none, .none): nil
        case (.some(let date), .none), (.none, .some(let date)): date
        case (.some(let lhs), .some(let rhs)): max(lhs, rhs)
        }
    }
}

extension Optional {
    fileprivate func requireValue() throws -> Wrapped {
        guard let self else {
            throw RepositoryLocalActivityPersistenceError.missingCoverageForNewRepository
        }
        return self
    }
}
