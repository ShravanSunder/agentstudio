import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct BridgePaneControllerProductBootstrapDeliveryTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("committed Review survives bootstrap failure and replays after worker replacement")
    func committedReviewSurvivesBootstrapFailureAndReplaysAfterWorkerReplacement() async throws {
        // Arrange
        let paneId = UUIDv7.generate()
        let reviewFixture = makeBootstrapCommittedReviewFixture()
        var deliveredInstallations: [BridgeProductSessionInstallation] = []
        let controller = BridgePaneController(
            paneId: paneId,
            state: BridgePaneState(
                panelKind: .diffViewer,
                source: .workspace(rootPath: "Sources", baseline: .headMinusOne)
            ),
            reviewSourceProvider: reviewFixture.sourceProvider,
            initialPaneActivity: .foreground,
            productSessionBootstrapSink: { _, _, installation, _, _ in
                deliveredInstallations.append(installation)
                if deliveredInstallations.count == 1 {
                    throw BridgeError.encoding("simulated ambiguous delivery failure")
                }
            }
        )
        let commandId = UUIDv7.generate()
        let loadResult = await controller.handleDiffCommand(
            .loadDiff(
                DiffArtifact(
                    diffId: UUIDv7.generate(),
                    worktreeId: reviewFixture.headEndpoint.worktreeId,
                    patchData: Data()
                )
            ),
            commandId: commandId,
            correlationId: nil
        )
        #expect(loadResult == .success(commandId: commandId))
        let committedPackage = try #require(controller.paneState.diff.packageMetadata)
        let committedDelta = controller.paneState.diff.packageDelta

        // Act
        await controller.enqueueProductSessionBootstrapRequest(
            requestId: "failed-initial-bootstrap",
            reason: .initial
        )
        let initialInstallation = try #require(deliveredInstallations.first)
        let staleReply = try await collectStaleBootstrapReply(from: initialInstallation)
        await controller.enqueueProductSessionBootstrapRequest(
            requestId: "retry-initial-bootstrap",
            reason: .initial
        )
        let replacementInstallation = try #require(deliveredInstallations.last)
        let productProvider = try #require(controller.productSchemeProvider)
        let replaySubscription = try await openBootstrapReviewReplaySubscription(
            controller: controller,
            installation: replacementInstallation,
            productProvider: productProvider
        )
        let replayEvent = try bootstrapReviewEvent(
            from: try bootstrapReviewMetadataFrame(
                from: try #require(
                    await consumeNextBridgeProductProducerFrame(
                        for: replaySubscription.lease,
                        from: replacementInstallation.session,
                        productAdmission: replaySubscription.productAdmission
                    )
                )
            )
        )

        // Assert
        #expect(staleReply.response?.statusCode == 403)
        #expect(deliveredInstallations.count == 2)
        #expect(
            replacementInstallation.bootstrap.workerInstanceId
                != initialInstallation.bootstrap.workerInstanceId
        )
        #expect(replacementInstallation.capabilityBytes != initialInstallation.capabilityBytes)
        #expect(controller.paneState.diff.packageMetadata == committedPackage)
        #expect(controller.paneState.diff.packageDelta == committedDelta)
        await #expect(throws: Never.self) {
            _ = try await controller.loadContentForIPC(
                contentHandleId: reviewFixture.committedHandle.handleId,
                reviewGeneration: reviewFixture.committedHandle.reviewGeneration.rawValue
            )
        }
        switch replayEvent {
        case .sourceAccepted:
            #expect(replayEvent.packageId == committedPackage.packageId)
            #expect(replayEvent.generation == committedPackage.reviewGeneration.rawValue)
        default:
            Issue.record("Expected replacement worker replay to begin with Review sourceAccepted")
        }
        try await closeBridgeProductSessionProducer(
            replaySubscription.lease,
            in: replacementInstallation.session
        )
        #expect(await controller.teardown().value)
    }

    @Test("pane close suppresses a suspended product bootstrap delivery")
    func paneCloseSuppressesSuspendedProductBootstrapDelivery() async throws {
        // Arrange
        let paneId = UUIDv7.generate()
        let provider = BridgePaneProductSessionProviderGate()
        let productAdmissionGate = BridgeProductAdmissionGate()
        let initialInstallation = BridgePaneController.makeInitialProductSessionInstallation(
            paneSessionId: paneId.uuidString,
            provider: provider,
            productAdmissionGate: productAdmissionGate
        )
        let owner = BridgePaneController.makeProductSessionOwner(
            paneSessionId: paneId.uuidString,
            provider: provider,
            productAdmissionGate: productAdmissionGate,
            activeInstallation: initialInstallation
        )
        let deliverySuspension = BridgeProductBootstrapDeliverySuspension()
        var deliveredWorkerInstanceIds: [String] = []
        let controller = BridgePaneController(
            paneId: paneId,
            state: BridgePaneState(panelKind: .diffViewer, source: .commit(sha: "close-bootstrap")),
            initialPaneActivity: .foreground,
            productSessionDependencies: BridgePaneProductSessionDependencies(
                installation: initialInstallation,
                owner: owner
            ),
            productSessionBootstrapSink: { _, _, installation, _, productAdmission in
                await deliverySuspension.suspendDelivery()
                _ = productAdmission.withValidAdmission {
                    deliveredWorkerInstanceIds.append(installation.bootstrap.workerInstanceId)
                }
            }
        )

        // Act
        let bootstrapTask = Task { @MainActor in
            await controller.enqueueProductSessionBootstrapRequest(
                requestId: "suspended-initial-bootstrap",
                reason: .initial
            )
        }
        await deliverySuspension.waitUntilDeliveryIsSuspended()
        let teardownTask = controller.teardown()
        await deliverySuspension.resumeDelivery()
        await bootstrapTask.value
        let teardownSucceeded = await teardownTask.value
        let ownerSnapshot = await owner.snapshot()

        // Assert
        #expect(deliveredWorkerInstanceIds.isEmpty)
        #expect(teardownSucceeded)
        #expect(ownerSnapshot.hasZeroResidue)
        #expect(productAdmissionGate.diagnosticSnapshot.isOpen == false)
    }

    @Test("surface command queued during replacement binds to the replacement worker")
    func surfaceCommandDuringReplacementBindsToReplacementWorker() async throws {
        // Arrange
        var deliveredInstallations: [BridgeProductSessionInstallation] = []
        let controller = BridgePaneController(
            paneId: UUIDv7.generate(),
            state: BridgePaneState(
                panelKind: .fileViewer,
                source: .workspace(rootPath: "Sources", baseline: .unstaged)
            ),
            initialPaneActivity: .foreground,
            productSessionBootstrapSink: { _, _, installation, _, _ in
                deliveredInstallations.append(installation)
            }
        )
        controller.hasPublishedProductSessionBootstrap = true
        #expect(await controller.productSessionOwner.retire(reason: .workerReplacement) == .retired)
        #expect(await controller.productSessionOwner.activeBootstrap() == nil)

        // Act: the command is admitted while no worker is active.
        #expect(controller.requestViewerSurface(.review))
        await controller.surfaceSelectionTransitionTail?.value
        let queuedSnapshot = controller.surfaceSelectionAuthority.diagnosticSnapshot

        await controller.enqueueProductSessionBootstrapRequest(
            requestId: "replacement-after-surface-command",
            reason: .workerReplacement
        )

        // Assert: bootstrap activation remints the retained intent for worker B.
        #expect(queuedSnapshot.desiredSurface == .review)
        #expect(queuedSnapshot.needsDelivery)
        #expect(queuedSnapshot.currentRequest == nil)
        let replacement = try #require(deliveredInstallations.last)
        let replacementRequest = try #require(
            controller.surfaceSelectionAuthority.diagnosticSnapshot.currentRequest
        )
        #expect(replacementRequest.surface == .review)
        #expect(replacementRequest.paneSessionId == replacement.bootstrap.paneSessionId)
        #expect(replacementRequest.workerInstanceId == replacement.bootstrap.workerInstanceId)

        let productAdmission = try #require(controller.productAdmissionGate.acquire())
        let correlation = try BridgeProductControlCorrelation(
            paneSessionId: replacement.bootstrap.paneSessionId,
            requestId: "replacement-surface-receipt",
            requestSequence: 1,
            workerInstanceId: replacement.bootstrap.workerInstanceId
        )
        await controller.handleCommittedProductActiveViewerModeUpdate(
            sessionId: "replacement-viewer-session",
            sequence: 1,
            mode: .review,
            activeSource: nil,
            productAdmission: productAdmission,
            nativeSelectionRequestId: replacementRequest.requestId,
            productCorrelation: correlation
        )
        #expect(
            controller.surfaceSelectionAuthority.diagnosticSnapshot.lastAcceptedRequest
                == replacementRequest
        )
        #expect(await controller.teardown().value)
    }

    @Test("cold Review intake admits nil or current stream and rejects stale stream")
    func coldReviewIntakeAdmitsNilOrCurrentStreamAndRejectsStaleStream() async throws {
        // Arrange
        let nilStreamController = makeColdReviewIntakeController()
        let currentStreamController = makeColdReviewIntakeController()
        let staleStreamController = makeColdReviewIntakeController()
        defer {
            nilStreamController.teardown()
            currentStreamController.teardown()
            staleStreamController.teardown()
        }
        let nilStreamAdmission = try #require(nilStreamController.productAdmissionGate.acquire())
        let currentStreamAdmission = try #require(
            currentStreamController.productAdmissionGate.acquire()
        )
        let staleStreamAdmission = try #require(
            staleStreamController.productAdmissionGate.acquire()
        )

        // Act
        await nilStreamController.handleCommittedProductReviewIntakeReady(
            BridgeProductReviewIntakeReadyRequest(reason: nil, streamId: nil),
            productAdmission: nilStreamAdmission
        )
        await currentStreamController.handleCommittedProductReviewIntakeReady(
            BridgeProductReviewIntakeReadyRequest(
                reason: nil,
                streamId: currentStreamController.reviewProtocolStreamId()
            ),
            productAdmission: currentStreamAdmission
        )
        await staleStreamController.handleCommittedProductReviewIntakeReady(
            BridgeProductReviewIntakeReadyRequest(
                reason: nil,
                streamId: "review:stale-stream"
            ),
            productAdmission: staleStreamAdmission
        )

        // Assert
        let nilStreamLoadTask = try #require(nilStreamController.activeReviewRefreshTask)
        let currentStreamLoadTask = try #require(currentStreamController.activeReviewRefreshTask)
        #expect(staleStreamController.activeReviewRefreshTask == nil)
        #expect(staleStreamController.paneState.diff.packageMetadata == nil)
        await nilStreamLoadTask.value
        await currentStreamLoadTask.value
        #expect(nilStreamController.paneState.diff.status == .ready)
        #expect(nilStreamController.paneState.diff.packageMetadata != nil)
        #expect(currentStreamController.paneState.diff.status == .ready)
        #expect(currentStreamController.paneState.diff.packageMetadata != nil)
    }

    private func makeColdReviewIntakeController() -> BridgePaneController {
        let paneId = UUIDv7.generate()
        let reviewFixture = makeBootstrapCommittedReviewFixture()
        return BridgePaneController(
            paneId: paneId,
            state: BridgePaneState(
                panelKind: .diffViewer,
                source: .workspace(rootPath: "Sources", baseline: .headMinusOne)
            ),
            metadata: PaneMetadata(
                paneId: PaneId(uuid: paneId),
                contentType: .diff,
                launchDirectory: URL(fileURLWithPath: "Sources"),
                title: "Cold Review Intake",
                facets: PaneContextFacets(
                    repoId: reviewFixture.headEndpoint.repoId,
                    worktreeId: reviewFixture.headEndpoint.worktreeId,
                    worktreeName: "cold-review-intake",
                    cwd: URL(fileURLWithPath: "Sources")
                )
            ),
            reviewSourceProvider: reviewFixture.sourceProvider,
            initialPaneActivity: .foreground
        )
    }
}

private struct BootstrapCommittedReviewFixture {
    let committedHandle: BridgeContentHandle
    let headEndpoint: BridgeSourceEndpoint
    let sourceProvider: BridgeReviewSourceProviderFake
}

private func makeBootstrapCommittedReviewFixture() -> BootstrapCommittedReviewFixture {
    let baseEndpoint = makeBridgeEndpoint(endpointId: "baseline-headMinusOne", kind: .gitRef)
    let headEndpoint = makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree)
    let changedFile = makeBridgeEndpointChangedFile(
        fileId: "committed-review",
        path: "Sources/App/CommittedReview.swift",
        sizeBytes: 100
    )
    let committedHandle = BridgeReviewPackageBuilder.contentHandle(
        for: changedFile,
        endpoint: headEndpoint,
        role: .head,
        reviewGeneration: 1
    )
    return BootstrapCommittedReviewFixture(
        committedHandle: committedHandle,
        headEndpoint: headEndpoint,
        sourceProvider: BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                changedFiles: [changedFile]
            ),
            contentByHandleId: [:]
        )
    )
}

private func collectStaleBootstrapReply(
    from installation: BridgeProductSessionInstallation
) async throws -> BridgeProductSchemeReplyObservation {
    let capability = try BridgeProductCapabilityHeaderEncoding.encode(installation.capabilityBytes)
    return try await collectBridgeProductSchemeReply(
        adapter: installation.productAdapter,
        request: bridgeProductSchemeRequest(
            route: BridgeProductWireContract.commandRoute,
            capability: capability,
            body: Data("{}".utf8)
        )
    )
}

private actor BridgeProductBootstrapDeliverySuspension {
    private var deliveryIsSuspended = false
    private var deliverySuspendedWaiters: [CheckedContinuation<Void, Never>] = []
    private var deliveryResumeContinuation: CheckedContinuation<Void, Never>?

    func suspendDelivery() async {
        deliveryIsSuspended = true
        let waiters = deliverySuspendedWaiters
        deliverySuspendedWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        await withCheckedContinuation { continuation in
            deliveryResumeContinuation = continuation
        }
    }

    func waitUntilDeliveryIsSuspended() async {
        guard !deliveryIsSuspended else { return }
        await withCheckedContinuation { continuation in
            deliverySuspendedWaiters.append(continuation)
        }
    }

    func resumeDelivery() {
        deliveryResumeContinuation?.resume()
        deliveryResumeContinuation = nil
    }
}

private struct BootstrapReviewReplaySubscription {
    let lease: BridgeProductProducerLease
    let productAdmission: BridgeProductAdmissionContext
}

private enum BootstrapReviewReplayError: Error {
    case expectedMetadataStreamAccepted
    case expectedReviewSubscriptionAccepted
    case expectedReviewMetadataEvent
    case expectedSingleMetadataFrame
    case expectedWorkerSessionAccepted
}

@MainActor
private func openBootstrapReviewReplaySubscription(
    controller: BridgePaneController,
    installation: BridgeProductSessionInstallation,
    productProvider: BridgePaneProductSchemeProvider
) async throws -> BootstrapReviewReplaySubscription {
    let productAdmission = try #require(controller.productAdmissionGate.acquire())
    let capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(
        installation.capabilityBytes
    )
    let controlDispatcher = BridgeProductSchemeControlDispatcher(
        session: installation.session,
        provider: productProvider,
        productAdmission: productAdmission
    )
    let workerOpenRequest = try bootstrapReviewWorkerOpenRequest(installation: installation)
    guard
        case .response = try await controlDispatcher.dispatch(
            exactRequestBytes: try bootstrapReviewControlRequestBytes(workerOpenRequest),
            presentedCapability: capabilityHeader
        )
    else {
        throw BootstrapReviewReplayError.expectedWorkerSessionAccepted
    }

    let metadataRequest = try bootstrapReviewMetadataRequest(installation: installation)
    let registration = await installation.session.registerMetadataProducer(
        request: metadataRequest,
        productAdmission: productAdmission
    ) { lease in
        await productProvider.runMetadataProducer(
            request: metadataRequest,
            lease: lease,
            productAdmission: productAdmission,
            session: installation.session
        )
    }
    let metadataLease = try bridgeProductAcceptedLease(registration)
    let metadataOpeningFrame = try bootstrapReviewMetadataFrame(
        from: try #require(
            await consumeNextBridgeProductProducerFrame(
                for: metadataLease,
                from: installation.session,
                productAdmission: productAdmission
            )
        )
    )
    guard case .metadataStreamAccepted = metadataOpeningFrame else {
        throw BootstrapReviewReplayError.expectedMetadataStreamAccepted
    }

    let reviewOpenRequest = try bootstrapReviewSubscriptionOpenRequest(
        installation: installation
    )
    var metadataStreamIsReady = false
    for _ in 0..<1000 {
        if case .subscriptionOpenAccepted = await productProvider.response(for: reviewOpenRequest) {
            metadataStreamIsReady = true
            break
        }
        await Task.yield()
    }
    #expect(metadataStreamIsReady)
    let reviewOpenDispatch = try await controlDispatcher.dispatch(
        exactRequestBytes: try bootstrapReviewControlRequestBytes(reviewOpenRequest),
        presentedCapability: capabilityHeader
    )
    guard case .response(let reviewOpenResponseBytes) = reviewOpenDispatch else {
        Issue.record("Expected Review open response, received \(String(describing: reviewOpenDispatch))")
        throw BootstrapReviewReplayError.expectedReviewSubscriptionAccepted
    }
    let reviewOpenResponse = try BridgeProductStrictJSON.decode(
        BridgeProductControlResponse.self,
        from: reviewOpenResponseBytes
    )
    guard case .subscriptionOpenAccepted = reviewOpenResponse else {
        Issue.record("Expected Review open acceptance, received \(String(describing: reviewOpenResponse))")
        throw BootstrapReviewReplayError.expectedReviewSubscriptionAccepted
    }
    try await consumeBootstrapReviewSubscriptionAcceptance(
        metadataLease: metadataLease,
        installation: installation,
        productAdmission: productAdmission
    )
    return BootstrapReviewReplaySubscription(
        lease: metadataLease,
        productAdmission: productAdmission
    )
}

private func consumeBootstrapReviewSubscriptionAcceptance(
    metadataLease: BridgeProductProducerLease,
    installation: BridgeProductSessionInstallation,
    productAdmission: BridgeProductAdmissionContext
) async throws {
    for _ in 0..<16 {
        guard
            let producerFrame = await consumeNextBridgeProductProducerFrame(
                for: metadataLease,
                from: installation.session,
                productAdmission: productAdmission
            )
        else { break }
        let metadataFrame = try bootstrapReviewMetadataFrame(from: producerFrame)
        if case .subscriptionAccepted = metadataFrame { return }
    }
    throw BootstrapReviewReplayError.expectedReviewSubscriptionAccepted
}

private func bootstrapReviewWorkerOpenRequest(
    installation: BridgeProductSessionInstallation
) throws -> BridgeProductControlRequest {
    try bootstrapReviewControlRequest([
        "kind": "workerSession.open",
        "paneSessionId": installation.bootstrap.paneSessionId,
        "request": NSNull(),
        "requestId": "request-open-bootstrap-review-replay",
        "requestSequence": 1,
        "wireVersion": BridgeProductWireContract.version,
        "workerInstanceId": installation.bootstrap.workerInstanceId,
    ])
}

private func bootstrapReviewSubscriptionOpenRequest(
    installation: BridgeProductSessionInstallation
) throws -> BridgeProductControlRequest {
    try bootstrapReviewControlRequest([
        "kind": "subscription.open",
        "paneSessionId": installation.bootstrap.paneSessionId,
        "requestId": "request-open-bootstrap-review-subscription",
        "requestSequence": 2,
        "subscription": ["subscriptionKind": "review.metadata"],
        "subscriptionId": "bootstrap-review-replay-subscription",
        "wireVersion": BridgeProductWireContract.version,
        "workerDerivationEpoch": 1,
        "workerInstanceId": installation.bootstrap.workerInstanceId,
    ])
}

private func bootstrapReviewMetadataRequest(
    installation: BridgeProductSessionInstallation
) throws -> BridgeProductMetadataStreamRequest {
    try BridgeProductStrictJSON.decode(
        BridgeProductMetadataStreamRequest.self,
        from: JSONSerialization.data(
            withJSONObject: [
                "kind": "metadataStream.open",
                "metadataStreamId": "bootstrap-review-replay-stream",
                "paneSessionId": installation.bootstrap.paneSessionId,
                "resumeFromStreamSequence": NSNull(),
                "wireVersion": BridgeProductWireContract.version,
                "workerInstanceId": installation.bootstrap.workerInstanceId,
            ],
            options: [.sortedKeys]
        )
    )
}

private func bootstrapReviewControlRequest(
    _ object: [String: Any]
) throws -> BridgeProductControlRequest {
    try BridgeProductStrictJSON.decode(
        BridgeProductControlRequest.self,
        from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    )
}

private func bootstrapReviewControlRequestBytes(
    _ request: BridgeProductControlRequest
) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(request)
}

private func bootstrapReviewMetadataFrame(
    from queuedFrame: BridgeProductQueuedProducerFrame
) throws -> BridgeProductMetadataFrame {
    let decoder = try BridgeProductMetadataFrameDecoder()
    let frames = try decoder.append(queuedFrame.data)
    guard frames.count == 1, let frame = frames.first else {
        throw BootstrapReviewReplayError.expectedSingleMetadataFrame
    }
    return frame
}

private func bootstrapReviewEvent(
    from frame: BridgeProductMetadataFrame
) throws -> BridgeProductReviewMetadataEvent {
    guard case .subscriptionData(let dataFrame) = frame,
        case .reviewMetadata(let event) = dataFrame.data
    else {
        throw BootstrapReviewReplayError.expectedReviewMetadataEvent
    }
    return event
}
