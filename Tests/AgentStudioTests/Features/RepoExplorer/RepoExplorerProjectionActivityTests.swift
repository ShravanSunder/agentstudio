import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

extension RepoExplorerProjectionWorkerTests {
    @Test("repository activity delta updates one deadline and preserves unrelated result facts")
    func repositoryActivityDeltaPreservesUnrelatedResultFacts() throws {
        let referenceDate = Date(timeIntervalSince1970: 10_000_000)
        let firstRepository = repo(
            id: UUIDv7.generate(),
            name: "first",
            stableKey: "1111111111111111"
        )
        let secondRepository = repo(
            id: UUIDv7.generate(),
            name: "second",
            stableKey: "2222222222222222"
        )
        let firstActivity = try RepositoryLocalActivity(
            repositoryStableKey: firstRepository.stableKey,
            lastQualifyingActivityAt: referenceDate.addingTimeInterval(-200),
            continuousCoverageStartedAt: referenceDate.addingTimeInterval(
                -AppPolicies.EntityRecency.applicationActivityHorizon - 1
            ),
            updatedAt: referenceDate,
            ownedPromotionAttemptID: nil,
            ownedPromotionStartedAt: nil,
            ownedPromotionUnsettled: false
        )
        let secondActivity = try RepositoryLocalActivity(
            repositoryStableKey: secondRepository.stableKey,
            lastQualifyingActivityAt: referenceDate.addingTimeInterval(-100),
            continuousCoverageStartedAt: referenceDate.addingTimeInterval(
                -AppPolicies.EntityRecency.applicationActivityHorizon - 1
            ),
            updatedAt: referenceDate,
            ownedPromotionAttemptID: nil,
            ownedPromotionStartedAt: nil,
            ownedPromotionUnsettled: false
        )
        let refreshedFirstActivity = try RepositoryLocalActivity(
            repositoryStableKey: firstRepository.stableKey,
            lastQualifyingActivityAt: referenceDate,
            continuousCoverageStartedAt: firstActivity.continuousCoverageStartedAt,
            updatedAt: referenceDate,
            ownedPromotionAttemptID: nil,
            ownedPromotionStartedAt: nil,
            ownedPromotionUnsettled: false
        )
        let initialRequest = request(
            repos: [firstRepository, secondRepository],
            generation: 1,
            localActivityHydrationDisposition: .authoritative,
            repositoryLocalActivityByStableKey: [
                firstRepository.stableKey: firstActivity,
                secondRepository.stableKey: secondActivity,
            ],
            activityReferenceDate: referenceDate
        )
        let updatedRequest = request(
            repos: [firstRepository, secondRepository],
            generation: 2,
            localActivityHydrationDisposition: .authoritative,
            repositoryLocalActivityByStableKey: [
                firstRepository.stableKey: refreshedFirstActivity,
                secondRepository.stableKey: secondActivity,
            ],
            activityReferenceDate: referenceDate
        )
        let initial = try RepoExplorerProjectionWorker.project(initialRequest)
        let secondRows = initial.materializationSnapshot
            .rowIDsByRepoID[secondRepository.id, default: []]
            .compactMap(initial.materializationSnapshot.row(id:))

        let scoped = try #require(
            RepoExplorerProjectionWorker.applyScopedChange(
                .repositoryActivity(firstRepository.id),
                request: updatedRequest,
                previous: initial
            )
        )

        #expect(scoped.repositoryActivityDispositionByRepoId[firstRepository.id] == .warm)
        #expect(
            scoped.repositoryActivityDispositionByRepoId[secondRepository.id]
                == initial.repositoryActivityDispositionByRepoId[secondRepository.id]
        )
        #expect(
            scoped.repositoryActivityTransitionAtByRepoId[firstRepository.id]
                != initial.repositoryActivityTransitionAtByRepoId[firstRepository.id]
        )
        #expect(
            scoped.repositoryActivityTransitionAtByRepoId[secondRepository.id]
                == initial.repositoryActivityTransitionAtByRepoId[secondRepository.id]
        )
        #expect(
            scoped.nextRepositoryActivityTransitionAt
                == scoped.repositoryActivityTransitionAtByRepoId[secondRepository.id]
        )
        #expect(scoped.projection == initial.projection)
        #expect(scoped.rowIndex == initial.rowIndex)
        #expect(scoped.branchStatusByWorktreeId == initial.branchStatusByWorktreeId)
        #expect(
            scoped.materializationSnapshot
                .rowIDsByRepoID[secondRepository.id, default: []]
                .compactMap(scoped.materializationSnapshot.row(id:)) == secondRows
        )
    }

    @Test("authoritative activity classifies inactive and updating repositories off-main")
    func authoritativeActivityClassifiesInactiveAndUpdatingRepositories() throws {
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()
        let repository = repo(
            id: repoId,
            worktreeId: worktreeId,
            name: "agent-studio",
            stableKey: "1111111111111111"
        )
        let attemptId = UUIDv7.generate()
        let referenceDate = Date(timeIntervalSince1970: 10_000_000)
        let inactiveActivity = try RepositoryLocalActivity(
            repositoryStableKey: repository.stableKey,
            lastQualifyingActivityAt: nil,
            continuousCoverageStartedAt: referenceDate.addingTimeInterval(
                -AppPolicies.EntityRecency.applicationActivityHorizon - 1
            ),
            updatedAt: referenceDate,
            ownedPromotionAttemptID: nil,
            ownedPromotionStartedAt: nil,
            ownedPromotionUnsettled: false
        )
        let inactiveRequest = request(
            repos: [repository],
            generation: 1,
            localActivityHydrationDisposition: .authoritative,
            repositoryLocalActivityByStableKey: [repository.stableKey: inactiveActivity],
            repositoryFactUpdateProgressByRepoId: [:]
        )
        let updatingRequest = request(
            repos: [repository],
            generation: 2,
            localActivityHydrationDisposition: .authoritative,
            repositoryLocalActivityByStableKey: [repository.stableKey: inactiveActivity],
            repositoryFactUpdateProgressByRepoId: [
                repoId: .captured(repoId: repoId, attemptId: attemptId)
            ]
        )

        let inactive = try RepoExplorerProjectionWorker.project(inactiveRequest)
        let updating = try RepoExplorerProjectionWorker.project(updatingRequest)

        #expect(inactive.repositoryActivityDispositionByRepoId[repoId] == .locallyInactive)
        #expect(updating.repositoryActivityDispositionByRepoId[repoId] == .locallyInactive)
        let inactiveHeader = try #require(inactive.materializationSnapshot.groupHeader(repoID: repoId))
        let updatingHeader = try #require(updating.materializationSnapshot.groupHeader(repoID: repoId))
        #expect(inactiveHeader.repositoryActivityDisposition == .locallyInactive)
        #expect(inactiveHeader.repositoryFactUpdateProgress == nil)
        #expect(updatingHeader.repositoryFactUpdateProgress?.phase == .captured)
        #expect(inactiveHeader.groupID == updatingHeader.groupID)
        #expect(
            inactive.materializationSnapshot.rowIDsByRepoID[repoId]
                == updating.materializationSnapshot.rowIDsByRepoID[repoId]
        )
        #expect(
            inactive.materializationSnapshot.fallbackContentHeight
                == updating.materializationSnapshot.fallbackContentHeight)
    }

    @Test("pre-hydration activity remains unclassified and never claims local inactivity")
    func preHydrationActivityRemainsUnclassified() throws {
        let repoId = UUIDv7.generate()
        let result = try RepoExplorerProjectionWorker.project(
            request(
                repos: [repo(id: repoId, name: "agent-studio")],
                generation: 1,
                localActivityHydrationDisposition: .pending
            )
        )

        #expect(result.repositoryActivityDispositionByRepoId[repoId] == .unclassified)
        #expect(
            result.materializationSnapshot.groupHeader(repoID: repoId)?.repositoryActivityDisposition == .unclassified)
    }

    @Test("warm repository publishes its exact activity cutoff and reclassifies after it")
    func warmRepositoryPublishesCutoffAndReclassifiesAfterIt() throws {
        let repositoryWithoutStableKeys = repo(
            id: UUIDv7.generate(),
            name: "agent-studio",
            stableKey: "1111111111111111"
        )
        let worktree = repositoryWithoutStableKeys.worktrees[0]
        let repository = RepoPresentationItem(
            id: repositoryWithoutStableKeys.id,
            name: repositoryWithoutStableKeys.name,
            repoPath: repositoryWithoutStableKeys.repoPath,
            stableKey: repositoryWithoutStableKeys.stableKey,
            worktrees: [worktree],
            worktreeStableKeysByID: [worktree.id: worktree.stableKey]
        )
        let referenceDate = Date(timeIntervalSince1970: 10_000_000)
        let activityAt = referenceDate.addingTimeInterval(
            -AppPolicies.EntityRecency.applicationActivityHorizon
        )
        let activity = try RepositoryLocalActivity(
            repositoryStableKey: repository.stableKey,
            lastQualifyingActivityAt: activityAt,
            continuousCoverageStartedAt: activityAt.addingTimeInterval(-1),
            updatedAt: referenceDate,
            ownedPromotionAttemptID: nil,
            ownedPromotionStartedAt: nil,
            ownedPromotionUnsettled: false
        )
        let expiration = activityAt.addingTimeInterval(
            AppPolicies.EntityRecency.applicationActivityHorizon
        )
        let transition = Date(
            timeIntervalSinceReferenceDate: expiration.timeIntervalSinceReferenceDate.nextUp
        )

        let warm = try RepoExplorerProjectionWorker.project(
            request(
                repos: [repository],
                generation: 1,
                localActivityHydrationDisposition: .authoritative,
                repositoryLocalActivityByStableKey: [repository.stableKey: activity],
                activityReferenceDate: referenceDate
            )
        )
        let inactive = try RepoExplorerProjectionWorker.project(
            request(
                repos: [repository],
                generation: 2,
                localActivityHydrationDisposition: .authoritative,
                repositoryLocalActivityByStableKey: [repository.stableKey: activity],
                activityReferenceDate: transition
            )
        )

        #expect(warm.repositoryActivityDispositionByRepoId[repository.id] == .warm)
        #expect(warm.nextRepositoryActivityTransitionAt == transition)
        #expect(inactive.repositoryActivityDispositionByRepoId[repository.id] == .locallyInactive)
        #expect(inactive.nextRepositoryActivityTransitionAt == nil)
    }
}
