import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("Repository local activity atom", .serialized)
struct RepositoryLocalActivityAtomTests {
    @Test("publishes keyed facts only when accepted content changes")
    func publishesKeyedFactsOnlyWhenAcceptedContentChanges() throws {
        // Arrange
        let atom = RepositoryLocalActivityAtom()
        let stableKey = "aaaaaaaaaaaaaaaa"
        let initialActivity = try RepositoryLocalActivity(
            repositoryStableKey: stableKey,
            lastQualifyingActivityAt: Date(timeIntervalSince1970: 200),
            continuousCoverageStartedAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 210),
            ownedPromotionAttemptID: nil,
            ownedPromotionStartedAt: nil,
            ownedPromotionUnsettled: false
        )
        let initialSnapshot = RepositoryLocalActivitySnapshot(
            activityByRepositoryStableKey: [stableKey: initialActivity],
            cursorByVolumeIdentifier: [:]
        )

        // Act / Assert
        atom.publishAuthoritative(initialSnapshot)
        let initialRevision = atom.acceptedRevision
        #expect(atom.hydrationDisposition == .authoritative)
        #expect(atom.activity(for: stableKey) == initialActivity)

        atom.publishAuthoritative(initialSnapshot)
        #expect(atom.acceptedRevision == initialRevision)

        atom.publishAuthoritative(
            RepositoryLocalActivitySnapshot(
                activityByRepositoryStableKey: [stableKey: initialActivity],
                cursorByVolumeIdentifier: [
                    "volume-a": try RepositoryLocalActivityCursor(
                        volumeIdentifier: "volume-a",
                        lastEventID: 10,
                        updatedAt: Date(timeIntervalSince1970: 220)
                    )
                ]
            )
        )
        #expect(atom.acceptedRevision == initialRevision)

        let changedActivity = try RepositoryLocalActivity(
            repositoryStableKey: stableKey,
            lastQualifyingActivityAt: Date(timeIntervalSince1970: 220),
            continuousCoverageStartedAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 220),
            ownedPromotionAttemptID: nil,
            ownedPromotionStartedAt: nil,
            ownedPromotionUnsettled: false
        )
        atom.publishAuthoritative(
            RepositoryLocalActivitySnapshot(
                activityByRepositoryStableKey: [stableKey: changedActivity],
                cursorByVolumeIdentifier: [:]
            )
        )
        #expect(atom.acceptedRevision == initialRevision + 1)
        #expect(atom.activity(for: stableKey) == changedActivity)
    }

    @Test("unavailable persistence clears facts without claiming authority")
    func unavailablePersistenceClearsFactsWithoutClaimingAuthority() throws {
        // Arrange
        let atom = RepositoryLocalActivityAtom()
        let stableKey = "bbbbbbbbbbbbbbbb"
        let activity = try RepositoryLocalActivity(
            repositoryStableKey: stableKey,
            lastQualifyingActivityAt: nil,
            continuousCoverageStartedAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100),
            ownedPromotionAttemptID: nil,
            ownedPromotionStartedAt: nil,
            ownedPromotionUnsettled: false
        )
        atom.publishAuthoritative(
            RepositoryLocalActivitySnapshot(
                activityByRepositoryStableKey: [stableKey: activity],
                cursorByVolumeIdentifier: [:]
            )
        )

        // Act
        atom.publishUnavailable()

        // Assert
        #expect(atom.hydrationDisposition == .unavailable)
        #expect(atom.activity(for: stableKey) == nil)
    }
}
