import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioBridge
@testable import AgentStudioCore

@MainActor
@Suite(
    "Bridge development product host Review replay integration",
    .serialized,
    .timeLimit(.minutes(1))
)
struct BridgeDevelopmentHostReviewReplayTests {
    @Test("fresh File bootstrap replays every retained Review metadata window")
    func freshFileBootstrapReplaysEveryRetainedReviewMetadataWindow() async throws {
        // Arrange
        let expectedItemCount = 1699
        let repositoryURL = try await FilesystemTestGitRepo.create(
            named: "bridge-development-product-host-review-replay"
        )
        defer { FilesystemTestGitRepo.destroy(repositoryURL) }
        let provider = makeReviewReplayProvider(itemCount: expectedItemCount)
        let host = try await BridgeDevelopmentProductHost(
            source: makeDevelopmentProductSource(worktreeRoot: repositoryURL),
            contributionTargetCommit: developmentContributionTargetCommit(
                worktreeRoot: repositoryURL
            ),
            makeReviewProvider: { _, _ in provider }
        )
        var activeMetadataStream: DevelopmentDisplayMetadataStream?

        do {
            let bootstrapRequest = try developmentDisplayBootstrapRequest(
                reason: "initial",
                surface: "file"
            )
            let firstWorker = try DevelopmentDisplayWorkerClient(
                host: host,
                delivery: await host.issueBootstrap(for: bootstrapRequest)
            )
            try await firstWorker.openSession()
            var firstMetadataStream = try firstWorker.startMetadataStream()
            activeMetadataStream = firstMetadataStream
            try await firstMetadataStream.requireOpeningFrameAndAcknowledge(using: firstWorker)
            try await firstWorker.activateReviewViewerMode()
            try await firstWorker.openReviewMetadataSubscription()
            let firstReplay = try await firstMetadataStream.consumeCompleteReviewPublication(
                expectedItemCount: expectedItemCount,
                using: firstWorker
            )
            let retainedPublication = try #require(await host.diagnosticCommittedReviewPublication())
            #expect(retainedPublication.package.orderedItemIds.count == expectedItemCount)
            #expect(firstReplay.identity.publicationId == retainedPublication.publicationId)
            #expect(firstReplay.windowCount > 1)
            #expect(
                try await firstWorker.admitReviewPublication(
                    candidatePublicationId: retainedPublication.publicationId,
                    expectedDisplayedPublicationId: nil,
                    workerDerivationEpoch: 1
                )
            )
            try await firstWorker.applyReviewPublication(
                retainedPublication.publicationId,
                workerDerivationEpoch: 1
            )

            // Act — ending the first document's real stream lets a fresh initial File bootstrap
            // retire that worker before the successor asks for the retained Review publication.
            await firstMetadataStream.stop()
            activeMetadataStream = nil
            let secondWorker = try DevelopmentDisplayWorkerClient(
                host: host,
                delivery: await host.issueBootstrap(for: bootstrapRequest)
            )
            try await secondWorker.openSession()
            var secondMetadataStream = try secondWorker.startMetadataStream()
            activeMetadataStream = secondMetadataStream
            try await secondMetadataStream.requireOpeningFrameAndAcknowledge(using: secondWorker)
            try await secondWorker.activateReviewViewerMode()
            try await secondWorker.openReviewMetadataSubscription()
            let secondReplay = try await secondMetadataStream.consumeCompleteReviewPublication(
                expectedItemCount: expectedItemCount,
                using: secondWorker
            )
            #expect(
                try await secondWorker.admitReviewPublication(
                    candidatePublicationId: retainedPublication.publicationId,
                    expectedDisplayedPublicationId: nil,
                    workerDerivationEpoch: 1
                )
            )
            try await secondWorker.applyReviewPublication(
                retainedPublication.publicationId,
                workerDerivationEpoch: 1
            )

            // Assert
            #expect(secondWorker.paneSessionId == firstWorker.paneSessionId)
            #expect(secondWorker.workerInstanceId != firstWorker.workerInstanceId)
            #expect(secondReplay.identity == firstReplay.identity)
            #expect(secondReplay.itemCount == expectedItemCount)
            #expect(secondReplay.windowCount == firstReplay.windowCount)
            #expect(
                await host.diagnosticCommittedReviewPublication()?.publicationId
                    == retainedPublication.publicationId
            )
            let coordinator = await host.reviewPublicationCoordinator
            #expect(
                coordinator.diagnosticSnapshot.acknowledgedDisplayed?.publicationId
                    == retainedPublication.publicationId
            )

            await secondMetadataStream.stop()
            activeMetadataStream = nil
            await host.shutdown()
        } catch {
            await activeMetadataStream?.stop()
            await host.shutdown()
            throw error
        }
    }
}

@MainActor
private func makeReviewReplayProvider(itemCount: Int) -> BridgeDevelopmentSharedConstructionReviewProvider {
    BridgeDevelopmentSharedConstructionReviewProvider(
        changedFiles: (0..<itemCount).map { itemIndex in
            makeBridgeEndpointChangedFile(
                fileId: String(format: "review-replay-%05d", itemIndex),
                path: String(
                    format: "Sources/Module%02d/File%05d.swift",
                    itemIndex % 32,
                    itemIndex
                ),
                sizeBytes: 100
            )
        }
    )
}
