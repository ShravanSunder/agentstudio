import AgentStudioCore
import AgentStudioTestSupport
import Testing

@testable import AgentStudioBridge

@Suite("Development Review refresh supersession", .timeLimit(.minutes(1)))
struct BridgeDevelopmentReviewRefreshSupersessionTests {
    @Test("cancelled same-lineage refresh cannot fail its pending successor")
    func cancelledSameLineageRefreshCannotFailPendingSuccessor() async throws {
        // Arrange — an installed, nonempty Review takes the same-lineage refresh path.
        let repositoryURL = try FilesystemTestGitRepo.create(named: "development-review-same-lineage-race")
        defer { FilesystemTestGitRepo.destroy(repositoryURL) }
        let provider = BridgeDevelopmentSharedConstructionReviewProvider(
            changedFiles: [
                makeBridgeEndpointChangedFile(
                    fileId: "reviewed-file",
                    path: "tracked.txt",
                    sizeBytes: 100,
                    newContentHash: "sha256:initial"
                )
            ]
        )
        let source = makeDevelopmentProductSource(worktreeRoot: repositoryURL)
        let host = try await BridgeDevelopmentProductHost(
            source: source,
            contributionTargetCommit: developmentContributionTargetCommit(worktreeRoot: repositoryURL),
            makeReviewProvider: { _, _ in provider }
        )
        try await withShutdownDevelopmentProductHost(host) {
            _ = try await host.issueBootstrap(for: makeDevelopmentBootstrapRequest(surface: "review"))
            let predecessor = try #require(await host.diagnosticCommittedReviewPublication())
            let coordinator = await host.reviewPublicationCoordinator
            let productAdmission = await host.productAdmission
            let workerInstanceId = "development-same-lineage-worker"
            #expect(
                await coordinator.admitDisplayInstallation(
                    expectedDisplayedPublicationId: nil,
                    candidatePublicationId: predecessor.publicationId,
                    workerInstanceId: workerInstanceId,
                    productAdmission: productAdmission
                ) == .admitted
            )
            #expect(
                await coordinator.recordDisplayedApplication(
                    publicationId: predecessor.publicationId,
                    workerInstanceId: workerInstanceId,
                    productAdmission: productAdmission
                ) == .advanced
            )
            await provider.setChangedFiles([
                makeBridgeEndpointChangedFile(
                    fileId: "reviewed-file",
                    path: "tracked.txt",
                    sizeBytes: 101,
                    newContentHash: "sha256:successor"
                )
            ])
            let predecessorGate = BridgeComparisonGate()
            let successorGate = BridgeComparisonGate()
            await provider.setComparisonGate(predecessorGate)

            // Act — finish cancelled work while the newer reservation is still pending.
            await host.handleObservedWorktreeInvalidation(
                developmentFileInvalidation(source: source, batchSequence: 1)
            )
            await predecessorGate.waitForStartedComparisonCount(1)
            let retiredTask = await host.activeReviewComparisonTask
            await provider.setComparisonGate(successorGate)
            await host.handleObservedWorktreeInvalidation(
                developmentFileInvalidation(source: source, batchSequence: 2)
            )
            await successorGate.waitForStartedComparisonCount(1)
            let successorTask = await host.activeReviewComparisonTask
            await predecessorGate.releaseAll()
            await retiredTask?.value

            // Assert — stale failure cannot mutate current presentation or publication.
            #expect(
                await host.diagnosticPanePresentation().reviewComparison?.attempt
                    == .pending(reviewGeneration: predecessor.package.reviewGeneration.rawValue)
            )
            #expect(await host.diagnosticCommittedReviewPublication()?.publicationId == predecessor.publicationId)
            let requests = await provider.snapshot()
            #expect(requests.reviewGenerationValues == [1, 1, 1])
            #expect(requests.reviewAttemptAuthorityGenerations.count == 3)
            #expect(requests.reviewAttemptAuthorityGenerations[2] > requests.reviewAttemptAuthorityGenerations[1])

            await successorGate.releaseAll()
            await successorTask?.value
            let successor = try #require(await host.diagnosticCommittedReviewPublication())
            #expect(successor.package.reviewGeneration == predecessor.package.reviewGeneration)
            #expect(successor.package.revision == predecessor.package.revision + 1)
            #expect(successor.publicationId != predecessor.publicationId)
            #expect(
                await host.diagnosticPanePresentation().reviewComparison?.attempt
                    == .settled(reviewGeneration: successor.package.reviewGeneration.rawValue)
            )
            #expect(await host.retiringReviewComparisonTasks.isEmpty)
            #expect(await host.activeReviewComparisonTask == nil)
        }
    }
}
