import AgentStudioCore
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge pane worktree refresh driver session integration")
@MainActor
struct BridgeWorktreeRefreshSessionTests {
    @Test("real metadata queue reset reopens File delivery and replays retained work once")
    func realQueueResetReopensAndReplays() async throws {
        // Arrange
        let queueLimits = try BridgeProductProducerQueueLimits(
            maximumQueuedFrameCount: 3,
            maximumQueuedByteCount: BridgeProductWireContract.maximumQueuedStreamBytes,
            maximumEncodedFrameByteCount:
                BridgeProductProducerQueueLimits.maximumProductEncodedFrameByteCount,
            terminalFrameReserve: BridgeProductWireContract.terminalFrameReserve
        )
        let harness = try await BridgeProductSessionLifecycleHarness.opened(
            producerQueueLimits: queueLimits
        )
        let firstMetadataLease = try await harness.admitMetadataFrames(through: 0)
        let firstPump = makeSessionIntegrationPump(harness, lease: firstMetadataLease)
        try await openSessionIntegrationFileSubscription(
            harness,
            pump: firstPump,
            requestSequence: 2,
            workerDerivationEpoch: 1
        )
        let publisher = BridgeRefreshDriverSessionPublisher(
            session: harness.session,
            subscriptionId: "file-subscription-1"
        )
        let coordinator = BridgePaneRefreshAdmissionCoordinator(initialActivity: .foreground)
        let driver = BridgePaneWorktreeRefreshDriver(
            coordinator: coordinator,
            acquireProductAdmission: { harness.productAdmission.context },
            publishFileChangeset: { changeset, admission, work, correlationID, attempt in
                await publisher.publish(
                    changeset,
                    productAdmission: admission,
                    foregroundWorkAdmission: work,
                    operationCorrelationID: correlationID,
                    operationStageAttempt: attempt
                )
            },
            publishFileStatus: { _, _, _, _, _ in .notRequired },
            publishPresentation: { _, _ in }
        )
        driver.recordFileSourceAccepted(try sessionIntegrationFileSource(generation: 1))

        // Act
        _ = driver.recordInvalidation(
            fileChangeset: sessionIntegrationChangeset(batchSequence: 1),
            latestFileStatus: nil,
            requiresReviewRefresh: false
        )
        await publisher.waitForAttemptCount(1)
        try await waitForSessionIntegrationDriverIdle(driver)
        let resetFrame = try await pullMetadataFrame(from: firstPump)

        // Assert
        guard case .metadataStreamError(let reset) = resetFrame else {
            Issue.record("Expected the real bounded queue to emit metadata.streamError")
            return
        }
        #expect(reset.code == .resyncRequired)
        #expect(reset.retryable)
        #expect(driver.hasPendingFileStreamRecovery)
        #expect(coordinator.productPresentationSnapshot.fileRefreshFailure == nil)
        #expect(await publisher.attemptCount == 1)

        // Act
        let resyncEffect = try await resyncSessionIntegrationFileSubscription(
            harness,
            requestSequence: 3,
            lastAcceptedStreamSequence: reset.frameIdentity.streamSequence,
            workerDerivationEpoch: 1
        )
        try await harness.closeProducer(firstMetadataLease)
        let secondMetadataLease = try await harness.admitMetadataFrames(through: 0)
        let secondPump = makeSessionIntegrationPump(harness, lease: secondMetadataLease)
        try await openSessionIntegrationFileSubscription(
            harness,
            pump: secondPump,
            requestSequence: 4,
            workerDerivationEpoch: 2
        )
        driver.recordFileSourceAccepted(try sessionIntegrationFileSource(generation: 2))
        await publisher.waitForAttemptCount(2)
        try await waitForSessionIntegrationDriverIdle(driver)
        let replayFrame = try await pullMetadataFrame(from: secondPump)

        // Assert
        guard case .resynced(let resync) = resyncEffect,
            case .subscriptionData(let replayData) = replayFrame,
            case .fileMetadata = replayData.data
        else {
            Issue.record("Expected resync reopening followed by retained File data")
            return
        }
        #expect(resync.reconciliation.map(\.dispositionName) == ["reopenRequired"])
        #expect(!driver.hasPendingFileStreamRecovery)
        #expect(await publisher.attemptCount == 2)
        let operationCorrelationIDs = await publisher.operationCorrelationIDs
        #expect(operationCorrelationIDs.count == 2)
        #expect(operationCorrelationIDs[0] == operationCorrelationIDs[1])
        #expect(await publisher.operationStageAttempts == [0, 2])
        #expect(replayData.operationCorrelationID == operationCorrelationIDs[1])
        #expect(coordinator.diagnosticSnapshot.dirtyFact == nil)
        await driver.closeAndDrain()
        try await harness.closeProducer(secondMetadataLease)
    }
}

private actor BridgeRefreshDriverSessionPublisher {
    private let session: BridgeProductSession
    private let subscriptionId: String
    private var attemptWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var attemptCount = 0
    private(set) var operationCorrelationIDs: [String] = []
    private(set) var operationStageAttempts: [Int] = []

    init(session: BridgeProductSession, subscriptionId: String) {
        self.session = session
        self.subscriptionId = subscriptionId
    }

    func publish(
        _: FileChangeset,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        operationCorrelationID: String,
        operationStageAttempt: Int
    ) async -> BridgePaneProductFileRefreshPublicationDisposition {
        attemptCount += 1
        operationCorrelationIDs.append(operationCorrelationID)
        operationStageAttempts.append(operationStageAttempt)
        resumeAttemptWaiters()
        let emissionCount = attemptCount == 1 ? 3 : 1
        do {
            for _ in 0..<emissionCount {
                let result = try await session.enqueueSubscriptionData(
                    subscriptionId: subscriptionId,
                    data: .fileMetadata(try coordinatorSourceAcceptedEvent()),
                    operationCorrelationID: operationCorrelationID,
                    productAdmission: productAdmission,
                    foregroundWorkAdmission: foregroundWorkAdmission
                )
                switch result {
                case .enqueued:
                    continue
                case .queueReset:
                    return .streamResetRequired
                case .rejected:
                    return .failed(.init(failureKind: .producerRejected))
                }
            }
            return .applied
        } catch {
            return BridgePaneProductMetadataCoordinator.fileRefreshDisposition(for: error)
        }
    }

    func waitForAttemptCount(_ expectedCount: Int) async {
        guard attemptCount < expectedCount else { return }
        await withCheckedContinuation { continuation in
            attemptWaiters.append((expectedCount, continuation))
        }
    }

    private func resumeAttemptWaiters() {
        var pendingWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
        for (expectedCount, continuation) in attemptWaiters {
            if attemptCount >= expectedCount {
                continuation.resume()
            } else {
                pendingWaiters.append((expectedCount, continuation))
            }
        }
        attemptWaiters = pendingWaiters
    }
}

private func makeSessionIntegrationPump(
    _ harness: BridgeProductSessionLifecycleHarness,
    lease: BridgeProductProducerLease
) -> BridgeProductSchemeFramePump {
    BridgeProductSchemeFramePump(
        session: harness.session,
        producerLease: lease,
        productAdmission: harness.productAdmission.context,
        acknowledgeLifecycle: { _ in true }
    )
}

private func openSessionIntegrationFileSubscription(
    _ harness: BridgeProductSessionLifecycleHarness,
    pump: BridgeProductSchemeFramePump,
    requestSequence: Int,
    workerDerivationEpoch: Int
) async throws {
    let request = try bridgeProductLifecycleControlRequest(
        bridgeProductLifecycleFileSubscriptionOpenObject(
            requestSequence: requestSequence,
            epoch: workerDerivationEpoch
        )
    )
    let token = try #require(controlExecutionToken(try await harness.begin(request)))
    #expect(await harness.session.claimControlProviderDispatch(token: token))
    let response = try BridgeProductControlResponse.subscriptionOpenAccepted(
        correlating: request,
        interestSha256:
            BridgeProductSubscriptionInterestState
            .fileMetadata(interests: [], pathScope: [])
            .sha256Hex()
    )
    _ = try await harness.session.completeControl(
        token: token,
        exactResponseBytes: try JSONEncoder().encode(response)
    )
    guard case .subscriptionAccepted = try await pullMetadataFrame(from: pump) else {
        throw BridgeRefreshDriverSessionIntegrationError.expectedSubscriptionAcceptance
    }
    await harness.session.settleControlProviderDispatch(token: token)
}

private func resyncSessionIntegrationFileSubscription(
    _ harness: BridgeProductSessionLifecycleHarness,
    requestSequence: Int,
    lastAcceptedStreamSequence: Int,
    workerDerivationEpoch: Int
) async throws -> BridgeProductSessionCompletionEffect {
    let emptyInterestSHA256 =
        try BridgeProductSubscriptionInterestState
        .fileMetadata(interests: [], pathScope: [])
        .sha256Hex()
    let request = try bridgeProductLifecycleControlRequest([
        "activeSubscriptions": [
            [
                "interestRevision": 0,
                "interestSha256": emptyInterestSHA256,
                "subscriptionId": "file-subscription-1",
                "subscriptionKind": "file.metadata",
                "workerDerivationEpoch": workerDerivationEpoch,
            ]
        ],
        "kind": "workerSession.resync",
        "lastAcceptedRequestSequence": requestSequence - 1,
        "lastAcceptedStreamSequence": lastAcceptedStreamSequence,
        "paneSessionId": "pane-session-1",
        "requestId": "request-resync-\(requestSequence)",
        "requestSequence": requestSequence,
        "wireVersion": BridgeProductWireContract.version,
        "workerInstanceId": "worker-instance-1",
    ])
    let token = try #require(controlExecutionToken(try await harness.begin(request)))
    let response = try await harness.authoritativeResyncResponse(
        request: request,
        token: token
    )
    return try await harness.session.completeControl(
        token: token,
        exactResponseBytes: try JSONEncoder().encode(response)
    )
}

@MainActor
private func waitForSessionIntegrationDriverIdle(
    _ driver: BridgePaneWorktreeRefreshDriver,
    maximumTurns: Int = 200
) async throws {
    for _ in 0..<maximumTurns {
        if !driver.hasActiveFileOperation { return }
        await Task.yield()
    }
    throw BridgeRefreshDriverSessionIntegrationError.fileOperationDidNotSettle
}

private func sessionIntegrationChangeset(batchSequence: UInt64) -> FileChangeset {
    FileChangeset(
        worktreeId: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
        repoId: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
        rootPath: URL(fileURLWithPath: "/tmp/bridge-refresh-driver-session"),
        paths: ["Sources/App.swift"],
        timestamp: .now,
        batchSeq: batchSequence
    )
}

private func sessionIntegrationFileSource(
    generation: Int
) throws -> BridgeProductFileSourceIdentity {
    try .init(
        repoId: "00000000-0000-4000-8000-000000000001",
        rootRevisionToken: "root-token-1",
        sourceCursor: "generation-\(generation)",
        sourceId: "file-source-\(generation)",
        subscriptionGeneration: generation,
        worktreeId: "00000000-0000-4000-8000-000000000002"
    )
}

private enum BridgeRefreshDriverSessionIntegrationError: Error {
    case expectedSubscriptionAcceptance
    case fileOperationDidNotSettle
}
