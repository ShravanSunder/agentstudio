import Foundation
import Testing

@testable import AgentStudioCore

@Suite("Repository local activity projector")
struct RepositoryLocalActivityProjectorTests {
    @Test("commits the slowest processed participant watermark per volume")
    func commitsSlowestProcessedParticipantWatermarkPerVolume() async throws {
        // Arrange
        let recorder = RepositoryLocalActivityCommitRecorder()
        let projector = RepositoryLocalActivityProjector { commit in
            await recorder.record(commit)
        }
        let repositoryA = "aaaaaaaaaaaaaaaa"
        let repositoryB = "bbbbbbbbbbbbbbbb"
        let localParticipant = RepositoryLocalActivityParticipant(
            scopeKey: "local-a",
            generation: 1,
            volumeIdentifier: "volume-7",
            repositoryStableKeys: [repositoryA]
        )
        let sharedParticipant = RepositoryLocalActivityParticipant(
            scopeKey: "shared-parent",
            generation: 2,
            volumeIdentifier: "volume-7",
            repositoryStableKeys: [repositoryA, repositoryB]
        )
        await projector.replaceParticipants(
            [localParticipant, sharedParticipant],
            coverageRestartedAt: Date(timeIntervalSince1970: 100)
        )
        await projector.ingest(
            .init(
                scopeKey: localParticipant.scopeKey,
                generation: localParticipant.generation,
                eventID: 100,
                disposition: .qualifying,
                observedAt: Date(timeIntervalSince1970: 110)
            )
        )
        await projector.ingest(
            .init(
                scopeKey: sharedParticipant.scopeKey,
                generation: sharedParticipant.generation,
                eventID: 80,
                disposition: .progressOnly,
                observedAt: Date(timeIntervalSince1970: 111)
            )
        )

        // Act
        let didCommit = try await projector.commitBarrier(
            .init(
                deliveredEventIDByParticipant: [
                    localParticipant.identity: 100,
                    sharedParticipant.identity: 80,
                ],
                completedAt: Date(timeIntervalSince1970: 120)
            )
        )

        // Assert
        #expect(didCommit)
        let commit = try #require(await recorder.commits.first)
        #expect(commit.cursorWatermarks.map(\.lastEventID) == [80])
        #expect(commit.cursorWatermarks.map(\.volumeIdentifier) == ["volume-7"])
        let updateByRepository = Dictionary(
            uniqueKeysWithValues: commit.repositoryUpdates.map { ($0.repositoryStableKey, $0) }
        )
        #expect(updateByRepository[repositoryA]?.qualifyingActivityAt == Date(timeIntervalSince1970: 110))
        #expect(updateByRepository[repositoryA]?.coverageChange == .restart(at: Date(timeIntervalSince1970: 100)))
        #expect(updateByRepository[repositoryB]?.qualifyingActivityAt == nil)
        #expect(updateByRepository[repositoryB]?.coverageChange == .restart(at: Date(timeIntervalSince1970: 100)))
    }

    @Test("participant generation replacement resets only affected repository coverage")
    func participantGenerationReplacementResetsOnlyAffectedRepositoryCoverage() async throws {
        // Arrange
        let recorder = RepositoryLocalActivityCommitRecorder()
        let projector = RepositoryLocalActivityProjector { commit in
            await recorder.record(commit)
        }
        let repositoryA = "aaaaaaaaaaaaaaaa"
        let repositoryB = "bbbbbbbbbbbbbbbb"
        let localA1 = RepositoryLocalActivityParticipant(
            scopeKey: "local-a",
            generation: 1,
            volumeIdentifier: "volume-7",
            repositoryStableKeys: [repositoryA]
        )
        let localB1 = RepositoryLocalActivityParticipant(
            scopeKey: "local-b",
            generation: 1,
            volumeIdentifier: "volume-7",
            repositoryStableKeys: [repositoryB]
        )
        await projector.replaceParticipants(
            [localA1, localB1],
            coverageRestartedAt: Date(timeIntervalSince1970: 100)
        )
        await projector.ingest(
            .init(
                scopeKey: localA1.scopeKey,
                generation: localA1.generation,
                eventID: 10,
                disposition: .progressOnly,
                observedAt: Date(timeIntervalSince1970: 101)
            )
        )
        await projector.ingest(
            .init(
                scopeKey: localB1.scopeKey,
                generation: localB1.generation,
                eventID: 10,
                disposition: .progressOnly,
                observedAt: Date(timeIntervalSince1970: 101)
            )
        )
        _ = try await projector.commitBarrier(
            .init(
                deliveredEventIDByParticipant: [localA1.identity: 10, localB1.identity: 10],
                completedAt: Date(timeIntervalSince1970: 110)
            )
        )
        await recorder.reset()
        let localA2 = RepositoryLocalActivityParticipant(
            scopeKey: localA1.scopeKey,
            generation: 2,
            volumeIdentifier: localA1.volumeIdentifier,
            repositoryStableKeys: localA1.repositoryStableKeys
        )
        await projector.replaceParticipants(
            [localA2, localB1],
            coverageRestartedAt: Date(timeIntervalSince1970: 200)
        )
        await projector.ingest(
            .init(
                scopeKey: localA2.scopeKey,
                generation: localA2.generation,
                eventID: 20,
                disposition: .progressOnly,
                observedAt: Date(timeIntervalSince1970: 201)
            )
        )
        await projector.ingest(
            .init(
                scopeKey: localB1.scopeKey,
                generation: localB1.generation,
                eventID: 20,
                disposition: .progressOnly,
                observedAt: Date(timeIntervalSince1970: 201)
            )
        )

        // Act
        _ = try await projector.commitBarrier(
            .init(
                deliveredEventIDByParticipant: [localA2.identity: 20, localB1.identity: 20],
                completedAt: Date(timeIntervalSince1970: 210)
            )
        )

        // Assert
        let commit = try #require(await recorder.commits.first)
        #expect(commit.repositoryUpdates.map(\.repositoryStableKey) == [repositoryA])
        #expect(
            commit.repositoryUpdates.first?.coverageChange
                == .restart(at: Date(timeIntervalSince1970: 200))
        )
    }
}

private actor RepositoryLocalActivityCommitRecorder {
    private(set) var commits: [RepositoryLocalActivityCommit] = []

    func record(_ commit: RepositoryLocalActivityCommit) {
        commits.append(commit)
    }

    func reset() {
        commits.removeAll(keepingCapacity: true)
    }
}
