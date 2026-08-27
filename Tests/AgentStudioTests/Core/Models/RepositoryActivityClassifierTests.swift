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

    @Test("pre-hydration recency is unclassified and has no deadline")
    func preHydrationIsUnclassified() {
        let result = RepositoryActivityClassifier.classify(
            input(
                hydrationDisposition: .pending,
                referenceDate: Date(timeIntervalSinceReferenceDate: 1000)
            )
        )

        #expect(result.dispositionByRepositoryID[firstRepositoryID] == .unclassified)
        #expect(result.dispositionByRepositoryID[secondRepositoryID] == .unclassified)
        #expect(result.warmRepositoryIDs.isEmpty)
        #expect(result.locallyInactiveRepositoryIDs.isEmpty)
        #expect(result.nextTransitionAt == nil)
    }

    @Test("authoritative missing recency makes closed repositories inactive")
    func authoritativeMissingRecencyIsInactive() {
        let result = RepositoryActivityClassifier.classify(
            input(
                hydrationDisposition: .authoritative,
                referenceDate: Date(timeIntervalSinceReferenceDate: 1000)
            )
        )

        #expect(result.locallyInactiveRepositoryIDs == [firstRepositoryID, secondRepositoryID])
        #expect(result.locallyInactiveWorktreeIDs == [firstWorktreeID, secondWorktreeID])
        #expect(result.warmRepositoryIDs.isEmpty)
        #expect(result.nextTransitionAt == nil)
    }

    @Test("repository or any current worktree recency warms the whole repository")
    func repositoryOrWorktreeRecencyWarmsWholeRepository() throws {
        let referenceDate = Date(timeIntervalSinceReferenceDate: 10_000)
        let recentDate = referenceDate.addingTimeInterval(-100)
        let recency = try [
            ApplicationEntityRecency(
                entity: .repository(repositoryStableKey: "1111111111111111"),
                interaction: .opened,
                lastInteractedAt: recentDate
            ),
            ApplicationEntityRecency(
                entity: .worktree(worktreeStableKey: "4444444444444444"),
                interaction: .opened,
                lastInteractedAt: recentDate
            ),
        ]

        let result = RepositoryActivityClassifier.classify(
            input(
                hydrationDisposition: .authoritative,
                recency: recency,
                referenceDate: referenceDate
            )
        )

        #expect(result.warmRepositoryIDs == [firstRepositoryID, secondRepositoryID])
        #expect(result.warmWorktreeIDs == [firstWorktreeID, secondWorktreeID])
        #expect(result.locallyInactiveRepositoryIDs.isEmpty)
    }

    @Test("an open worktree keeps its repository warm without a time deadline")
    func openWorktreeKeepsRepositoryWarm() {
        let result = RepositoryActivityClassifier.classify(
            input(
                hydrationDisposition: .authoritative,
                openWorktreeIDs: [firstWorktreeID],
                referenceDate: Date(timeIntervalSinceReferenceDate: 10_000)
            )
        )

        #expect(result.warmRepositoryIDs == [firstRepositoryID])
        #expect(result.locallyInactiveRepositoryIDs == [secondRepositoryID])
        #expect(result.nextTransitionAt == nil)
    }

    @Test("cutoff equality is warm and the first representable later instant is inactive")
    func cutoffEqualityAndNextUp() throws {
        let lastOpen = Date(timeIntervalSinceReferenceDate: 50_000)
        let expiration = lastOpen.addingTimeInterval(horizon)
        let nextInstant = Date(
            timeIntervalSinceReferenceDate: expiration.timeIntervalSinceReferenceDate.nextUp
        )
        let recency = try [
            ApplicationEntityRecency(
                entity: .repository(repositoryStableKey: "1111111111111111"),
                interaction: .opened,
                lastInteractedAt: lastOpen
            )
        ]

        let atCutoff = RepositoryActivityClassifier.classify(
            input(
                hydrationDisposition: .authoritative,
                recency: recency,
                referenceDate: expiration
            )
        )
        let afterCutoff = RepositoryActivityClassifier.classify(
            input(
                hydrationDisposition: .authoritative,
                recency: recency,
                referenceDate: nextInstant
            )
        )

        #expect(atCutoff.dispositionByRepositoryID[firstRepositoryID] == .warm)
        #expect(atCutoff.nextTransitionAt == nextInstant)
        #expect(afterCutoff.dispositionByRepositoryID[firstRepositoryID] == .locallyInactive)
    }

    @Test("earliest transition ignores repositories held warm by open panes")
    func earliestTransitionIgnoresOpenRepositories() throws {
        let referenceDate = Date(timeIntervalSinceReferenceDate: 100_000)
        let firstOpen = referenceDate.addingTimeInterval(-1000)
        let secondOpen = referenceDate.addingTimeInterval(-2000)
        let recency = try [
            ApplicationEntityRecency(
                entity: .repository(repositoryStableKey: "1111111111111111"),
                interaction: .opened,
                lastInteractedAt: firstOpen
            ),
            ApplicationEntityRecency(
                entity: .repository(repositoryStableKey: "3333333333333333"),
                interaction: .opened,
                lastInteractedAt: secondOpen
            ),
        ]
        let expected = secondOpen.addingTimeInterval(horizon)
        let expectedNext = Date(
            timeIntervalSinceReferenceDate: expected.timeIntervalSinceReferenceDate.nextUp
        )

        let result = RepositoryActivityClassifier.classify(
            input(
                hydrationDisposition: .authoritative,
                openWorktreeIDs: [firstWorktreeID],
                recency: recency,
                referenceDate: referenceDate
            )
        )

        #expect(result.nextTransitionAt == expectedNext)
    }

    private func input(
        hydrationDisposition: ApplicationEntityRecencyHydrationDisposition,
        openWorktreeIDs: Set<UUID> = [],
        recency: [ApplicationEntityRecency] = [],
        referenceDate: Date
    ) -> RepositoryActivityClassificationInput {
        RepositoryActivityClassificationInput(
            hydrationDisposition: hydrationDisposition,
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
            recency: recency,
            referenceDate: referenceDate,
            inactivityHorizon: horizon
        )
    }
}
