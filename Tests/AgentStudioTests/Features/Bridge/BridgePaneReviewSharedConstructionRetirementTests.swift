import AgentStudioGit
import Foundation
import Testing

@testable import AgentStudio

extension BridgePaneReviewSharedConstructionTests {
    @Test("retiring candidate locator falls back to retained same-generation backing")
    func retiringCandidateLocatorFallsBackToRetainedSameGenerationBacking() async throws {
        let baseTarget = GitDiffTarget.commit(String(repeating: "a", count: 40))
        let basePath = "Sources/App.swift"
        let physicalReadGate = BridgeGitContentReadGate()
        let schedulerEventProbe = BridgeGitReadSchedulerEventProbe()
        let fixture = try BridgeSharedReviewConstructionFixture.make(
            contentReadGateByLocator: [
                GitContentLocator(target: baseTarget, path: basePath): physicalReadGate
            ],
            schedulerEventSink: schedulerEventProbe.eventSink
        )
        defer { fixture.removeTestRoot() }
        let request = fixture.request(packageId: "package-retained", generation: 1)
        let bindingA = try await fixture.firstBinder.acquire(request)
        let handleA = try #require(
            bindingA.result.registeredContentHandles.first { $0.role == .base }
        )
        _ = await fixture.coordinator.invalidate(worktree: fixture.worktreeIdentityKey)
        let bindingB = try await fixture.firstBinder.acquire(request)
        let handleB = try #require(bindingB.result.registeredContentHandles.first { $0.role == .base })
        let blockingRead = Task {
            try await fixture.firstClient.loadGitContentPayload(
                GitContentRequest(
                    repositoryPath: fixture.repositoryPath,
                    target: baseTarget,
                    path: basePath,
                    maxSizeBytes: Int64(AppPolicies.Bridge.contentMaxBytesPerItem)
                ),
                operationClass: .selectedVisibleContent,
                freshnessKey: BridgeGitReadFreshnessKey(token: "retirement-blocker")
            )
        }
        await physicalReadGate.waitUntilStarted()
        let queuedOccurrence = schedulerEventProbe.events.count { $0.kind == .queued } + 1
        let retainedLoad = Task {
            try await fixture.firstProvider.loadContent(
                BridgeContentLoadRequest(handle: handleA, requestedGeneration: 1)
            )
        }
        _ = await schedulerEventProbe.waitFor(.queued, occurrence: queuedOccurrence)
        #expect(handleA.handleId == handleB.handleId)
        #expect(handleA.reviewGeneration == handleB.reviewGeneration)

        bindingB.artifactPin.release()
        _ = await fixture.constructionEventProbe.waitFor(.entryRemoved)
        await physicalReadGate.release()
        _ = try await blockingRead.value
        let loadedContent = try await retainedLoad.value

        #expect(loadedContent.data == Data("base-a".utf8))
        await bindingA.artifactPin.releaseAndWait()
        await fixture.waitUntilBackingDirectoryIsEmpty()
        #expect(await fixture.firstClient.registeredContentLocatorCount() == 0)
    }
}

extension BridgeSharedReviewConstructionFixture {
    static func makeScheduler(
        eventSink: BridgeGitReadSchedulerEventSink?
    ) -> BridgeGitReadScheduler {
        BridgeGitReadScheduler(
            topology: BridgeGitReadSchedulerTopology(
                slotsByOperationClass: [
                    .reviewMetadata: [BridgeGitReadSlotID(token: "shared-review-metadata")],
                    .selectedVisibleContent: [BridgeGitReadSlotID(token: "shared-review-content")],
                ],
                maximumQueuedOperationCountByClass: [
                    .reviewMetadata: 8,
                    .selectedVisibleContent: 8,
                ],
                maximumLogicalWaiterCountPerOperation: 8
            ),
            eventSink: eventSink
        )
    }
}
