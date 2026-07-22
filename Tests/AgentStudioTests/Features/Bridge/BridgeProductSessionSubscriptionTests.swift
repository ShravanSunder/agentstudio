import Foundation
import Testing

@testable import AgentStudio

struct BridgeProductSessionSubscriptionTests {
    private static let reviewEmptySHA256 = "1a71797cab8ed23c72233b7706b166a33049e4e87dfbc55b9e252f9c1843eca6"
    private static let fileEmptySHA256 = "51ce8b03041697e18e2a24d5311e14bb1df4da119635bb84246c1b047316e46b"
    private static let reviewTwoItemSHA256 = "2535176c2a822c1f5007dd72a7987b7c0a1b6e9af1bc28324ec4618b43f71ebd"

    @Test("subscription opens establish canonical empty state and exact identities")
    func subscriptionOpensEstablishCanonicalEmptyStateAndExactIdentities() throws {
        // Arrange
        var state = BridgeProductSubscriptionState()
        let reviewOpen = try makeOpenRequest(
            subscriptionId: "review-subscription-1",
            subscriptionKind: .reviewMetadata,
            workerDerivationEpoch: 7
        )
        let fileOpen = try makeOpenRequest(
            subscriptionId: "file-subscription-1",
            subscriptionKind: .fileMetadata,
            workerDerivationEpoch: 11
        )

        // Act
        let reviewReceipt = try state.open(reviewOpen)
        let fileReceipt = try state.open(fileOpen)

        // Assert
        #expect(reviewReceipt.interestRevision == 0)
        #expect(reviewReceipt.interestSha256 == Self.reviewEmptySHA256)
        #expect(fileReceipt.interestRevision == 0)
        #expect(fileReceipt.interestSha256 == Self.fileEmptySHA256)
        #expect(state.subscriptionCount == 2)
        #expect(
            state.snapshot(subscriptionId: "review-subscription-1")?.interestState
                == .reviewMetadata(interests: [])
        )
        #expect(
            state.snapshot(subscriptionId: "file-subscription-1")?.interestState
                == .fileMetadata(interests: [], pathScope: [])
        )
        #expect(throws: BridgeProductSubscriptionStateError.duplicateSubscriptionId) {
            _ = try state.open(reviewOpen)
        }
    }

    @Test("multi-batch updates expose no committed mutation before the final valid batch")
    func multiBatchUpdatesCommitOnceAndQueueOneBarrier() throws {
        // Arrange
        var state = BridgeProductSubscriptionState()
        _ = try state.open(
            makeOpenRequest(
                subscriptionId: "review-subscription-1",
                subscriptionKind: .reviewMetadata,
                workerDerivationEpoch: 7
            ))
        let firstBatch = try makeBatchRequest(
            BatchFixture(
                subscriptionId: "review-subscription-1",
                subscriptionKind: .reviewMetadata,
                workerDerivationEpoch: 7,
                updateId: "review-update-1",
                batchIndex: 0,
                batchCount: 2,
                totalDeltaItemCount: 2,
                baseInterestSha256: Self.reviewEmptySHA256,
                targetInterestSha256: Self.reviewTwoItemSHA256,
                delta: reviewDelta(additions: [("review-item-1", .foreground)])
            ))
        let finalBatch = try makeBatchRequest(
            BatchFixture(
                subscriptionId: "review-subscription-1",
                subscriptionKind: .reviewMetadata,
                workerDerivationEpoch: 7,
                updateId: "review-update-1",
                batchIndex: 1,
                batchCount: 2,
                totalDeltaItemCount: 2,
                baseInterestSha256: Self.reviewEmptySHA256,
                targetInterestSha256: Self.reviewTwoItemSHA256,
                delta: reviewDelta(additions: [("review-item-2", .visible)])
            ))

        // Act
        let stagedResult = try state.apply(firstBatch)
        let stagedSnapshot = try #require(state.snapshot(subscriptionId: "review-subscription-1"))
        let committedResult = try state.apply(finalBatch)
        let committedSnapshot = try #require(state.snapshot(subscriptionId: "review-subscription-1"))
        let queuedBarriers = state.drainCommitBarrierIntents()

        // Assert
        #expect(stagedResult == .staged)
        #expect(stagedSnapshot.interestRevision == 0)
        #expect(stagedSnapshot.interestSha256 == Self.reviewEmptySHA256)
        #expect(stagedSnapshot.interestState == .reviewMetadata(interests: []))
        #expect(stagedSnapshot.hasStagedUpdate)
        let expectedBarrier = BridgeProductSubscriptionCommitBarrierIntent(
            subscriptionId: "review-subscription-1",
            subscriptionKind: .reviewMetadata,
            workerDerivationEpoch: 7,
            interestRevision: 1,
            interestSha256: Self.reviewTwoItemSHA256,
            updateId: "review-update-1"
        )
        #expect(committedResult == .committed(expectedBarrier))
        #expect(committedSnapshot.interestRevision == 1)
        #expect(committedSnapshot.interestSha256 == Self.reviewTwoItemSHA256)
        #expect(!committedSnapshot.hasStagedUpdate)
        #expect(queuedBarriers == [expectedBarrier])
        #expect(state.drainCommitBarrierIntents().isEmpty)
    }

    @Test("hostile batches reject without partial committed mutation")
    func hostileBatchesRejectWithoutPartialCommittedMutation() throws {
        // Arrange
        let unknownBatch = try makeUnknownSubscriptionBatch()
        var unknownState = BridgeProductSubscriptionState()

        var gapState = try makeReviewState()
        let gapBatch = try makeGapBatch()

        var duplicateState = try makeReviewState()
        let duplicateFirstBatch = try makeBatchRequest(
            BatchFixture(
                subscriptionId: "review-subscription-1",
                subscriptionKind: .reviewMetadata,
                workerDerivationEpoch: 7,
                updateId: "duplicate-update",
                batchIndex: 0,
                batchCount: 2,
                totalDeltaItemCount: 2,
                baseInterestSha256: Self.reviewEmptySHA256,
                targetInterestSha256: Self.reviewTwoItemSHA256,
                delta: reviewDelta(additions: [("review-item-1", .foreground)])
            ))
        let duplicateFinalBatch = try makeBatchRequest(
            BatchFixture(
                subscriptionId: "review-subscription-1",
                subscriptionKind: .reviewMetadata,
                workerDerivationEpoch: 7,
                updateId: "duplicate-update",
                batchIndex: 1,
                batchCount: 2,
                totalDeltaItemCount: 2,
                baseInterestSha256: Self.reviewEmptySHA256,
                targetInterestSha256: Self.reviewTwoItemSHA256,
                delta: reviewDelta(additions: [("review-item-1", .visible)])
            ))
        _ = try duplicateState.apply(duplicateFirstBatch)

        var crossWiredState = try makeReviewState()
        let crossWiredBatch = try makeBatchRequest(
            BatchFixture(
                subscriptionId: "review-subscription-1",
                subscriptionKind: .fileMetadata,
                workerDerivationEpoch: 7,
                updateId: "cross-wired-update",
                batchIndex: 0,
                batchCount: 1,
                totalDeltaItemCount: 1,
                baseInterestSha256: Self.fileEmptySHA256,
                targetInterestSha256: String(repeating: "0", count: 64),
                delta: fileDelta(additions: [("src/file.ts", .foreground)])
            ))

        var wrongHashState = try makeReviewState()
        let wrongHashBatch = try makeBatchRequest(
            BatchFixture(
                subscriptionId: "review-subscription-1",
                subscriptionKind: .reviewMetadata,
                workerDerivationEpoch: 7,
                updateId: "wrong-hash-update",
                batchIndex: 0,
                batchCount: 1,
                totalDeltaItemCount: 1,
                baseInterestSha256: Self.reviewEmptySHA256,
                targetInterestSha256: String(repeating: "0", count: 64),
                delta: reviewDelta(additions: [("review-item-1", .foreground)])
            ))

        // Act / Assert
        #expect(throws: BridgeProductSubscriptionStateError.unknownSubscriptionId) {
            _ = try unknownState.apply(unknownBatch)
        }
        #expect(
            throws: BridgeProductSubscriptionStateError.batchSequenceGap(
                expectedBatchIndex: 0,
                receivedBatchIndex: 1
            )
        ) {
            _ = try gapState.apply(gapBatch)
        }
        #expect(throws: BridgeProductSubscriptionStateError.duplicateDeltaMember) {
            _ = try duplicateState.apply(duplicateFinalBatch)
        }
        #expect(throws: BridgeProductSubscriptionStateError.subscriptionKindMismatch) {
            _ = try crossWiredState.apply(crossWiredBatch)
        }
        #expect(throws: BridgeProductSubscriptionStateError.interestTargetHashMismatch) {
            _ = try wrongHashState.apply(wrongHashBatch)
        }

        let duplicateSnapshot = try #require(
            duplicateState.snapshot(subscriptionId: "review-subscription-1")
        )
        #expect(duplicateSnapshot.interestRevision == 0)
        #expect(duplicateSnapshot.interestSha256 == Self.reviewEmptySHA256)
        #expect(duplicateSnapshot.hasStagedUpdate)
        #expect(duplicateState.pendingBarrierIntentCount == 0)
        #expect(wrongHashState.snapshot(subscriptionId: "review-subscription-1")?.interestRevision == 0)
        #expect(wrongHashState.pendingBarrierIntentCount == 0)
    }

    @Test("file interest updates preserve composed and decomposed UTF-8 identities")
    func fileInterestUpdatesPreserveExactUTF8Identity() throws {
        // Arrange
        let composedPath = "caf\u{00e9}.txt"
        let decomposedPath = "cafe\u{0301}.txt"
        let expectedState = BridgeProductSubscriptionInterestState.fileMetadata(
            interests: [
                try BridgeProductFileMetadataInterestStateGroup(
                    lane: .foreground,
                    paths: [composedPath]
                ),
                try BridgeProductFileMetadataInterestStateGroup(
                    lane: .visible,
                    paths: [decomposedPath]
                ),
            ],
            pathScope: []
        )
        let targetSHA256 = try expectedState.sha256Hex()
        var state = BridgeProductSubscriptionState()
        _ = try state.open(
            makeOpenRequest(
                subscriptionId: "file-subscription-1",
                subscriptionKind: .fileMetadata,
                workerDerivationEpoch: 3
            ))
        let batch = try makeBatchRequest(
            BatchFixture(
                subscriptionId: "file-subscription-1",
                subscriptionKind: .fileMetadata,
                workerDerivationEpoch: 3,
                updateId: "file-update-1",
                batchIndex: 0,
                batchCount: 1,
                totalDeltaItemCount: 2,
                baseInterestSha256: Self.fileEmptySHA256,
                targetInterestSha256: targetSHA256,
                delta: fileDelta(
                    additions: [
                        (composedPath, .foreground),
                        (decomposedPath, .visible),
                    ]
                )
            ))

        // Act
        _ = try state.apply(batch)

        // Assert
        let snapshot = try #require(state.snapshot(subscriptionId: "file-subscription-1"))
        #expect(Data(composedPath.utf8) != Data(decomposedPath.utf8))
        #expect(snapshot.interestState == expectedState)
        #expect(snapshot.interestSha256 == targetSHA256)
    }

    @Test("surface reset is scoped and worker revoke clears every subscription fact")
    func surfaceResetIsScopedAndWorkerRevokeClearsAllState() throws {
        // Arrange
        var state = BridgeProductSubscriptionState()
        _ = try state.open(
            makeOpenRequest(
                subscriptionId: "review-subscription-1",
                subscriptionKind: .reviewMetadata,
                workerDerivationEpoch: 7
            ))
        _ = try state.open(
            makeOpenRequest(
                subscriptionId: "file-subscription-1",
                subscriptionKind: .fileMetadata,
                workerDerivationEpoch: 3
            ))
        _ = try state.apply(
            makeBatchRequest(
                BatchFixture(
                    subscriptionId: "review-subscription-1",
                    subscriptionKind: .reviewMetadata,
                    workerDerivationEpoch: 7,
                    updateId: "review-update-1",
                    batchIndex: 0,
                    batchCount: 1,
                    totalDeltaItemCount: 2,
                    baseInterestSha256: Self.reviewEmptySHA256,
                    targetInterestSha256: Self.reviewTwoItemSHA256,
                    delta: reviewDelta(
                        additions: [
                            ("review-item-1", .foreground),
                            ("review-item-2", .visible),
                        ]
                    )
                )))
        _ = try state.apply(
            makeBatchRequest(
                BatchFixture(
                    subscriptionId: "file-subscription-1",
                    subscriptionKind: .fileMetadata,
                    workerDerivationEpoch: 3,
                    updateId: "file-update-1",
                    batchIndex: 0,
                    batchCount: 2,
                    totalDeltaItemCount: 2,
                    baseInterestSha256: Self.fileEmptySHA256,
                    targetInterestSha256: String(repeating: "0", count: 64),
                    delta: fileDelta(additions: [("src/file.ts", .foreground)])
                )))

        // Act
        state.reset(surface: .review)

        // Assert
        #expect(state.snapshot(subscriptionId: "review-subscription-1") == nil)
        #expect(state.snapshot(subscriptionId: "file-subscription-1")?.hasStagedUpdate == true)
        #expect(state.subscriptionCount == 1)
        #expect(state.pendingBarrierIntentCount == 0)

        // Act
        state.revokeWorker()

        // Assert
        #expect(state.subscriptionCount == 0)
        #expect(state.pendingBarrierIntentCount == 0)
        #expect(state.snapshot(subscriptionId: "file-subscription-1") == nil)
    }

    @Test("subscription and barrier capacities reject without partial mutation")
    func boundedStateRejectsBeforeMutation() throws {
        // Arrange
        var subscriptionBoundedState = BridgeProductSubscriptionState(
            maximumSubscriptionCount: 1,
            maximumCommittedUpdateIdCount: 2,
            maximumPendingBarrierIntentCount: 1
        )
        _ = try subscriptionBoundedState.open(
            makeOpenRequest(
                subscriptionId: "review-subscription-1",
                subscriptionKind: .reviewMetadata,
                workerDerivationEpoch: 7
            ))
        let secondSubscription = try makeOpenRequest(
            subscriptionId: "file-subscription-1",
            subscriptionKind: .fileMetadata,
            workerDerivationEpoch: 3
        )

        var barrierBoundedState = BridgeProductSubscriptionState(
            maximumSubscriptionCount: 2,
            maximumCommittedUpdateIdCount: 2,
            maximumPendingBarrierIntentCount: 1
        )
        _ = try barrierBoundedState.open(
            makeOpenRequest(
                subscriptionId: "review-subscription-1",
                subscriptionKind: .reviewMetadata,
                workerDerivationEpoch: 7
            ))
        _ = try barrierBoundedState.open(secondSubscription)
        _ = try barrierBoundedState.apply(
            makeBatchRequest(
                BatchFixture(
                    subscriptionId: "review-subscription-1",
                    subscriptionKind: .reviewMetadata,
                    workerDerivationEpoch: 7,
                    updateId: "review-update-1",
                    batchIndex: 0,
                    batchCount: 1,
                    totalDeltaItemCount: 2,
                    baseInterestSha256: Self.reviewEmptySHA256,
                    targetInterestSha256: Self.reviewTwoItemSHA256,
                    delta: reviewDelta(
                        additions: [
                            ("review-item-1", .foreground),
                            ("review-item-2", .visible),
                        ]
                    )
                )))
        let fileState = BridgeProductSubscriptionInterestState.fileMetadata(
            interests: [
                try BridgeProductFileMetadataInterestStateGroup(
                    lane: .foreground,
                    paths: ["src/file.ts"]
                )
            ],
            pathScope: []
        )
        let fileBatch = try makeBatchRequest(
            BatchFixture(
                subscriptionId: "file-subscription-1",
                subscriptionKind: .fileMetadata,
                workerDerivationEpoch: 3,
                updateId: "file-update-1",
                batchIndex: 0,
                batchCount: 1,
                totalDeltaItemCount: 1,
                baseInterestSha256: Self.fileEmptySHA256,
                targetInterestSha256: try fileState.sha256Hex(),
                delta: fileDelta(additions: [("src/file.ts", .foreground)])
            ))

        // Act / Assert
        #expect(throws: BridgeProductSubscriptionStateError.subscriptionCapacityExceeded) {
            _ = try subscriptionBoundedState.open(secondSubscription)
        }
        #expect(subscriptionBoundedState.subscriptionCount == 1)
        #expect(throws: BridgeProductSubscriptionStateError.barrierIntentCapacityExceeded) {
            _ = try barrierBoundedState.apply(fileBatch)
        }
        #expect(
            barrierBoundedState.snapshot(subscriptionId: "file-subscription-1")?.interestRevision == 0
        )
        #expect(barrierBoundedState.pendingBarrierIntentCount == 1)
    }

    private func makeReviewState() throws -> BridgeProductSubscriptionState {
        var state = BridgeProductSubscriptionState()
        _ = try state.open(
            makeOpenRequest(
                subscriptionId: "review-subscription-1",
                subscriptionKind: .reviewMetadata,
                workerDerivationEpoch: 7
            ))
        return state
    }

    private func makeUnknownSubscriptionBatch() throws -> BridgeProductSubscriptionUpdateBatchRequest {
        try makeBatchRequest(
            BatchFixture(
                subscriptionId: "missing-subscription",
                subscriptionKind: .reviewMetadata,
                workerDerivationEpoch: 7,
                updateId: "missing-update",
                batchIndex: 0,
                batchCount: 1,
                totalDeltaItemCount: 1,
                baseInterestSha256: Self.reviewEmptySHA256,
                targetInterestSha256: String(repeating: "0", count: 64),
                delta: reviewDelta(additions: [("review-item-1", .foreground)])
            ))
    }

    private func makeGapBatch() throws -> BridgeProductSubscriptionUpdateBatchRequest {
        try makeBatchRequest(
            BatchFixture(
                subscriptionId: "review-subscription-1",
                subscriptionKind: .reviewMetadata,
                workerDerivationEpoch: 7,
                updateId: "gap-update",
                batchIndex: 1,
                batchCount: 2,
                totalDeltaItemCount: 2,
                baseInterestSha256: Self.reviewEmptySHA256,
                targetInterestSha256: Self.reviewTwoItemSHA256,
                delta: reviewDelta(additions: [("review-item-2", .visible)])
            ))
    }

    private func makeOpenRequest(
        subscriptionId: String,
        subscriptionKind: BridgeProductSubscriptionKind,
        workerDerivationEpoch: Int
    ) throws -> BridgeProductSubscriptionOpenRequest {
        var subscription: [String: Any] = [
            "subscriptionKind": subscriptionKind.rawValue
        ]
        if subscriptionKind == .fileMetadata {
            subscription["source"] = [
                "cwdScope": NSNull(),
                "freshness": "live",
                "includeStatuses": true,
                "repoId": "00000000-0000-4000-8000-000000000001",
                "rootPathToken": "root-token-1",
                "worktreeId": "00000000-0000-4000-8000-000000000002",
            ]
        }
        return try decode(
            BridgeProductSubscriptionOpenRequest.self,
            object: [
                "kind": "subscription.open",
                "paneSessionId": "pane-session-1",
                "requestId": "open:\(subscriptionId)",
                "requestSequence": 1,
                "subscription": subscription,
                "subscriptionId": subscriptionId,
                "wireVersion": BridgeProductWireContract.version,
                "workerDerivationEpoch": workerDerivationEpoch,
                "workerInstanceId": "worker-instance-1",
            ]
        )
    }

    private func makeBatchRequest(
        _ fixture: BatchFixture
    ) throws -> BridgeProductSubscriptionUpdateBatchRequest {
        try decode(
            BridgeProductSubscriptionUpdateBatchRequest.self,
            object: [
                "baseInterestRevision": 0,
                "baseInterestSha256": fixture.baseInterestSha256,
                "batchCount": fixture.batchCount,
                "batchIndex": fixture.batchIndex,
                "delta": fixture.delta,
                "kind": "subscription.updateBatch",
                "paneSessionId": "pane-session-1",
                "requestId": "batch:\(fixture.updateId):\(fixture.batchIndex)",
                "requestSequence": fixture.batchIndex + 2,
                "subscriptionId": fixture.subscriptionId,
                "subscriptionKind": fixture.subscriptionKind.rawValue,
                "targetInterestRevision": 1,
                "targetInterestSha256": fixture.targetInterestSha256,
                "totalDeltaItemCount": fixture.totalDeltaItemCount,
                "updateId": fixture.updateId,
                "wireVersion": BridgeProductWireContract.version,
                "workerDerivationEpoch": fixture.workerDerivationEpoch,
                "workerInstanceId": "worker-instance-1",
            ]
        )
    }

    private func reviewDelta(
        additions: [(String, BridgeProductDemandLane)]
    ) -> [String: Any] {
        [
            "add": additions.map { itemId, lane in
                ["itemId": itemId, "lane": lane.rawValue]
            },
            "removeItemIds": [],
            "subscriptionKind": BridgeProductSubscriptionKind.reviewMetadata.rawValue,
        ]
    }

    private func fileDelta(
        additions: [(String, BridgeProductDemandLane)]
    ) -> [String: Any] {
        [
            "add": additions.map { path, lane in
                ["lane": lane.rawValue, "path": path]
            },
            "addPathScope": [],
            "removePathScope": [],
            "removePaths": [],
            "subscriptionKind": BridgeProductSubscriptionKind.fileMetadata.rawValue,
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

private struct BatchFixture {
    let subscriptionId: String
    let subscriptionKind: BridgeProductSubscriptionKind
    let workerDerivationEpoch: Int
    let updateId: String
    let batchIndex: Int
    let batchCount: Int
    let totalDeltaItemCount: Int
    let baseInterestSha256: String
    let targetInterestSha256: String
    let delta: [String: Any]
}
