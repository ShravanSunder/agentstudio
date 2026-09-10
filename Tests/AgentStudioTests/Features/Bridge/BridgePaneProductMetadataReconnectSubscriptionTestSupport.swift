import AgentStudioCore
import Foundation
import Testing

@testable import AgentStudioBridge

struct ReconnectSubscriptionContext {
    let committedInterest: BridgeProductSubscriptionInterestsCommittedFrame
    let dispatcher: BridgeProductSchemeControlDispatcher
    let fileSource: ReconnectFileMetadataSource
    let firstStream: ReconnectMetadataStream
    let refreshWorkAdmission: BridgePaneRefreshWorkAdmission
    let harness: BridgeProductSessionLifecycleHarness
    let initialData: BridgeProductSubscriptionDataFrame
    let provider: BridgePaneProductSchemeProvider
    let retainedSubscription: BridgeProductSubscriptionSnapshot
}

struct ReconnectMetadataStream {
    let pump: BridgeProductSchemeFramePump
}

struct ReconnectFileSourceDiagnostics: Sendable {
    let cancellationCount: Int
    let interestSha256: String?
    let openCallCount: Int
    let publicationCallCount: Int
    let updateCallCount: Int
}

actor ReconnectFileMetadataSource: BridgePaneProductFileMetadataProducing {
    private var activeSubscriptionIds: Set<String> = []
    private var cancellationCount = 0
    private var appliedInterestSha256: String?
    private var openCallCount = 0
    private var publicationCallCount = 0
    private var updateCallCount = 0

    var hasActiveSubscription: Bool { !activeSubscriptionIds.isEmpty }

    var diagnostics: ReconnectFileSourceDiagnostics {
        .init(
            cancellationCount: cancellationCount,
            interestSha256: appliedInterestSha256,
            openCallCount: openCallCount,
            publicationCallCount: publicationCallCount,
            updateCallCount: updateCallCount
        )
    }

    func currentSource() -> BridgeProductFileSourceCurrentResult {
        .unavailable(.noFileSourceAuthority)
    }

    func open(
        subscription: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        foregroundWorkAdmission _: BridgePaneRefreshWorkAdmission,
        emit: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws {
        openCallCount += 1
        appliedInterestSha256 = subscription.interestSha256
        activeSubscriptionIds.insert(subscription.subscriptionId)
        try await emit(try reconnectFileSourceAcceptedEvent(cursor: "initial"))
    }

    func update(
        subscription: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        foregroundWorkAdmission _: BridgePaneRefreshWorkAdmission,
        emit _: @escaping BridgePaneProductFileMetadataEventSink
    ) async throws {
        guard activeSubscriptionIds.contains(subscription.subscriptionId) else { return }
        appliedInterestSha256 = subscription.interestSha256
        updateCallCount += 1
    }

    func cancel(subscriptionId: String) {
        activeSubscriptionIds.remove(subscriptionId)
        appliedInterestSha256 = nil
        cancellationCount += 1
    }

    func publish(
        status _: GitWorkingTreeStatus,
        productAdmission _: BridgeProductAdmissionContext,
        foregroundWorkAdmission _: BridgePaneRefreshWorkAdmission
    ) -> [BridgePaneProductFileMetadataEmission] { [] }

    func publish(
        changeset _: FileChangeset,
        productAdmission _: BridgeProductAdmissionContext,
        foregroundWorkAdmission _: BridgePaneRefreshWorkAdmission
    ) async throws -> [BridgePaneProductFileMetadataEmission] {
        publicationCallCount += 1
        return try activeSubscriptionIds.sorted().map { subscriptionId in
            BridgePaneProductFileMetadataEmission(
                event: try reconnectFileSourceAcceptedEvent(cursor: "post-reconnect"),
                subscriptionId: subscriptionId
            )
        }
    }

    func contentReadPlan(
        for _: BridgeProductFileContentRequest,
        productAdmission _: BridgeProductAdmissionContext
    ) -> BridgePaneProductFileContentReadPlan? { nil }
}

func makeReconnectSubscriptionContext() async throws -> ReconnectSubscriptionContext {
    let harness = try await BridgeProductSessionLifecycleHarness.opened()
    let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
    let fileSource = ReconnectFileMetadataSource()
    let provider = BridgePaneProductSchemeProvider(
        fileMetadataSource: fileSource,
        reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
        reviewContentSource: BridgeUnavailablePaneProductReviewContentSource(),
        markReviewItemViewed: { _, _ in },
        refreshWorkAdmissionSource: refreshWorkAdmission.source
    )
    let dispatcher = makeBridgeProductSchemeControlDispatcher(
        session: harness.session,
        provider: provider,
        productAdmission: harness.productAdmission.context
    )
    let firstStream = try await installReconnectMetadataStream(
        request: bridgeProductMetadataStreamRequest(
            metadataStreamId: "metadata-before-reconnect",
            resumeFromStreamSequence: nil
        ),
        provider: provider,
        harness: harness
    )
    let established = try await establishReconnectFileSubscription(
        dispatcher: dispatcher,
        fileSource: fileSource,
        harness: harness,
        stream: firstStream
    )
    return ReconnectSubscriptionContext(
        committedInterest: established.committedInterest,
        dispatcher: dispatcher,
        fileSource: fileSource,
        firstStream: firstStream,
        refreshWorkAdmission: refreshWorkAdmission.admission,
        harness: harness,
        initialData: established.initialData,
        provider: provider,
        retainedSubscription: established.retainedSubscription
    )
}

func establishReconnectFileSubscription(
    dispatcher: BridgeProductSchemeControlDispatcher,
    fileSource: ReconnectFileMetadataSource,
    harness: BridgeProductSessionLifecycleHarness,
    stream: ReconnectMetadataStream
) async throws -> (
    committedInterest: BridgeProductSubscriptionInterestsCommittedFrame,
    initialData: BridgeProductSubscriptionDataFrame,
    retainedSubscription: BridgeProductSubscriptionSnapshot
) {
    let openRequest = try bridgeProductLifecycleControlRequest(
        bridgeProductLifecycleFileSubscriptionOpenObject(requestSequence: 2, epoch: 1)
    )
    _ = try await dispatchReconnectControl(
        openRequest,
        dispatcher: dispatcher,
        capabilityHeader: harness.capabilityHeader
    )
    guard case .subscriptionAccepted = try await pullMetadataFrame(from: stream.pump) else {
        throw ReconnectSubscriptionTestError.expectedSubscriptionAcceptance
    }
    guard case .subscriptionData(let initialData) = try await pullMetadataFrame(from: stream.pump)
    else {
        throw ReconnectSubscriptionTestError.expectedSubscriptionData
    }
    let lifecycle = try coordinatorFileSubscriptionLifecycle()
    let updateRequest = try coordinatorFileUpdateRequest(
        emptyInterestSha256: lifecycle.opened.interestSha256,
        targetInterestSha256: lifecycle.updated.interestSha256,
        updateId: lifecycle.commitBarrier.updateId
    )
    _ = try await dispatchReconnectControl(
        updateRequest,
        dispatcher: dispatcher,
        capabilityHeader: harness.capabilityHeader
    )
    guard
        case .subscriptionInterestsCommitted(let committedInterest) =
            try await pullMetadataFrame(from: stream.pump)
    else {
        throw ReconnectSubscriptionTestError.expectedInterestCommit
    }
    guard await waitForReconnectSourceUpdate(fileSource) else {
        throw ReconnectSubscriptionTestError.expectedSourceUpdate
    }
    let retainedSubscription = try #require(
        await harness.session.subscriptionSnapshot(subscriptionId: "file-subscription-1")
    )
    return (committedInterest, initialData, retainedSubscription)
}

func installReconnectMetadataStream(
    request: BridgeProductMetadataStreamRequest,
    provider: BridgePaneProductSchemeProvider,
    harness: BridgeProductSessionLifecycleHarness
) async throws -> ReconnectMetadataStream {
    let session = harness.session
    let productAdmission = harness.productAdmission.context
    let registration = await session.registerMetadataProducer(
        request: request,
        productAdmission: productAdmission
    ) { lease in
        await provider.runMetadataProducer(
            request: request,
            lease: lease,
            productAdmission: productAdmission,
            session: session
        )
    }
    let lease = try bridgeProductAcceptedLease(registration)
    let pump = BridgeProductSchemeFramePump(
        session: session,
        producerLease: lease,
        productAdmission: productAdmission,
        acknowledgeLifecycle: provider.acknowledgeLifecycle
    )
    guard case .metadataStreamAccepted = try await pullMetadataFrame(from: pump) else {
        throw ReconnectSubscriptionTestError.expectedMetadataStreamAcceptance
    }
    return ReconnectMetadataStream(pump: pump)
}

func dispatchReconnectControl(
    _ request: BridgeProductControlRequest,
    dispatcher: BridgeProductSchemeControlDispatcher,
    capabilityHeader: String
) async throws -> BridgeProductControlResponse {
    let encoder = JSONEncoder()
    // Exact control retries compare wire bytes, not decoded object equality.
    encoder.outputFormatting = [.sortedKeys]
    let result = try await dispatcher.dispatch(
        exactRequestBytes: try encoder.encode(request),
        presentedCapability: capabilityHeader
    )
    guard case .response(let responseData) = result else {
        throw ReconnectSubscriptionTestError.expectedControlResponse
    }
    return try BridgeProductStrictJSON.decode(BridgeProductControlResponse.self, from: responseData)
}

func pullPostReconnectPublication(
    from pump: BridgeProductSchemeFramePump,
    session: BridgeProductSession
) async throws -> BridgeProductMetadataFrame? {
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline {
        if await session.producerSnapshot().queuedFrameCount > 0 {
            let frame = try await pullMetadataFrame(from: pump)
            if case .subscriptionData(let data) = frame,
                case .sourceAccepted(let accepted)? = data.data.fileMetadataEvent,
                accepted.source.sourceCursor == "source-cursor-post-reconnect"
            {
                return frame
            }
        } else {
            await Task.yield()
        }
    }
    return nil
}

func reconnectResyncRequest(
    subscription: BridgeProductSubscriptionSnapshot,
    lastAcceptedStreamSequence: Int,
    claimedInterestSha256: String? = nil
) throws -> BridgeProductControlRequest {
    try bridgeProductLifecycleControlRequest([
        "activeSubscriptions": [
            [
                "interestRevision": subscription.interestRevision,
                "interestSha256": claimedInterestSha256 ?? subscription.interestSha256,
                "subscriptionId": subscription.subscriptionId,
                "subscriptionKind": subscription.subscriptionKind.rawValue,
                "workerDerivationEpoch": subscription.workerDerivationEpoch,
            ]
        ],
        "kind": "workerSession.resync",
        "lastAcceptedRequestSequence": 3,
        "lastAcceptedStreamSequence": lastAcceptedStreamSequence,
        "paneSessionId": bridgeProductTestPaneSessionId,
        "requestId": "request-reconnect-resync-4",
        "requestSequence": 4,
        "wireVersion": BridgeProductWireContract.version,
        "workerInstanceId": bridgeProductTestWorkerInstanceId,
    ])
}

func reconnectFileSourceAcceptedEvent(
    cursor: String
) throws -> BridgeProductFileMetadataEvent {
    .sourceAccepted(
        .init(
            source: try .init(
                repoId: "00000000-0000-4000-8000-000000000001",
                rootRevisionToken: "root-token-reconnect",
                sourceCursor: "source-cursor-\(cursor)",
                sourceId: "file-source-reconnect",
                subscriptionGeneration: 1,
                worktreeId: "00000000-0000-4000-8000-000000000002"
            )
        )
    )
}

func reconnectFileChangeset() throws -> FileChangeset {
    let worktreeIdentifier = "00000000-0000-4000-8000-000000000002"
    let repositoryIdentifier = "00000000-0000-4000-8000-000000000001"
    let repositoryUUID: UUID = try #require(UUID(uuidString: repositoryIdentifier))
    return FileChangeset(
        worktreeId: try #require(UUID(uuidString: worktreeIdentifier)),
        repoId: repositoryUUID,
        rootPath: URL(fileURLWithPath: "/tmp/bridge-metadata-reconnect"),
        paths: ["Sources/App.swift"],
        timestamp: .now,
        batchSeq: 1
    )
}

func waitForReconnectSourceActivity(
    _ source: ReconnectFileMetadataSource,
    maximumTurns: Int = 2000
) async -> Bool {
    for _ in 0..<maximumTurns {
        if await source.hasActiveSubscription { return true }
        await Task.yield()
    }
    return false
}

func waitForReconnectSourceUpdate(
    _ source: ReconnectFileMetadataSource,
    maximumTurns: Int = 2000
) async -> Bool {
    for _ in 0..<maximumTurns {
        if await source.diagnostics.updateCallCount >= 1 { return true }
        await Task.yield()
    }
    return false
}

enum ReconnectSubscriptionTestError: Error {
    case expectedControlResponse
    case expectedInterestCommit
    case expectedMetadataStreamAcceptance
    case expectedSourceUpdate
    case expectedSubscriptionAcceptance
    case expectedSubscriptionData
}
