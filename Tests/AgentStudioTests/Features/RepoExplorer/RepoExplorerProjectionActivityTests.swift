import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

extension RepoExplorerProjectionWorkerTests {
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
