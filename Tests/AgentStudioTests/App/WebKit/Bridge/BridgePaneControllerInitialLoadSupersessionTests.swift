import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore

extension WebKitSerializedTests.BridgePaneControllerTests {
    @Test("invalidation supersedes an initial Review load before any snapshot exists")
    func invalidationSupersedesInitialReviewLoadBeforeAnySnapshotExists() async throws {
        // Arrange
        let comparisonGate = BridgeComparisonGate()
        let fixture = try await makeRefreshAdmissionIntegrationFixture(comparisonGate: comparisonGate)
        // fire-and-forget: the test asserts admission state; the presentation transition handle is not its claim
        _ = fixture.controller.applyBridgePaneActivity(.foreground)
        await comparisonGate.waitForStartedComparisonCount(1)
        #expect(fixture.controller.paneState.diff.status == .loading)
        #expect(fixture.controller.paneState.diff.packageMetadata == nil)

        // Act — the first physical capture ignores cancellation while a fresh
        // repository invalidation must admit its current successor.
        await fixture.controller.handleWorktreeProductInvalidation(
            .filesChanged(
                fixture.makeChangeset(
                    paths: ["Sources/App/InitialLoadChanged.swift"],
                    batchSequence: 101
                )
            )
        )
        await comparisonGate.waitForStartedComparisonCount(2)
        let retirementTasks = Array(fixture.controller.retiringReviewRefreshTaskById.values)
        #expect(!retirementTasks.isEmpty)
        await comparisonGate.releaseAll()
        for task in retirementTasks { await task.value }
        #expect(fixture.controller.retiringReviewRefreshTaskById.isEmpty)
        await fixture.controller.activeReviewRefreshTask?.value
        await waitForActiveReviewRefreshTaskToFinish(fixture.controller)

        // Assert
        #expect(await fixture.reviewProvider.recordedComparisonRequestsCount() == 2)
        #expect(fixture.controller.pendingReviewPackageBuildReasons.isEmpty)
        #expect(fixture.controller.paneState.diff.status == .ready)
        #expect(fixture.controller.paneState.diff.packageMetadata?.orderedItemIds == ["item-initial"])
        #expect(fixture.controller.refreshAdmissionCoordinator.diagnosticSnapshot.dirtyFact == nil)
        await fixture.finish()
    }
}
