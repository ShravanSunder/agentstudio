import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge product session control mutation boundary")
struct BridgeProductSessionControlMutationTests {
    @Test("raw subscription controls stage then commit once with a barrier")
    func successfulMultiBatchUpdateCommitsOnce() async throws {
        // Arrange
        let interestFixture = try ReviewInterestFixture.make()
        let harness = try await RawControlSessionHarness.opened()
        let openEffects = try await openReviewSubscription(
            harness,
            interestFixture: interestFixture
        )
        let openedSnapshot = try #require(
            await harness.session.subscriptionSnapshot(subscriptionId: reviewSubscriptionId)
        )
        let firstBatchRequestBytes = try jsonData(
            reviewUpdateBatchObject(
                requestSequence: 3,
                batchIndex: 0,
                itemId: "review-item-1",
                lane: "foreground",
                interestFixture: interestFixture
            ))
        let firstBatchResponseBytes = try jsonData(
            reviewUpdateAcceptedObject(
                requestSequence: 3,
                batchIndex: 0,
                disposition: "staged",
                interestFixture: interestFixture
            ))

        // Act
        let firstBatchEffects = try await harness.execute(
            requestBytes: firstBatchRequestBytes,
            responseBytes: firstBatchResponseBytes
        )
        let stagedSnapshot = try #require(
            await harness.session.subscriptionSnapshot(subscriptionId: reviewSubscriptionId)
        )

        // Assert
        guard case .subscriptionOpened(let committedOpenedSnapshot) = openEffects else {
            Issue.record("Expected a committed subscription-open effect")
            return
        }
        #expect(committedOpenedSnapshot == openedSnapshot)
        #expect(firstBatchEffects == .noEffect)
        #expect(stagedSnapshot.hasStagedUpdate)
        #expect(stagedSnapshot.interestRevision == 0)
        #expect(stagedSnapshot.interestSha256 == interestFixture.emptySHA256)
        #expect(stagedSnapshot.interestState == interestFixture.emptyState)

        let finalBatchRequestBytes = try jsonData(
            reviewUpdateBatchObject(
                requestSequence: 4,
                batchIndex: 1,
                itemId: "review-item-2",
                lane: "visible",
                interestFixture: interestFixture
            ))
        let finalBatchResponseBytes = try jsonData(
            reviewUpdateAcceptedObject(
                requestSequence: 4,
                batchIndex: 1,
                disposition: "committed",
                interestFixture: interestFixture
            ))

        let finalBatchEffects = try await harness.execute(
            requestBytes: finalBatchRequestBytes,
            responseBytes: finalBatchResponseBytes
        )
        let committedSnapshot = try #require(
            await harness.session.subscriptionSnapshot(subscriptionId: reviewSubscriptionId)
        )
        let sessionAfterCommit = await harness.session.snapshot
        let retryAdmission = await harness.begin(finalBatchRequestBytes)
        let subscriptionAfterRetry = await harness.session.subscriptionSnapshot(
            subscriptionId: reviewSubscriptionId
        )

        guard
            case .subscriptionInterestsCommitted(
                let committedBarrier,
                let committedEffectSnapshot
            ) = finalBatchEffects
        else {
            Issue.record("Expected a committed subscription-interest effect")
            return
        }
        #expect(
            committedBarrier
                == BridgeProductSubscriptionCommitBarrierIntent(
                    subscriptionId: reviewSubscriptionId,
                    subscriptionKind: .reviewMetadata,
                    workerDerivationEpoch: reviewEpoch,
                    interestRevision: 1,
                    interestSha256: interestFixture.targetSHA256,
                    updateId: reviewUpdateId
                )
        )
        #expect(committedEffectSnapshot == committedSnapshot)
        #expect(committedSnapshot.interestRevision == 1)
        #expect(committedSnapshot.interestSha256 == interestFixture.targetSHA256)
        #expect(committedSnapshot.interestState == interestFixture.targetState)
        #expect(!committedSnapshot.hasStagedUpdate)
        #expect(retryAdmission == .replay(exactResponseBytes: finalBatchResponseBytes))
        #expect(subscriptionAfterRetry == committedSnapshot)
        #expect((await harness.session.snapshot) == sessionAfterCommit)
    }

    @Test("every accepted update response identity field is atomic on mismatch")
    func updateAcceptedFieldMismatchesLeavePendingStateUnchanged() async throws {
        // Arrange
        let interestFixture = try ReviewInterestFixture.make()
        let harness = try await RawControlSessionHarness.opened()
        _ = try await openReviewSubscription(harness, interestFixture: interestFixture)
        try await stageFirstReviewBatch(harness, interestFixture: interestFixture)
        let finalRequestBytes = try jsonData(
            reviewUpdateBatchObject(
                requestSequence: 4,
                batchIndex: 1,
                itemId: "review-item-2",
                lane: "visible",
                interestFixture: interestFixture
            ))
        let finalToken = try await harness.beginExecution(finalRequestBytes)
        let pendingSessionSnapshot = await harness.session.snapshot
        let stagedSubscriptionSnapshot = try #require(
            await harness.session.subscriptionSnapshot(subscriptionId: reviewSubscriptionId)
        )
        let correctResponseObject = reviewUpdateAcceptedObject(
            requestSequence: 4,
            batchIndex: 1,
            disposition: "committed",
            interestFixture: interestFixture
        )
        let mismatchFixtures = try updateResponseMismatchFixtures(
            correctResponseObject,
            interestFixture: interestFixture
        )

        // Act / Assert
        for mismatchFixture in mismatchFixtures {
            await expectCompletionError(
                .mismatchedControlResponse,
                context: mismatchFixture.name,
                session: harness.session,
                token: finalToken,
                responseBytes: mismatchFixture.bytes
            )
            #expect(
                (await harness.session.snapshot) == pendingSessionSnapshot,
                "\(mismatchFixture.name) must preserve the replay admission"
            )
            #expect(
                await harness.session.subscriptionSnapshot(subscriptionId: reviewSubscriptionId)
                    == stagedSubscriptionSnapshot,
                "\(mismatchFixture.name) must preserve the staged subscription"
            )
        }

        let correctResponseBytes = try jsonData(correctResponseObject)
        let completionEffects = try await harness.session.completeControl(
            token: finalToken,
            exactResponseBytes: correctResponseBytes
        )

        guard case .subscriptionInterestsCommitted(let barrier, _) = completionEffects else {
            Issue.record("Expected a committed subscription-interest effect")
            return
        }
        #expect(barrier.updateId == reviewUpdateId)
        #expect((await harness.session.snapshot).controlReplay.nextExpectedRequestSequence == 5)
    }

    @Test("request error completes replay without applying the candidate open")
    func requestErrorDoesNotApplyCandidateMutation() async throws {
        // Arrange
        let harness = try await RawControlSessionHarness.opened()
        let requestBytes = try jsonData(reviewSubscriptionOpenObject(requestSequence: 2))
        let responseBytes = try jsonData(
            requestErrorObject(
                requestId: reviewSubscriptionOpenRequestId(requestSequence: 2),
                requestSequence: 2
            ))
        let token = try await harness.beginExecution(requestBytes)

        // Act
        let effects = try await harness.session.completeControl(
            token: token,
            exactResponseBytes: responseBytes
        )
        let subscriptionAfterError = await harness.session.subscriptionSnapshot(
            subscriptionId: reviewSubscriptionId
        )
        let completedSnapshot = await harness.session.snapshot
        let retryAdmission = await harness.begin(requestBytes)

        // Assert
        #expect(effects == .noEffect)
        #expect(subscriptionAfterError == nil)
        #expect(completedSnapshot.pendingRequestKind == nil)
        #expect(completedSnapshot.controlReplay.nextExpectedRequestSequence == 3)
        #expect(completedSnapshot.controlReplay.replayableRequestSequence == 2)
        #expect(retryAdmission == .replay(exactResponseBytes: responseBytes))
        #expect(
            await harness.session.subscriptionSnapshot(subscriptionId: reviewSubscriptionId) == nil
        )
    }

    @Test("invalid bytes and cross-wired responses never become replay entries")
    func invalidAndCrossWiredBytesCannotEnterReplay() async throws {
        // Arrange
        let interestFixture = try ReviewInterestFixture.make()
        let harness = try await RawControlSessionHarness.opened()
        let initialSnapshot = await harness.session.snapshot
        let invalidRequests = [
            Data("{".utf8),
            Data([0xFF]),
            Data(#"{"kind":"workerSession.open","kind":"product.call"}"#.utf8),
        ]

        // Act / Assert
        for invalidRequest in invalidRequests {
            #expect(
                await harness.begin(invalidRequest) == .rejected(.invalidRequest)
            )
            #expect((await harness.session.snapshot) == initialSnapshot)
        }

        let requestBytes = try jsonData(reviewSubscriptionOpenObject(requestSequence: 2))
        let token = try await harness.beginExecution(requestBytes)
        let pendingSnapshot = await harness.session.snapshot
        let invalidResponseBytes = [
            Data("{".utf8),
            try jsonData(
                reviewSubscriptionOpenAcceptedObject(
                    requestSequence: 2,
                    interestSHA256: interestFixture.emptySHA256
                ).merging(["unexpected": true]) { _, newValue in newValue }
            ),
        ]

        for responseBytes in invalidResponseBytes {
            await expectCompletionError(
                .invalidControlResponse,
                context: "invalid response bytes",
                session: harness.session,
                token: token,
                responseBytes: responseBytes
            )
            #expect((await harness.session.snapshot) == pendingSnapshot)
            #expect(
                await harness.session.subscriptionSnapshot(subscriptionId: reviewSubscriptionId)
                    == nil
            )
        }

        let crossWiredResponseBytes = try jsonData(
            controlIdentity(
                kind: "workerSession.accepted",
                requestId: reviewSubscriptionOpenRequestId(requestSequence: 2),
                requestSequence: 2
            ).merging(["result": NSNull()]) { _, newValue in newValue }
        )
        await expectCompletionError(
            .mismatchedControlResponse,
            context: "cross-wired response kind",
            session: harness.session,
            token: token,
            responseBytes: crossWiredResponseBytes
        )

        #expect((await harness.session.snapshot) == pendingSnapshot)
        #expect(pendingSnapshot.controlReplay.inFlightRequestSequence == 2)
        #expect(pendingSnapshot.controlReplay.replayableRequestSequence == 1)

        let correctResponseBytes = try jsonData(
            reviewSubscriptionOpenAcceptedObject(
                requestSequence: 2,
                interestSHA256: interestFixture.emptySHA256
            ))
        _ = try await harness.session.completeControl(
            token: token,
            exactResponseBytes: correctResponseBytes
        )
        let retryAdmission = await harness.begin(requestBytes)

        #expect(retryAdmission == .replay(exactResponseBytes: correctResponseBytes))
    }
}

private let paneSessionId = "pane-session-1"
private let workerInstanceId = "worker-instance-1"
private let reviewSubscriptionId = "review-subscription-1"
private let reviewUpdateId = "review-update-1"
private let reviewEpoch = 7

private struct ReviewInterestFixture: Sendable {
    let emptyState: BridgeProductSubscriptionInterestState
    let emptySHA256: String
    let targetState: BridgeProductSubscriptionInterestState
    let targetSHA256: String

    static func make() throws -> Self {
        let emptyState = BridgeProductSubscriptionInterestState.reviewMetadata(interests: [])
        let targetState = BridgeProductSubscriptionInterestState.reviewMetadata(
            interests: [
                try .init(itemIds: ["review-item-1"], lane: .foreground),
                try .init(itemIds: ["review-item-2"], lane: .visible),
            ]
        )
        return try Self(
            emptyState: emptyState,
            emptySHA256: emptyState.sha256Hex(),
            targetState: targetState,
            targetSHA256: targetState.sha256Hex()
        )
    }
}

private struct RawControlSessionHarness {
    let capabilityHeader: String
    let session: BridgeProductSession

    static func opened() async throws -> Self {
        let capabilityBytes = (0..<BridgeProductWireContract.capabilityByteLength).map(UInt8.init)
        let harness = try Self(
            capabilityHeader: BridgeProductCapabilityHeaderEncoding.encode(capabilityBytes),
            session: BridgeProductSession(
                paneSessionId: paneSessionId,
                workerInstanceId: workerInstanceId,
                capabilityBytes: capabilityBytes
            )
        )
        let requestBytes = try jsonData(workerSessionOpenObject())
        let responseBytes = try jsonData(
            controlIdentity(
                kind: "workerSession.accepted",
                requestId: "request-open-1",
                requestSequence: 1
            ).merging(["result": NSNull()]) { _, newValue in newValue }
        )
        _ = try await harness.execute(requestBytes: requestBytes, responseBytes: responseBytes)
        return harness
    }

    func begin(_ requestBytes: Data) async -> BridgeProductSessionControlAdmission {
        await session.beginControl(
            exactRequestBytes: requestBytes,
            presentedCapability: capabilityHeader
        )
    }

    func beginExecution(_ requestBytes: Data) async throws -> BridgeProductControlAdmissionToken {
        let admission = await begin(requestBytes)
        guard case .execute(let token, _) = admission else {
            Issue.record("Expected execution admission, received \(admission)")
            throw RawControlSessionHarnessError.expectedExecution
        }
        return token
    }

    func execute(
        requestBytes: Data,
        responseBytes: Data
    ) async throws -> BridgeProductSessionCompletionEffect {
        let token = try await beginExecution(requestBytes)
        return try await session.completeControl(
            token: token,
            exactResponseBytes: responseBytes
        )
    }
}

private enum RawControlSessionHarnessError: Error {
    case expectedExecution
}

private struct ResponseMismatchFixture: Sendable {
    let name: String
    let bytes: Data
}

private func openReviewSubscription(
    _ harness: RawControlSessionHarness,
    interestFixture: ReviewInterestFixture
) async throws -> BridgeProductSessionCompletionEffect {
    try await harness.execute(
        requestBytes: jsonData(reviewSubscriptionOpenObject(requestSequence: 2)),
        responseBytes: jsonData(
            reviewSubscriptionOpenAcceptedObject(
                requestSequence: 2,
                interestSHA256: interestFixture.emptySHA256
            ))
    )
}

private func stageFirstReviewBatch(
    _ harness: RawControlSessionHarness,
    interestFixture: ReviewInterestFixture
) async throws {
    _ = try await harness.execute(
        requestBytes: jsonData(
            reviewUpdateBatchObject(
                requestSequence: 3,
                batchIndex: 0,
                itemId: "review-item-1",
                lane: "foreground",
                interestFixture: interestFixture
            )),
        responseBytes: jsonData(
            reviewUpdateAcceptedObject(
                requestSequence: 3,
                batchIndex: 0,
                disposition: "staged",
                interestFixture: interestFixture
            ))
    )
}

private func expectCompletionError(
    _ expectedError: BridgeProductSessionError,
    context: String,
    session: BridgeProductSession,
    token: BridgeProductControlAdmissionToken,
    responseBytes: Data
) async {
    do {
        _ = try await session.completeControl(
            token: token,
            exactResponseBytes: responseBytes
        )
        Issue.record("Expected \(expectedError) for \(context)")
    } catch let error as BridgeProductSessionError {
        #expect(error == expectedError, "Unexpected error for \(context)")
    } catch {
        Issue.record("Unexpected non-session error for \(context): \(error)")
    }
}

private func updateResponseMismatchFixtures(
    _ correctResponse: [String: Any],
    interestFixture: ReviewInterestFixture
) throws -> [ResponseMismatchFixture] {
    try [
        responseMismatch("batchIndex", correctResponse, key: "batchIndex", value: 0),
        responseMismatch("disposition", correctResponse, key: "disposition", value: "staged"),
        responseMismatch("subscriptionId", correctResponse, key: "subscriptionId", value: "other-subscription"),
        responseMismatch("subscriptionKind", correctResponse, key: "subscriptionKind", value: "file.metadata"),
        responseMismatch("targetInterestRevision", correctResponse, key: "targetInterestRevision", value: 2),
        responseMismatch(
            "targetInterestSha256",
            correctResponse,
            key: "targetInterestSha256",
            value: interestFixture.emptySHA256
        ),
        responseMismatch("updateId", correctResponse, key: "updateId", value: "other-update"),
        responseMismatch("paneSessionId", correctResponse, key: "paneSessionId", value: "other-pane"),
        responseMismatch("requestId", correctResponse, key: "requestId", value: "other-request"),
        responseMismatch("requestSequence", correctResponse, key: "requestSequence", value: 5),
        responseMismatch("workerInstanceId", correctResponse, key: "workerInstanceId", value: "other-worker"),
    ]
}

private func responseMismatch(
    _ name: String,
    _ correctResponse: [String: Any],
    key: String,
    value: Any
) throws -> ResponseMismatchFixture {
    var mismatchResponse = correctResponse
    mismatchResponse[key] = value
    return try ResponseMismatchFixture(name: name, bytes: jsonData(mismatchResponse))
}

private func workerSessionOpenObject() -> [String: Any] {
    controlIdentity(
        kind: "workerSession.open",
        requestId: "request-open-1",
        requestSequence: 1
    ).merging(["request": NSNull()]) { _, newValue in newValue }
}

private func reviewSubscriptionOpenObject(requestSequence: Int) -> [String: Any] {
    surfaceControlRequestIdentity(
        kind: "subscription.open",
        requestId: reviewSubscriptionOpenRequestId(requestSequence: requestSequence),
        requestSequence: requestSequence
    ).merging([
        "subscription": ["subscriptionKind": "review.metadata"],
        "subscriptionId": reviewSubscriptionId,
    ]) { _, newValue in newValue }
}

private func reviewSubscriptionOpenAcceptedObject(
    requestSequence: Int,
    interestSHA256: String
) -> [String: Any] {
    controlIdentity(
        kind: "subscription.openAccepted",
        requestId: reviewSubscriptionOpenRequestId(requestSequence: requestSequence),
        requestSequence: requestSequence
    ).merging([
        "interestRevision": 0,
        "interestSha256": interestSHA256,
        "subscriptionId": reviewSubscriptionId,
        "subscriptionKind": "review.metadata",
    ]) { _, newValue in newValue }
}

private func reviewUpdateBatchObject(
    requestSequence: Int,
    batchIndex: Int,
    itemId: String,
    lane: String,
    interestFixture: ReviewInterestFixture
) -> [String: Any] {
    surfaceControlRequestIdentity(
        kind: "subscription.updateBatch",
        requestId: reviewUpdateRequestId(requestSequence: requestSequence),
        requestSequence: requestSequence
    ).merging([
        "baseInterestRevision": 0,
        "baseInterestSha256": interestFixture.emptySHA256,
        "batchCount": 2,
        "batchIndex": batchIndex,
        "delta": [
            "add": [["itemId": itemId, "lane": lane]],
            "removeItemIds": [],
            "subscriptionKind": "review.metadata",
        ],
        "subscriptionId": reviewSubscriptionId,
        "subscriptionKind": "review.metadata",
        "targetInterestRevision": 1,
        "targetInterestSha256": interestFixture.targetSHA256,
        "totalDeltaItemCount": 2,
        "updateId": reviewUpdateId,
    ]) { _, newValue in newValue }
}

private func reviewUpdateAcceptedObject(
    requestSequence: Int,
    batchIndex: Int,
    disposition: String,
    interestFixture: ReviewInterestFixture
) -> [String: Any] {
    controlIdentity(
        kind: "subscription.updateBatchAccepted",
        requestId: reviewUpdateRequestId(requestSequence: requestSequence),
        requestSequence: requestSequence
    ).merging([
        "batchIndex": batchIndex,
        "disposition": disposition,
        "subscriptionId": reviewSubscriptionId,
        "subscriptionKind": "review.metadata",
        "targetInterestRevision": 1,
        "targetInterestSha256": interestFixture.targetSHA256,
        "updateId": reviewUpdateId,
    ]) { _, newValue in newValue }
}

private func requestErrorObject(
    requestId: String,
    requestSequence: Int
) -> [String: Any] {
    controlIdentity(
        kind: "request.error",
        requestId: requestId,
        requestSequence: requestSequence
    ).merging([
        "code": "unsupported_subscription",
        "nextExpectedRequestSequence": requestSequence + 1,
        "retryAfterMilliseconds": NSNull(),
        "retryable": false,
        "safeMessage": "Unsupported subscription",
    ]) { _, newValue in newValue }
}

private func surfaceControlRequestIdentity(
    kind: String,
    requestId: String,
    requestSequence: Int
) -> [String: Any] {
    controlIdentity(
        kind: kind,
        requestId: requestId,
        requestSequence: requestSequence
    ).merging(["workerDerivationEpoch": reviewEpoch]) { _, newValue in newValue }
}

private func controlIdentity(
    kind: String,
    requestId: String,
    requestSequence: Int
) -> [String: Any] {
    [
        "kind": kind,
        "paneSessionId": paneSessionId,
        "requestId": requestId,
        "requestSequence": requestSequence,
        "wireVersion": BridgeProductWireContract.version,
        "workerInstanceId": workerInstanceId,
    ]
}

private func reviewSubscriptionOpenRequestId(requestSequence: Int) -> String {
    "request-review-open-\(requestSequence)"
}

private func reviewUpdateRequestId(requestSequence: Int) -> String {
    "request-review-update-\(requestSequence)"
}

private func jsonData(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}
