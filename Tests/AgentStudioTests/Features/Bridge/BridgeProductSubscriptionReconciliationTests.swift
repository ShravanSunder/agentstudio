import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge product subscription resync reconciliation")
struct BridgeProductSubscriptionReconciliationTests {
    @Test("resync discards staging and returns deterministic reset cancel and reopen intents")
    func resyncReconcilesSubscriptionStateAtomically() throws {
        // Arrange
        var state = BridgeProductSubscriptionState()
        let fileOpenRequest = try decode(
            BridgeProductSubscriptionOpenRequest.self,
            object: fileSubscriptionOpenObject()
        )
        let reviewOpenRequest = try decode(
            BridgeProductSubscriptionOpenRequest.self,
            object: reviewSubscriptionOpenObject()
        )
        _ = try state.open(fileOpenRequest)
        _ = try state.open(reviewOpenRequest)
        _ = try state.apply(
            decode(
                BridgeProductSubscriptionUpdateBatchRequest.self,
                object: stagedFileUpdateObject()
            ))
        let activeFile = try activeSubscription(
            subscriptionId: "file-subscription-1",
            subscriptionKind: .fileMetadata,
            workerDerivationEpoch: 2,
            interestRevision: 5,
            interestSha256: String(repeating: "0", count: 64)
        )
        let missingReview = try activeSubscription(
            subscriptionId: "review-subscription-missing",
            subscriptionKind: .reviewMetadata,
            workerDerivationEpoch: 7,
            interestRevision: 0,
            interestSha256:
                try BridgeProductSubscriptionInterestState
                .reviewMetadata(interests: [])
                .sha256Hex()
        )

        // Act
        let result = try state.reconcile(
            activeSubscriptions: [missingReview, activeFile]
        )

        // Assert
        let fileSnapshot = try #require(
            state.snapshot(subscriptionId: "file-subscription-1")
        )
        #expect(fileSnapshot.subscription == fileOpenRequest.subscription)
        #expect(fileSnapshot.interestRevision == 6)
        #expect(
            fileSnapshot.interestSha256
                == (try BridgeProductSubscriptionInterestState
                    .fileMetadata(interests: [], pathScope: [])
                    .sha256Hex())
        )
        #expect(!fileSnapshot.hasStagedUpdate)
        #expect(state.snapshot(subscriptionId: "review-subscription-1") == nil)
        #expect(result.reconciliation.map(\.dispositionName) == ["reopenRequired", "reset"])
        #expect(
            result.reconciliation.map(\.subscriptionId) == [
                "review-subscription-missing", "file-subscription-1",
            ])
        #expect(result.revokedNativeOnlySubscriptionIds == ["review-subscription-1"])
        #expect(result.resetIntents.count == 1)
        #expect(result.resetIntents[0].subscription == fileOpenRequest.subscription)
        #expect(result.resetIntents[0].interestRevision == 6)
    }

    @Test("failed resync revision reset leaves every subscription fact unchanged")
    func failedResyncIsMutationFree() throws {
        // Arrange
        var state = BridgeProductSubscriptionState()
        _ = try state.open(
            decode(
                BridgeProductSubscriptionOpenRequest.self,
                object: fileSubscriptionOpenObject()
            ))
        let beforeFailure = try #require(
            state.snapshot(subscriptionId: "file-subscription-1")
        )
        let exhaustedRevision = try activeSubscription(
            subscriptionId: "file-subscription-1",
            subscriptionKind: .fileMetadata,
            workerDerivationEpoch: 2,
            interestRevision: BridgeProductWireContract.maximumSafeInteger,
            interestSha256: String(repeating: "0", count: 64)
        )

        // Act / Assert
        #expect(throws: BridgeProductSubscriptionStateError.interestRevisionExhausted) {
            _ = try state.reconcile(activeSubscriptions: [exhaustedRevision])
        }
        #expect(state.snapshot(subscriptionId: "file-subscription-1") == beforeFailure)
        #expect(state.pendingBarrierIntentCount == 0)
    }

    private func activeSubscription(
        subscriptionId: String,
        subscriptionKind: BridgeProductSubscriptionKind,
        workerDerivationEpoch: Int,
        interestRevision: Int,
        interestSha256: String
    ) throws -> BridgeProductActiveSubscription {
        try decode(
            BridgeProductActiveSubscription.self,
            object: [
                "interestRevision": interestRevision,
                "interestSha256": interestSha256,
                "subscriptionId": subscriptionId,
                "subscriptionKind": subscriptionKind.rawValue,
                "workerDerivationEpoch": workerDerivationEpoch,
            ]
        )
    }

    private func fileSubscriptionOpenObject() -> [String: Any] {
        surfaceControlIdentity(
            kind: "subscription.open",
            requestId: "request-file-open-1",
            requestSequence: 1,
            epoch: 2
        ).merging([
            "subscription": [
                "source": [
                    "cwdScope": NSNull(),
                    "freshness": "live",
                    "includeStatuses": true,
                    "repoId": "00000000-0000-4000-8000-000000000001",
                    "rootPathToken": "root-token-1",
                    "worktreeId": "00000000-0000-4000-8000-000000000002",
                ],
                "subscriptionKind": "file.metadata",
            ],
            "subscriptionId": "file-subscription-1",
        ]) { _, new in new }
    }

    private func reviewSubscriptionOpenObject() -> [String: Any] {
        surfaceControlIdentity(
            kind: "subscription.open",
            requestId: "request-review-open-1",
            requestSequence: 2,
            epoch: 7
        ).merging([
            "subscription": ["subscriptionKind": "review.metadata"],
            "subscriptionId": "review-subscription-1",
        ]) { _, new in new }
    }

    private func stagedFileUpdateObject() throws -> [String: Any] {
        surfaceControlIdentity(
            kind: "subscription.updateBatch",
            requestId: "request-file-update-1",
            requestSequence: 3,
            epoch: 2
        ).merging([
            "baseInterestRevision": 0,
            "baseInterestSha256":
                try BridgeProductSubscriptionInterestState
                .fileMetadata(interests: [], pathScope: [])
                .sha256Hex(),
            "batchCount": 2,
            "batchIndex": 0,
            "delta": [
                "add": [["lane": "foreground", "path": "src/file.ts"]],
                "addPathScope": [],
                "removePathScope": [],
                "removePaths": [],
                "subscriptionKind": "file.metadata",
            ],
            "subscriptionId": "file-subscription-1",
            "subscriptionKind": "file.metadata",
            "targetInterestRevision": 1,
            "targetInterestSha256": String(repeating: "0", count: 64),
            "totalDeltaItemCount": 2,
            "updateId": "file-update-1",
        ]) { _, new in new }
    }

    private func surfaceControlIdentity(
        kind: String,
        requestId: String,
        requestSequence: Int,
        epoch: Int
    ) -> [String: Any] {
        [
            "kind": kind,
            "paneSessionId": "pane-session-1",
            "requestId": requestId,
            "requestSequence": requestSequence,
            "wireVersion": BridgeProductWireContract.version,
            "workerDerivationEpoch": epoch,
            "workerInstanceId": "worker-instance-1",
        ]
    }

    private func decode<DecodedValue: Decodable>(
        _ type: DecodedValue.Type,
        object: [String: Any]
    ) throws -> DecodedValue {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try BridgeProductStrictJSON.decode(type, from: data)
    }
}
