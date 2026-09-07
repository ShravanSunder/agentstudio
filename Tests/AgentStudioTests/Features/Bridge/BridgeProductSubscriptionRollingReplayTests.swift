import Foundation
import Testing

@testable import AgentStudioBridge

struct BridgeProductSubscriptionRollingReplayTests {
    @Test("rolling history preserves exact replay and stale sequence rejection through the session")
    func sessionReplayOutlivesRecentIdWindow() async throws {
        // Arrange: real native session, control replay, and subscription transitions.
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        try await harness.openSubscription(
            bridgeProductLifecycleReviewSubscriptionOpenObject(requestSequence: 2, epoch: 1)
        )
        var firstRequestBytes: Data?

        do {
            // Act: each committed update is retried exactly before admitting the next.
            for revision in 1...1100 {
                let before = try #require(
                    await harness.session.subscriptionSnapshot(subscriptionId: "review-subscription-1")
                )
                let request = try makeRequest(snapshot: before, revision: revision)
                let requestBytes = try encode(request)
                if firstRequestBytes == nil { firstRequestBytes = requestBytes }
                let admission = await harness.session.beginControl(
                    exactRequestBytes: requestBytes,
                    presentedCapability: harness.capabilityHeader,
                    productAdmission: harness.productAdmission.context
                )
                guard case .execute(let token, _) = admission else {
                    Issue.record("Expected a fresh control admission")
                    await close(harness)
                    return
                }
                let response = try BridgeProductControlResponse.subscriptionUpdateBatchAccepted(
                    correlating: request,
                    disposition: .committed
                )
                let responseBytes = try encode(response)
                let effect = try await harness.session.completeControl(token: token, exactResponseBytes: responseBytes)
                guard case .subscriptionInterestsCommitted = effect else {
                    Issue.record("Expected a committed interest transition")
                    break
                }
                let after = await harness.session.subscriptionSnapshot(subscriptionId: "review-subscription-1")
                let replay = await harness.session.beginControl(
                    exactRequestBytes: requestBytes,
                    presentedCapability: harness.capabilityHeader,
                    productAdmission: harness.productAdmission.context
                )

                // Assert: replay returns identical bytes and performs no second mutation.
                #expect(after?.interestRevision == revision)
                #expect(replay == .replay(exactResponseBytes: responseBytes))
                #expect(await harness.session.subscriptionSnapshot(subscriptionId: "review-subscription-1") == after)
            }
            let oldRequest = try #require(firstRequestBytes)
            let stale = await harness.session.beginControl(
                exactRequestBytes: oldRequest,
                presentedCapability: harness.capabilityHeader,
                productAdmission: harness.productAdmission.context
            )
            guard case .rejected(let rejection) = stale else {
                Issue.record("An evicted update ID must not permit replay of an old request")
                await close(harness)
                return
            }
            #expect(rejection.reason == .sequenceConflict(nextExpectedRequestSequence: 1103))
            #expect(
                await harness.session.subscriptionSnapshot(subscriptionId: "review-subscription-1")?.interestRevision
                    == 1100)
        } catch {
            await close(harness)
            throw error
        }
        await close(harness)
    }

    private func makeRequest(snapshot: BridgeProductSubscriptionSnapshot, revision: Int) throws
        -> BridgeProductControlRequest
    {
        let lane: BridgeProductDemandLane = revision.isMultiple(of: 2) ? .visible : .foreground
        let target = BridgeProductSubscriptionInterestState.reviewMetadata(interests: [
            try .init(itemIds: ["rolling-item"], lane: lane)
        ])
        return try bridgeProductLifecycleControlRequest(
            [
                "kind": "subscription.updateBatch",
                "paneSessionId": "pane-session-1",
                "workerInstanceId": "worker-instance-1",
                "wireVersion": BridgeProductWireContract.version,
                "workerDerivationEpoch": 1,
                "requestId": "rolling-control-\(revision)",
                "requestSequence": revision + 2,
                "subscriptionId": "review-subscription-1",
                "subscriptionKind": "review.metadata",
                "updateId": "rolling-update-\(revision)",
                "batchIndex": 0,
                "batchCount": 1,
                "totalDeltaItemCount": 1,
                "baseInterestRevision": snapshot.interestRevision,
                "baseInterestSha256": snapshot.interestSha256,
                "targetInterestRevision": revision,
                "targetInterestSha256": try target.sha256Hex(),
                "delta": [
                    "subscriptionKind": "review.metadata",
                    "add": [["itemId": "rolling-item", "lane": lane.rawValue]],
                    "removeItemIds": [],
                ],
            ]
        )
    }

    private func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func close(_ harness: BridgeProductSessionLifecycleHarness) async {
        let barrier = await harness.session.revoke { _ in true }
        #expect(await barrier.wait())
    }
}
