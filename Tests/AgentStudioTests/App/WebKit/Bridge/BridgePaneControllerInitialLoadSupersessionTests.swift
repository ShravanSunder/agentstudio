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
        fixture.controller.applyBridgePaneActivity(.foreground)
        let initialLoadStarted = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(2)) {
            await comparisonGate.hasStartedComparisonCount(1)
        }
        guard initialLoadStarted else {
            Issue.record("Explicit initial Review intake did not reach the provider")
            await comparisonGate.releaseAll()
            await fixture.finish()
            return
        }
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
        let successorStarted = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(2)) {
            await comparisonGate.hasStartedComparisonCount(2)
        }
        #expect(successorStarted, "A cancelled initial load must not consume its successor as a no-op")
        await comparisonGate.releaseAll()
        let predecessorDrained = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(2)) {
            fixture.controller.retiringReviewRefreshTaskById.isEmpty
        }
        #expect(predecessorDrained)
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
