import Foundation
import Testing

@testable import AgentStudioBridge

struct BridgeProductSubscriptionRollingHistoryTests {
    @Test("ring storage remains bounded across wraparound and preserves exact UTF-8 IDs")
    func ringStorageRemainsBounded() {
        // Arrange
        var history = BridgeProductCommittedUpdateHistory(capacity: 2)
        let composed = BridgeProductSubscriptionExactUTF8Identity("caf\u{00E9}")
        let decomposed = BridgeProductSubscriptionExactUTF8Identity("cafe\u{0301}")
        history.insert(composed)
        history.insert(decomposed)
        #expect(history.count == 2)
        #expect(history.contains(composed))
        #expect(history.contains(decomposed))

        // Act / Assert
        for index in 0..<1100 {
            let identifier = BridgeProductSubscriptionExactUTF8Identity("id-\(index)")
            history.insert(identifier)
            #expect(history.count == 2)
            #expect(history.contains(identifier))
        }
        #expect(!history.contains(composed))
        #expect(!history.contains(decomposed))
        history.removeAll()
        #expect(history.isEmpty)
        history.insert(composed)
        #expect(history.count == 1)
    }

    @Test("one subscription continues beyond the default committed ID window")
    func subscriptionOutlivesHistoryWindow() throws {
        // Arrange
        var state = try makeState(capacity: 1024)

        // Act: every update changes the lane, without replacing the subscription.
        for index in 0..<1100 {
            try commit(updateId: "update-\(index)", to: &state)
        }

        // Assert
        #expect(state.subscriptionCount == 1)
        #expect(state.snapshot(subscriptionId: subscriptionId)?.interestRevision == 1100)
        #expect(state.pendingBarrierIntentCount == 0)
    }

    @Test("rolling history rejects recent IDs and evicts in successful commit order", arguments: [1, 2, 3])
    func historyRollsInCommitOrder(capacity: Int) throws {
        // Arrange
        var state = try makeState(capacity: capacity)
        for index in 0..<capacity {
            try commit(updateId: "update-\(index)", to: &state)
        }
        let originalRequest = try makeUpdate(updateId: "next", state: state)

        // Act
        try commit(updateId: "next", to: &state)

        // Assert: the evicted label may identify new work, but an old request
        // carrying an obsolete base revision remains rejected.
        #expect(throws: BridgeProductSubscriptionStateError.interestBaseMismatch) {
            _ = try state.apply(originalRequest)
        }
        #expect(throws: BridgeProductSubscriptionStateError.committedUpdateIdReused) {
            _ = try state.apply(makeUpdate(updateId: "next", state: state))
        }
        try commit(updateId: "update-0", to: &state)
        #expect(throws: BridgeProductSubscriptionStateError.committedUpdateIdReused) {
            _ = try state.apply(makeUpdate(updateId: "update-0", state: state))
        }
        #expect(state.snapshot(subscriptionId: subscriptionId)?.interestRevision == capacity + 2)
    }

    @Test("rejected updates cannot evict committed history or change source state")
    func rejectedUpdateDoesNotAdvanceHistory() throws {
        // Arrange
        var state = try makeState(capacity: 2)
        try commit(updateId: "first", to: &state)
        try commit(updateId: "second", to: &state)
        let before = state.snapshot(subscriptionId: subscriptionId)
        let invalid = try makeUpdate(updateId: "invalid", state: state, invalidHash: true)

        // Act / Assert
        #expect(throws: BridgeProductSubscriptionStateError.interestTargetHashMismatch) {
            _ = try state.apply(invalid)
        }
        #expect(state.snapshot(subscriptionId: subscriptionId) == before)
        #expect(throws: BridgeProductSubscriptionStateError.committedUpdateIdReused) {
            _ = try state.apply(makeUpdate(updateId: "first", state: state))
        }
        try commit(updateId: "third", to: &state)
        try commit(updateId: "first", to: &state)
    }

    @Test("candidate rollover cannot evict IDs from the uncommitted parent state")
    func candidateHistoryIsValueIsolated() throws {
        // Arrange
        var state = try makeState(capacity: 2)
        try commit(updateId: "first", to: &state)
        try commit(updateId: "second", to: &state)
        var candidate = state

        // Act
        try commit(updateId: "third", to: &candidate)

        // Assert: protocol commit may discard a candidate if frame admission fails.
        #expect(throws: BridgeProductSubscriptionStateError.committedUpdateIdReused) {
            _ = try state.apply(makeUpdate(updateId: "first", state: state))
        }
        try commit(updateId: "first", to: &candidate)
        #expect(state.snapshot(subscriptionId: subscriptionId)?.interestRevision == 2)
        #expect(candidate.snapshot(subscriptionId: subscriptionId)?.interestRevision == 4)
    }

    @Test("staging and retained reconciliation preserve recent IDs while reset clears history")
    func stagingAndReconciliationRespectHistoryLifetime() throws {
        // Arrange
        var state = try makeState(capacity: 2)
        try commit(updateId: "first", to: &state)
        try commit(updateId: "second", to: &state)
        let before = try #require(state.snapshot(subscriptionId: subscriptionId))
        let complete = try makeUpdate(updateId: "staged", state: state)
        var stagedObject = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(complete)) as? [String: Any]
        )
        stagedObject["batchCount"] = 2
        stagedObject["totalDeltaItemCount"] = 2

        // Act: an incomplete update does not consume a committed-history slot.
        #expect(try state.apply(decode(BridgeProductSubscriptionUpdateBatchRequest.self, stagedObject)) == .staged)
        #expect(throws: BridgeProductSubscriptionStateError.committedUpdateIdReused) {
            _ = try state.apply(makeUpdate(updateId: "first", state: state))
        }
        let claim = try decode(
            BridgeProductActiveSubscription.self,
            [
                "subscriptionId": subscriptionId,
                "subscriptionKind": "review.metadata",
                "workerDerivationEpoch": 1,
                "interestRevision": before.interestRevision,
                "interestSha256": before.interestSha256,
            ])
        let retained = try state.reconcile(activeSubscriptions: [claim])

        // Assert: retained clears only staging, whereas a reset clears the history.
        #expect(retained.reconciliation.map(\.dispositionName) == ["retained"])
        #expect(state.snapshot(subscriptionId: subscriptionId) == before)
        #expect(throws: BridgeProductSubscriptionStateError.committedUpdateIdReused) {
            _ = try state.apply(makeUpdate(updateId: "first", state: state))
        }
        let staleClaim = try decode(
            BridgeProductActiveSubscription.self,
            [
                "subscriptionId": subscriptionId,
                "subscriptionKind": "review.metadata",
                "workerDerivationEpoch": 1,
                "interestRevision": before.interestRevision,
                "interestSha256": String(repeating: "0", count: 64),
            ])
        let reset = try state.reconcile(activeSubscriptions: [staleClaim])
        #expect(reset.reconciliation.map(\.dispositionName) == ["reset"])
        try commit(updateId: "first", to: &state)
        try commit(updateId: "second", to: &state)
        try commit(updateId: "third", to: &state)
        #expect(throws: BridgeProductSubscriptionStateError.committedUpdateIdReused) {
            _ = try state.apply(makeUpdate(updateId: "second", state: state))
        }
    }

    private let subscriptionId = "rolling-review-subscription"

    private func makeState(capacity: Int) throws -> BridgeProductSubscriptionState {
        var state = BridgeProductSubscriptionState(maximumCommittedUpdateIdCount: capacity)
        _ = try state.open(
            decode(
                BridgeProductSubscriptionOpenRequest.self,
                [
                    "kind": "subscription.open",
                    "wireVersion": BridgeProductWireContract.version,
                    "paneSessionId": "rolling-pane",
                    "workerInstanceId": "rolling-worker",
                    "workerDerivationEpoch": 1,
                    "requestId": "rolling-open",
                    "requestSequence": 1,
                    "subscriptionId": subscriptionId,
                    "subscription": ["subscriptionKind": "review.metadata"],
                ]))
        return state
    }

    private func commit(updateId: String, to state: inout BridgeProductSubscriptionState) throws {
        let request = try makeUpdate(updateId: updateId, state: state)
        guard case .committed = try state.apply(request) else {
            Issue.record("Expected one complete interest commit")
            return
        }
        #expect(state.drainCommitBarrierIntents().count == 1)
    }

    private func makeUpdate(
        updateId: String,
        state: BridgeProductSubscriptionState,
        invalidHash: Bool = false
    ) throws -> BridgeProductSubscriptionUpdateBatchRequest {
        let snapshot = try #require(state.snapshot(subscriptionId: subscriptionId))
        let lane: BridgeProductDemandLane = snapshot.interestRevision.isMultiple(of: 2) ? .foreground : .visible
        let target = BridgeProductSubscriptionInterestState.reviewMetadata(interests: [
            try .init(itemIds: ["rolling-item"], lane: lane)
        ])
        return try decode(
            BridgeProductSubscriptionUpdateBatchRequest.self,
            [
                "kind": "subscription.updateBatch",
                "wireVersion": BridgeProductWireContract.version,
                "paneSessionId": "rolling-pane",
                "workerInstanceId": "rolling-worker",
                "workerDerivationEpoch": 1,
                "requestId": "request-\(snapshot.interestRevision + 2)",
                "requestSequence": snapshot.interestRevision + 2,
                "subscriptionId": subscriptionId,
                "subscriptionKind": "review.metadata",
                "updateId": updateId,
                "batchCount": 1,
                "batchIndex": 0,
                "totalDeltaItemCount": 1,
                "baseInterestRevision": snapshot.interestRevision,
                "targetInterestRevision": snapshot.interestRevision + 1,
                "baseInterestSha256": snapshot.interestSha256,
                "targetInterestSha256": invalidHash ? String(repeating: "0", count: 64) : try target.sha256Hex(),
                "delta": [
                    "subscriptionKind": "review.metadata",
                    "add": [["itemId": "rolling-item", "lane": lane.rawValue]],
                    "removeItemIds": [],
                ],
            ])
    }

    private func decode<Value: Decodable>(_ type: Value.Type, _ object: [String: Any]) throws -> Value {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
    }
}
