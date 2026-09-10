import Foundation

package enum ApplicationEntityRecencyHydrationDisposition: Equatable, Sendable {
    case pending
    case authoritative
}

package enum RepositoryActivityDisposition: Equatable, Sendable {
    case unclassified
    case warm
    case locallyInactive
}

package struct RepositoryActivityTopology: Equatable, Sendable {
    package let repositoryID: UUID
    package let repositoryStableKey: String
    package let worktreeStableKeysByID: [UUID: String]

    package init(
        repositoryID: UUID,
        repositoryStableKey: String,
        worktreeStableKeysByID: [UUID: String]
    ) {
        self.repositoryID = repositoryID
        self.repositoryStableKey = repositoryStableKey
        self.worktreeStableKeysByID = worktreeStableKeysByID
    }
}

package struct RepositoryActivityClassificationInput: Equatable, Sendable {
    package let repositories: [RepositoryActivityTopology]
    package let openWorktreeIDs: Set<UUID>
    package let localActivityHydrationDisposition: RepositoryLocalActivityHydrationDisposition
    package let repositoryLocalActivityByStableKey: [String: RepositoryLocalActivity]
    package let referenceDate: Date
    package let inactivityHorizon: TimeInterval

    package init(
        repositories: [RepositoryActivityTopology],
        openWorktreeIDs: Set<UUID>,
        localActivityHydrationDisposition: RepositoryLocalActivityHydrationDisposition = .pending,
        repositoryLocalActivityByStableKey: [String: RepositoryLocalActivity] = [:],
        referenceDate: Date,
        inactivityHorizon: TimeInterval
    ) {
        self.repositories = repositories
        self.openWorktreeIDs = openWorktreeIDs
        self.localActivityHydrationDisposition = localActivityHydrationDisposition
        self.repositoryLocalActivityByStableKey = repositoryLocalActivityByStableKey
        self.referenceDate = referenceDate
        self.inactivityHorizon = inactivityHorizon
    }
}

package struct RepositoryActivityClassification: Equatable, Sendable {
    package let dispositionByRepositoryID: [UUID: RepositoryActivityDisposition]
    package let warmRepositoryIDs: Set<UUID>
    package let unknownRepositoryIDs: Set<UUID>
    package let locallyInactiveRepositoryIDs: Set<UUID>
    package let warmWorktreeIDs: Set<UUID>
    package let unknownWorktreeIDs: Set<UUID>
    package let locallyInactiveWorktreeIDs: Set<UUID>
    package let transitionAtByRepositoryID: [UUID: Date]

    package var nextTransitionAt: Date? {
        transitionAtByRepositoryID.values.min()
    }
}

package enum RepositoryActivityClassifier {
    package static func classify(
        _ input: RepositoryActivityClassificationInput
    ) -> RepositoryActivityClassification {
        var dispositionByRepositoryID: [UUID: RepositoryActivityDisposition] = [:]
        var warmRepositoryIDs = Set<UUID>()
        var unknownRepositoryIDs = Set<UUID>()
        var locallyInactiveRepositoryIDs = Set<UUID>()
        var warmWorktreeIDs = Set<UUID>()
        var unknownWorktreeIDs = Set<UUID>()
        var locallyInactiveWorktreeIDs = Set<UUID>()
        var transitionAtByRepositoryID: [UUID: Date] = [:]

        for repository in input.repositories {
            let worktreeIDs = Set(repository.worktreeStableKeysByID.keys)
            if !worktreeIDs.isDisjoint(with: input.openWorktreeIDs) {
                dispositionByRepositoryID[repository.repositoryID] = .warm
                warmRepositoryIDs.insert(repository.repositoryID)
                warmWorktreeIDs.formUnion(worktreeIDs)
                continue
            }

            guard input.localActivityHydrationDisposition == .authoritative,
                let activity = input.repositoryLocalActivityByStableKey[repository.repositoryStableKey],
                !activity.ownedPromotionUnsettled,
                activity.continuousCoverageStartedAt <= input.referenceDate,
                activity.updatedAt <= input.referenceDate,
                activity.lastQualifyingActivityAt.map({ $0 <= input.referenceDate }) ?? true
            else {
                dispositionByRepositoryID[repository.repositoryID] = .unclassified
                unknownRepositoryIDs.insert(repository.repositoryID)
                unknownWorktreeIDs.formUnion(worktreeIDs)
                continue
            }

            if let lastQualifyingActivityAt = activity.lastQualifyingActivityAt,
                input.referenceDate
                    <= lastQualifyingActivityAt.addingTimeInterval(input.inactivityHorizon)
            {
                dispositionByRepositoryID[repository.repositoryID] = .warm
                warmRepositoryIDs.insert(repository.repositoryID)
                warmWorktreeIDs.formUnion(worktreeIDs)
                let transitionAt = nextTransitionDate(
                    after: lastQualifyingActivityAt,
                    horizon: input.inactivityHorizon
                )
                transitionAtByRepositoryID[repository.repositoryID] = transitionAt
                continue
            }

            if input.referenceDate
                <= activity.continuousCoverageStartedAt.addingTimeInterval(input.inactivityHorizon)
            {
                dispositionByRepositoryID[repository.repositoryID] = .unclassified
                unknownRepositoryIDs.insert(repository.repositoryID)
                unknownWorktreeIDs.formUnion(worktreeIDs)
                let transitionAt = nextTransitionDate(
                    after: activity.continuousCoverageStartedAt,
                    horizon: input.inactivityHorizon
                )
                transitionAtByRepositoryID[repository.repositoryID] = transitionAt
            } else {
                dispositionByRepositoryID[repository.repositoryID] = .locallyInactive
                locallyInactiveRepositoryIDs.insert(repository.repositoryID)
                locallyInactiveWorktreeIDs.formUnion(worktreeIDs)
            }
        }

        return RepositoryActivityClassification(
            dispositionByRepositoryID: dispositionByRepositoryID,
            warmRepositoryIDs: warmRepositoryIDs,
            unknownRepositoryIDs: unknownRepositoryIDs,
            locallyInactiveRepositoryIDs: locallyInactiveRepositoryIDs,
            warmWorktreeIDs: warmWorktreeIDs,
            unknownWorktreeIDs: unknownWorktreeIDs,
            locallyInactiveWorktreeIDs: locallyInactiveWorktreeIDs,
            transitionAtByRepositoryID: transitionAtByRepositoryID
        )
    }

    private static func nextTransitionDate(after boundary: Date, horizon: TimeInterval) -> Date {
        let expiration = boundary.addingTimeInterval(horizon)
        return Date(
            timeIntervalSinceReferenceDate: expiration.timeIntervalSinceReferenceDate.nextUp
        )
    }
}
