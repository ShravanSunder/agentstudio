import Foundation
import Testing

@testable import AgentStudioCore

@Suite("RepositoryActivityClassifier")
struct RepositoryActivityClassifierTests {
    private let firstRepositoryID = UUID(uuidString: "00000000-0000-7000-8000-000000000001")!
    private let firstWorktreeID = UUID(uuidString: "00000000-0000-7000-8000-000000000002")!
    private let secondRepositoryID = UUID(uuidString: "00000000-0000-7000-8000-000000000003")!
    private let secondWorktreeID = UUID(uuidString: "00000000-0000-7000-8000-000000000004")!
    private let horizon: TimeInterval = 60 * 24 * 60 * 60

    @Test("unknown local activity is unclassified and has no deadline")
    func preHydrationIsUnclassified() {
        let result = RepositoryActivityClassifier.classify(
            input(referenceDate: Date(timeIntervalSinceReferenceDate: 1000))
        )

        #expect(result.dispositionByRepositoryID[firstRepositoryID] == .unclassified)
        #expect(result.dispositionByRepositoryID[secondRepositoryID] == .unclassified)
        #expect(result.warmRepositoryIDs.isEmpty)
        #expect(result.warmWorktreeIDs.isEmpty)
        #expect(result.unknownRepositoryIDs == [firstRepositoryID, secondRepositoryID])
        #expect(result.unknownWorktreeIDs == [firstWorktreeID, secondWorktreeID])
        #expect(result.locallyInactiveRepositoryIDs.isEmpty)
        #expect(result.nextTransitionAt == nil)
    }

    @Test("recent authoritative coverage without recent activity remains unknown")
    func recentCoverageWithoutRecentActivityRemainsUnknown() throws {
        let referenceDate = Date(timeIntervalSinceReferenceDate: 10_000_000)
        let coverageStartedAt = referenceDate.addingTimeInterval(-100)
        let transitionAt = Date(
            timeIntervalSinceReferenceDate: coverageStartedAt.addingTimeInterval(horizon)
                .timeIntervalSinceReferenceDate.nextUp
        )
        let firstActivity = try RepositoryLocalActivity(
            repositoryStableKey: "1111111111111111",
            lastQualifyingActivityAt: nil,
            continuousCoverageStartedAt: coverageStartedAt,
            updatedAt: referenceDate,
            ownedPromotionAttemptID: nil,
            ownedPromotionStartedAt: nil,
            ownedPromotionUnsettled: false
        )

        let result = RepositoryActivityClassifier.classify(
            input(
                localActivityHydrationDisposition: .authoritative,
                repositoryLocalActivityByStableKey: [
                    firstActivity.repositoryStableKey: firstActivity
                ],
                referenceDate: referenceDate
            )
        )

        #expect(result.dispositionByRepositoryID[firstRepositoryID] == .unclassified)
        #expect(result.warmRepositoryIDs.isEmpty)
        #expect(result.warmWorktreeIDs.isEmpty)
        #expect(result.unknownRepositoryIDs == [firstRepositoryID, secondRepositoryID])
        #expect(result.unknownWorktreeIDs == [firstWorktreeID, secondWorktreeID])
        #expect(result.locallyInactiveRepositoryIDs.isEmpty)
        #expect(result.nextTransitionAt == transitionAt)
    }

    @Test("trustworthy repository-local activity separates warm and sixty-day inactive")
    func trustworthyLocalActivitySeparatesWarmAndInactive() throws {
        let referenceDate = Date(timeIntervalSinceReferenceDate: 10_000_000)
        let warmActivityAt = referenceDate.addingTimeInterval(-100)
        let coverageStartedAt = referenceDate.addingTimeInterval(-horizon - 1000)
        let warmTransition = Date(
            timeIntervalSinceReferenceDate: warmActivityAt.addingTimeInterval(horizon)
                .timeIntervalSinceReferenceDate.nextUp
        )
        let firstActivity = try RepositoryLocalActivity(
            repositoryStableKey: "1111111111111111",
            lastQualifyingActivityAt: warmActivityAt,
            continuousCoverageStartedAt: coverageStartedAt,
            updatedAt: referenceDate,
            ownedPromotionAttemptID: nil,
            ownedPromotionStartedAt: nil,
            ownedPromotionUnsettled: false
        )
        let secondActivity = try RepositoryLocalActivity(
            repositoryStableKey: "3333333333333333",
            lastQualifyingActivityAt: nil,
            continuousCoverageStartedAt: coverageStartedAt,
            updatedAt: referenceDate,
            ownedPromotionAttemptID: nil,
            ownedPromotionStartedAt: nil,
            ownedPromotionUnsettled: false
        )
        let result = RepositoryActivityClassifier.classify(
            input(
                localActivityHydrationDisposition: .authoritative,
                repositoryLocalActivityByStableKey: [
                    firstActivity.repositoryStableKey: firstActivity,
                    secondActivity.repositoryStableKey: secondActivity,
                ],
                referenceDate: referenceDate
            )
        )

        #expect(result.dispositionByRepositoryID[firstRepositoryID] == .warm)
        #expect(result.dispositionByRepositoryID[secondRepositoryID] == .locallyInactive)
        #expect(result.warmRepositoryIDs == [firstRepositoryID])
        #expect(result.unknownRepositoryIDs.isEmpty)
        #expect(result.locallyInactiveRepositoryIDs == [secondRepositoryID])
        #expect(result.warmWorktreeIDs == [firstWorktreeID])
        #expect(result.unknownWorktreeIDs.isEmpty)
        #expect(result.locallyInactiveWorktreeIDs == [secondWorktreeID])
        #expect(result.nextTransitionAt == warmTransition)
    }

    @Test("activity expiry becomes unknown until continuous coverage matures")
    func activityExpiryBecomesUnknownUntilCoverageMatures() throws {
        let referenceDate = Date(timeIntervalSinceReferenceDate: 10_000_000)
        let lastActivityAt = referenceDate.addingTimeInterval(-50 * 24 * 60 * 60)
        let coverageStartedAt = referenceDate.addingTimeInterval(-10 * 24 * 60 * 60)
        let activityTransitionAt = Date(
            timeIntervalSinceReferenceDate: lastActivityAt.addingTimeInterval(horizon)
                .timeIntervalSinceReferenceDate.nextUp
        )
        let coverageTransitionAt = Date(
            timeIntervalSinceReferenceDate: coverageStartedAt.addingTimeInterval(horizon)
                .timeIntervalSinceReferenceDate.nextUp
        )
        let activity = try RepositoryLocalActivity(
            repositoryStableKey: "1111111111111111",
            lastQualifyingActivityAt: lastActivityAt,
            continuousCoverageStartedAt: coverageStartedAt,
            updatedAt: referenceDate,
            ownedPromotionAttemptID: nil,
            ownedPromotionStartedAt: nil,
            ownedPromotionUnsettled: false
        )

        let warm = RepositoryActivityClassifier.classify(
            input(
                localActivityHydrationDisposition: .authoritative,
                repositoryLocalActivityByStableKey: [activity.repositoryStableKey: activity],
                referenceDate: referenceDate
            )
        )
        let unknown = RepositoryActivityClassifier.classify(
            input(
                localActivityHydrationDisposition: .authoritative,
                repositoryLocalActivityByStableKey: [activity.repositoryStableKey: activity],
                referenceDate: activityTransitionAt
            )
        )

        #expect(warm.dispositionByRepositoryID[firstRepositoryID] == .warm)
        #expect(warm.nextTransitionAt == activityTransitionAt)
        #expect(unknown.dispositionByRepositoryID[firstRepositoryID] == .unclassified)
        #expect(unknown.unknownRepositoryIDs.contains(firstRepositoryID))
        #expect(unknown.nextTransitionAt == coverageTransitionAt)
    }

    @Test("an open worktree keeps its repository warm without a time deadline")
    func openWorktreeKeepsRepositoryWarm() {
        let result = RepositoryActivityClassifier.classify(
            input(
                openWorktreeIDs: [firstWorktreeID],
                referenceDate: Date(timeIntervalSinceReferenceDate: 10_000)
            )
        )

        #expect(result.dispositionByRepositoryID[secondRepositoryID] == .unclassified)
        #expect(result.warmRepositoryIDs == [firstRepositoryID])
        #expect(result.unknownRepositoryIDs == [secondRepositoryID])
        #expect(result.unknownWorktreeIDs == [secondWorktreeID])
        #expect(result.locallyInactiveRepositoryIDs.isEmpty)
        #expect(result.nextTransitionAt == nil)
    }

    private func input(
        openWorktreeIDs: Set<UUID> = [],
        localActivityHydrationDisposition: RepositoryLocalActivityHydrationDisposition = .pending,
        repositoryLocalActivityByStableKey: [String: RepositoryLocalActivity] = [:],
        referenceDate: Date
    ) -> RepositoryActivityClassificationInput {
        RepositoryActivityClassificationInput(
            repositories: [
                RepositoryActivityTopology(
                    repositoryID: firstRepositoryID,
                    repositoryStableKey: "1111111111111111",
                    worktreeStableKeysByID: [firstWorktreeID: "2222222222222222"]
                ),
                RepositoryActivityTopology(
                    repositoryID: secondRepositoryID,
                    repositoryStableKey: "3333333333333333",
                    worktreeStableKeysByID: [secondWorktreeID: "4444444444444444"]
                ),
            ],
            openWorktreeIDs: openWorktreeIDs,
            localActivityHydrationDisposition: localActivityHydrationDisposition,
            repositoryLocalActivityByStableKey: repositoryLocalActivityByStableKey,
            referenceDate: referenceDate,
            inactivityHorizon: horizon
        )
    }
}
