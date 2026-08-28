import Foundation

package enum RepositoryLocalActivityValidationError: Error, Equatable {
    case invalidRepositoryStableKey
    case invalidVolumeIdentifier
    case invalidTimestamp
    case invalidOwnedPromotion
    case duplicateRepositoryUpdate
    case duplicateVolumeCursor
}

package struct RepositoryLocalActivity: Hashable, Sendable {
    package let repositoryStableKey: String
    package let lastQualifyingActivityAt: Date?
    package let continuousCoverageStartedAt: Date
    package let updatedAt: Date
    package let ownedPromotionAttemptID: UUID?
    package let ownedPromotionStartedAt: Date?
    package let ownedPromotionUnsettled: Bool

    package init(
        repositoryStableKey: String,
        lastQualifyingActivityAt: Date?,
        continuousCoverageStartedAt: Date,
        updatedAt: Date,
        ownedPromotionAttemptID: UUID?,
        ownedPromotionStartedAt: Date?,
        ownedPromotionUnsettled: Bool
    ) throws {
        try RepositoryLocalActivityValidation.validateStableKey(repositoryStableKey)
        try RepositoryLocalActivityValidation.validateOptionalTimestamp(lastQualifyingActivityAt)
        try RepositoryLocalActivityValidation.validateTimestamp(continuousCoverageStartedAt)
        try RepositoryLocalActivityValidation.validateTimestamp(updatedAt)
        try RepositoryLocalActivityValidation.validateOptionalTimestamp(ownedPromotionStartedAt)
        guard
            ownedPromotionUnsettled
                ? (ownedPromotionAttemptID != nil && ownedPromotionStartedAt != nil)
                : (ownedPromotionAttemptID == nil && ownedPromotionStartedAt == nil)
        else {
            throw RepositoryLocalActivityValidationError.invalidOwnedPromotion
        }
        self.repositoryStableKey = repositoryStableKey
        self.lastQualifyingActivityAt = lastQualifyingActivityAt
        self.continuousCoverageStartedAt = continuousCoverageStartedAt
        self.updatedAt = updatedAt
        self.ownedPromotionAttemptID = ownedPromotionAttemptID
        self.ownedPromotionStartedAt = ownedPromotionStartedAt
        self.ownedPromotionUnsettled = ownedPromotionUnsettled
    }
}

package struct RepositoryLocalActivityCursor: Hashable, Sendable {
    package let volumeIdentifier: String
    package let lastEventID: UInt64
    package let updatedAt: Date

    package init(volumeIdentifier: String, lastEventID: UInt64, updatedAt: Date) throws {
        guard !volumeIdentifier.isEmpty else {
            throw RepositoryLocalActivityValidationError.invalidVolumeIdentifier
        }
        try RepositoryLocalActivityValidation.validateTimestamp(updatedAt)
        self.volumeIdentifier = volumeIdentifier
        self.lastEventID = lastEventID
        self.updatedAt = updatedAt
    }
}

package struct RepositoryLocalActivitySnapshot: Equatable, Sendable {
    package let activityByRepositoryStableKey: [String: RepositoryLocalActivity]
    package let cursorByVolumeIdentifier: [String: RepositoryLocalActivityCursor]

    package static let empty = Self(
        activityByRepositoryStableKey: [:],
        cursorByVolumeIdentifier: [:]
    )

    package init(
        activityByRepositoryStableKey: [String: RepositoryLocalActivity],
        cursorByVolumeIdentifier: [String: RepositoryLocalActivityCursor]
    ) {
        self.activityByRepositoryStableKey = activityByRepositoryStableKey
        self.cursorByVolumeIdentifier = cursorByVolumeIdentifier
    }
}

package enum RepositoryLocalActivityCoverageChange: Equatable, Sendable {
    case unchanged
    case restart(at: Date)
}

package enum RepositoryLocalActivityOwnedPromotionChange: Equatable, Sendable {
    case unchanged
    case begin(attemptID: UUID, startedAt: Date)
    case clear(expectedAttemptID: UUID)
}

package struct RepositoryLocalActivityUpdate: Equatable, Sendable {
    package let repositoryStableKey: String
    package let qualifyingActivityAt: Date?
    package let coverageChange: RepositoryLocalActivityCoverageChange
    package let ownedPromotionChange: RepositoryLocalActivityOwnedPromotionChange

    package init(
        repositoryStableKey: String,
        qualifyingActivityAt: Date? = nil,
        coverageChange: RepositoryLocalActivityCoverageChange = .unchanged,
        ownedPromotionChange: RepositoryLocalActivityOwnedPromotionChange = .unchanged
    ) {
        self.repositoryStableKey = repositoryStableKey
        self.qualifyingActivityAt = qualifyingActivityAt
        self.coverageChange = coverageChange
        self.ownedPromotionChange = ownedPromotionChange
    }
}

package struct RepositoryLocalActivityCommit: Equatable, Sendable {
    package let repositoryUpdates: [RepositoryLocalActivityUpdate]
    package let cursorWatermarks: [RepositoryLocalActivityCursor]
    package let updatedAt: Date

    package init(
        repositoryUpdates: [RepositoryLocalActivityUpdate],
        cursorWatermarks: [RepositoryLocalActivityCursor] = [],
        updatedAt: Date
    ) throws {
        try RepositoryLocalActivityValidation.validateTimestamp(updatedAt)
        var repositoryStableKeys = Set<String>()
        for update in repositoryUpdates {
            try RepositoryLocalActivityValidation.validateStableKey(update.repositoryStableKey)
            try RepositoryLocalActivityValidation.validateOptionalTimestamp(update.qualifyingActivityAt)
            switch update.coverageChange {
            case .unchanged:
                break
            case .restart(let timestamp):
                try RepositoryLocalActivityValidation.validateTimestamp(timestamp)
            }
            switch update.ownedPromotionChange {
            case .unchanged, .clear:
                break
            case .begin(_, let startedAt):
                try RepositoryLocalActivityValidation.validateTimestamp(startedAt)
            }
            guard repositoryStableKeys.insert(update.repositoryStableKey).inserted else {
                throw RepositoryLocalActivityValidationError.duplicateRepositoryUpdate
            }
        }
        guard Set(cursorWatermarks.map(\.volumeIdentifier)).count == cursorWatermarks.count else {
            throw RepositoryLocalActivityValidationError.duplicateVolumeCursor
        }
        self.repositoryUpdates = repositoryUpdates
        self.cursorWatermarks = cursorWatermarks
        self.updatedAt = updatedAt
    }
}

enum RepositoryLocalActivityValidation {
    static func validateStableKey(_ stableKey: String) throws {
        guard
            stableKey.count == 16,
            stableKey.utf8.allSatisfy({ byte in
                (byte >= Character("0").asciiValue! && byte <= Character("9").asciiValue!)
                    || (byte >= Character("a").asciiValue! && byte <= Character("f").asciiValue!)
            })
        else {
            throw RepositoryLocalActivityValidationError.invalidRepositoryStableKey
        }
    }

    static func validateTimestamp(_ timestamp: Date) throws {
        guard timestamp.timeIntervalSince1970.isFinite else {
            throw RepositoryLocalActivityValidationError.invalidTimestamp
        }
    }

    static func validateOptionalTimestamp(_ timestamp: Date?) throws {
        if let timestamp { try validateTimestamp(timestamp) }
    }
}
