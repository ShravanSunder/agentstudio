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
    package let hydrationDisposition: ApplicationEntityRecencyHydrationDisposition
    package let repositories: [RepositoryActivityTopology]
    package let openWorktreeIDs: Set<UUID>
    package let recency: [ApplicationEntityRecency]
    package let referenceDate: Date
    package let inactivityHorizon: TimeInterval

    package init(
        hydrationDisposition: ApplicationEntityRecencyHydrationDisposition,
        repositories: [RepositoryActivityTopology],
        openWorktreeIDs: Set<UUID>,
        recency: [ApplicationEntityRecency],
        referenceDate: Date,
        inactivityHorizon: TimeInterval
    ) {
        self.hydrationDisposition = hydrationDisposition
        self.repositories = repositories
        self.openWorktreeIDs = openWorktreeIDs
        self.recency = recency
        self.referenceDate = referenceDate
        self.inactivityHorizon = inactivityHorizon
    }
}

package struct RepositoryActivityClassification: Equatable, Sendable {
    package let dispositionByRepositoryID: [UUID: RepositoryActivityDisposition]
    package let warmRepositoryIDs: Set<UUID>
    package let locallyInactiveRepositoryIDs: Set<UUID>
    package let warmWorktreeIDs: Set<UUID>
    package let locallyInactiveWorktreeIDs: Set<UUID>
    package let nextTransitionAt: Date?
}

package enum RepositoryActivityClassifier {
    package static func classify(
        _ input: RepositoryActivityClassificationInput
    ) -> RepositoryActivityClassification {
        guard input.hydrationDisposition == .authoritative else {
            return RepositoryActivityClassification(
                dispositionByRepositoryID: Dictionary(
                    uniqueKeysWithValues: input.repositories.map { ($0.repositoryID, .unclassified) }
                ),
                warmRepositoryIDs: [],
                locallyInactiveRepositoryIDs: [],
                warmWorktreeIDs: [],
                locallyInactiveWorktreeIDs: [],
                nextTransitionAt: nil
            )
        }

        let recencyByEntity = Dictionary(
            input.recency.map { ($0.entity, $0.lastInteractedAt) },
            uniquingKeysWith: max
        )
        var dispositionByRepositoryID: [UUID: RepositoryActivityDisposition] = [:]
        var warmRepositoryIDs = Set<UUID>()
        var locallyInactiveRepositoryIDs = Set<UUID>()
        var warmWorktreeIDs = Set<UUID>()
        var locallyInactiveWorktreeIDs = Set<UUID>()
        var nextTransitionAt: Date?

        for repository in input.repositories {
            let worktreeIDs = Set(repository.worktreeStableKeysByID.keys)
            if !worktreeIDs.isDisjoint(with: input.openWorktreeIDs) {
                dispositionByRepositoryID[repository.repositoryID] = .warm
                warmRepositoryIDs.insert(repository.repositoryID)
                warmWorktreeIDs.formUnion(worktreeIDs)
                continue
            }

            let repositoryRecency = recencyByEntity[
                .repository(repositoryStableKey: repository.repositoryStableKey)
            ]
            let latestWorktreeRecency = repository.worktreeStableKeysByID.values.compactMap { stableKey in
                recencyByEntity[.worktree(worktreeStableKey: stableKey)]
            }.max()
            let latestRecency = [repositoryRecency, latestWorktreeRecency].compactMap { $0 }.max()

            guard let latestRecency else {
                dispositionByRepositoryID[repository.repositoryID] = .locallyInactive
                locallyInactiveRepositoryIDs.insert(repository.repositoryID)
                locallyInactiveWorktreeIDs.formUnion(worktreeIDs)
                continue
            }

            let expiration = latestRecency.addingTimeInterval(input.inactivityHorizon)
            if input.referenceDate <= expiration {
                dispositionByRepositoryID[repository.repositoryID] = .warm
                warmRepositoryIDs.insert(repository.repositoryID)
                warmWorktreeIDs.formUnion(worktreeIDs)
                let transitionAt = Date(
                    timeIntervalSinceReferenceDate: expiration.timeIntervalSinceReferenceDate.nextUp
                )
                nextTransitionAt = min(nextTransitionAt ?? transitionAt, transitionAt)
            } else {
                dispositionByRepositoryID[repository.repositoryID] = .locallyInactive
                locallyInactiveRepositoryIDs.insert(repository.repositoryID)
                locallyInactiveWorktreeIDs.formUnion(worktreeIDs)
            }
        }

        return RepositoryActivityClassification(
            dispositionByRepositoryID: dispositionByRepositoryID,
            warmRepositoryIDs: warmRepositoryIDs,
            locallyInactiveRepositoryIDs: locallyInactiveRepositoryIDs,
            warmWorktreeIDs: warmWorktreeIDs,
            locallyInactiveWorktreeIDs: locallyInactiveWorktreeIDs,
            nextTransitionAt: nextTransitionAt
        )
    }
}
