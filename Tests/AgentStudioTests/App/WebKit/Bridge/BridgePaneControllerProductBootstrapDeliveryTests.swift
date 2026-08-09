import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    struct BridgePaneControllerProductBootstrapDeliveryTests {
        init() {
            installTestCoreAtomsIfNeeded()
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
                    source: .workspace(
                        rootPath: "Sources",
                        baseline: .ref(name: "HEAD~1"))
                ),
                appRootURL: testBridgeAppRootURL(),
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
                appRootURL: testBridgeAppRootURL(),
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
                    source: .workspace(
                        rootPath: "Sources", baseline: .unstaged
                    )
                ),
                appRootURL: testBridgeAppRootURL(),
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
            _ = await controller.surfaceSelectionTransitionTail?.value
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

        @Test("exact Review command rejected without an active worker cannot replay")
        func rejectedExactReviewCommandCannotReplayAfterReplacement() async throws {
            // Arrange
            var deliveredInstallations: [BridgeProductSessionInstallation] = []
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(
                    panelKind: .diffViewer,
                    source: .workspace(
                        rootPath: "Sources", baseline: .unstaged
                    )
                ),
                appRootURL: testBridgeAppRootURL(),
                initialPaneActivity: .foreground,
                productSessionBootstrapSink: { _, _, installation, _, _ in
                    deliveredInstallations.append(installation)
                }
            )
            controller.hasPublishedProductSessionBootstrap = true
            #expect(await controller.productSessionOwner.retire(reason: .workerReplacement) == .retired)
            #expect(await controller.productSessionOwner.activeBootstrap() == nil)
            let reviewSource = BridgeProductNavigationReviewSource(
                generation: 1,
                metadataSourceId: "review-query-rejected-during-replacement",
                packageId: "review-package-rejected-during-replacement"
            )
            let reviewTarget = BridgeProductNavigationReviewTarget(
                reviewItemId: "review-item-rejected-during-replacement"
            )

            // Act
            await #expect(throws: CancellationError.self) {
                try await controller.requestReviewTargetAndPublish(
                    source: reviewSource,
                    target: reviewTarget
                )
            }
            let rejectedSnapshot = controller.surfaceSelectionAuthority.diagnosticSnapshot
            await controller.enqueueProductSessionBootstrapRequest(
                requestId: "replacement-after-rejected-exact-review",
                reason: .workerReplacement
            )
            let replacementInstallation = try #require(deliveredInstallations.last)
            let productProvider = try #require(controller.productSchemeProvider)
            let productAdmission = try #require(controller.productAdmissionGate.acquire())
            let replacementMetadataProducer = try await installRefreshAdmissionMetadataProducer(
                installation: replacementInstallation,
                productProvider: productProvider,
                productAdmission: productAdmission
            )

            // Assert
            #expect(rejectedSnapshot.desiredSurface == nil)
            #expect(rejectedSnapshot.currentRequest == nil)
            #expect(controller.surfaceSelectionAuthority.diagnosticSnapshot.desiredSurface == nil)
            #expect(controller.surfaceSelectionAuthority.diagnosticSnapshot.currentRequest == nil)
            await #expect(throws: BootstrapSurfaceSelectionReplayError.self) {
                try await consumeBootstrapSurfaceSelectionRequest(
                    producerLease: replacementMetadataProducer,
                    installation: replacementInstallation,
                    productAdmission: productAdmission
                )
            }
            try await closeBridgeProductSessionProducer(
                replacementMetadataProducer,
                in: replacementInstallation.session
            )
            #expect(await controller.teardown().value)
        }

        @Test("queued exact Review command keeps ownership across worker replacement")
        func queuedExactReviewCommandKeepsOwnershipAcrossWorkerReplacement() async throws {
            // Arrange
            let transitionSuspension = BridgeProductBootstrapDeliverySuspension()
            let overlapState = BootstrapReplacementOverlapState()
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(
                    panelKind: .diffViewer,
                    source: .workspace(
                        rootPath: "Sources", baseline: .unstaged
                    )
                ),
                appRootURL: testBridgeAppRootURL(),
                initialPaneActivity: .foreground,
                productSessionBootstrapSink: { _, _, installation, _, productAdmission in
                    overlapState.deliveredInstallations.append(installation)
                    do {
                        let activeController = try #require(overlapState.controller)
                        let productProvider = try #require(activeController.productSchemeProvider)
                        overlapState.replacementMetadataProducer =
                            try await installRefreshAdmissionMetadataProducer(
                                installation: installation,
                                productProvider: productProvider,
                                productAdmission: productAdmission
                            )
                    } catch {
                        await transitionSuspension.resumeDelivery()
                        throw error
                    }
                    await transitionSuspension.resumeDelivery()
                }
            )
            overlapState.controller = controller
            controller.hasPublishedProductSessionBootstrap = true
            controller.surfaceSelectionTransitionTail = Task { @MainActor in
                await transitionSuspension.suspendDelivery()
                return true
            }
            await transitionSuspension.waitUntilDeliveryIsSuspended()
            let reviewSource = BridgeProductNavigationReviewSource(
                generation: 1,
                metadataSourceId: "review-query-queued-during-replacement",
                packageId: "review-package-queued-during-replacement"
            )
            let reviewTarget = BridgeProductNavigationReviewTarget(
                reviewItemId: "review-item-queued-during-replacement"
            )

            // Act
            let exactCommandTask = Task { @MainActor in
                do {
                    try await controller.requestReviewTargetAndPublish(
                        source: reviewSource,
                        target: reviewTarget
                    )
                    return true
                } catch {
                    return false
                }
            }
            var exactCommandWasRetained = false
            for _ in 0..<1000 {
                if controller.surfaceSelectionAuthority.diagnosticSnapshot.desiredSurface == .review {
                    exactCommandWasRetained = true
                    break
                }
                await Task.yield()
            }
            #expect(exactCommandWasRetained)
            let bootstrapTask = Task { @MainActor in
                await controller.enqueueProductSessionBootstrapRequest(
                    requestId: "replacement-overlapping-queued-exact-review",
                    reason: .workerReplacement
                )
            }
            let exactCommandSucceeded = await exactCommandTask.value
            await bootstrapTask.value
            let replacementInstallation = try #require(overlapState.deliveredInstallations.last)
            let metadataProducer = try #require(overlapState.replacementMetadataProducer)
            let publishedRequest = try await consumeBootstrapSurfaceSelectionRequest(
                producerLease: metadataProducer,
                installation: replacementInstallation,
                productAdmission: try #require(controller.productAdmissionGate.acquire())
            )

            // Assert
            #expect(exactCommandSucceeded)
            guard
                case .activateReviewTarget(_, _, let publishedSource, let publishedTarget) =
                    publishedRequest.navigationCommand
            else {
                Issue.record("Expected the queued exact Review command on the replacement worker")
                return
            }
            #expect(publishedSource == reviewSource)
            #expect(publishedTarget == reviewTarget)
            try await closeBridgeProductSessionProducer(
                metadataProducer,
                in: replacementInstallation.session
            )
            #expect(await controller.teardown().value)
        }

        @Test("exact Review target replays after the replacement metadata stream opens")
        func exactReviewTargetReplaysAfterReplacementMetadataStreamOpens() async throws {
            // Arrange
            var deliveredInstallations: [BridgeProductSessionInstallation] = []
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(
                    panelKind: .diffViewer,
                    source: .workspace(
                        rootPath: "Sources", baseline: .unstaged
                    )
                ),
                appRootURL: testBridgeAppRootURL(),
                initialPaneActivity: .foreground,
                productSessionBootstrapSink: { _, _, installation, _, _ in
                    deliveredInstallations.append(installation)
                }
            )
            let initialInstallation = try #require(
                await controller.productSessionOwner.activeInstallation
            )
            let productProvider = try #require(controller.productSchemeProvider)
            let productAdmission = try #require(controller.productAdmissionGate.acquire())
            let initialMetadataProducer = try await installRefreshAdmissionMetadataProducer(
                installation: initialInstallation,
                productProvider: productProvider,
                productAdmission: productAdmission
            )
            let reviewSource = BridgeProductNavigationReviewSource(
                generation: 1,
                metadataSourceId: "review-query-replacement",
                packageId: "review-package-replacement"
            )
            let reviewTarget = BridgeProductNavigationReviewTarget(
                reviewItemId: "review-item-replacement"
            )
            try await controller.requestReviewTargetAndPublish(
                source: reviewSource,
                target: reviewTarget
            )
            let initialRequest = try await consumeBootstrapSurfaceSelectionRequest(
                producerLease: initialMetadataProducer,
                installation: initialInstallation,
                productAdmission: productAdmission
            )
            try await closeBridgeProductSessionProducer(
                initialMetadataProducer,
                in: initialInstallation.session
            )
            controller.hasPublishedProductSessionBootstrap = true

            // Act
            await controller.enqueueProductSessionBootstrapRequest(
                requestId: "replacement-with-exact-review-target",
                reason: .workerReplacement
            )
            let replacementInstallation = try #require(deliveredInstallations.last)
            let replacementMetadataProducer = try await installRefreshAdmissionMetadataProducer(
                installation: replacementInstallation,
                productProvider: productProvider,
                productAdmission: productAdmission
            )
            let replacementSnapshot = await replacementInstallation.session.producerSnapshot()
            let replacementRequest: BridgeProductPaneSurfaceSelectionRequestedFrame?
            if replacementSnapshot.queuedFrameCount > 0 {
                replacementRequest = try await consumeBootstrapSurfaceSelectionRequest(
                    producerLease: replacementMetadataProducer,
                    installation: replacementInstallation,
                    productAdmission: productAdmission
                )
            } else {
                replacementRequest = nil
            }

            // Assert
            let replayedRequest = try #require(replacementRequest)
            #expect(
                replayedRequest.navigationCommand.commandId
                    == initialRequest.navigationCommand.commandId
            )
            #expect(
                replayedRequest.navigationCommand.bindingRevision
                    > initialRequest.navigationCommand.bindingRevision
            )
            #expect(
                replayedRequest.frameIdentity.workerInstanceId
                    == replacementInstallation.bootstrap.workerInstanceId
            )
            guard
                case .activateReviewTarget(_, _, let replayedSource, let replayedTarget) =
                    replayedRequest.navigationCommand
            else {
                Issue.record("Expected the replacement stream to replay the exact Review target")
                return
            }
            #expect(replayedSource == reviewSource)
            #expect(replayedTarget == reviewTarget)
            try await closeBridgeProductSessionProducer(
                replacementMetadataProducer,
                in: replacementInstallation.session
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
                    source: .workspace(
                        rootPath: "Sources",
                        baseline: .ref(name: "HEAD~1"))
                ),
                appRootURL: testBridgeAppRootURL(),
                metadata: PaneMetadata(
                    paneId: PaneId(existingUUID: paneId),
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

private enum BootstrapSurfaceSelectionReplayError: Error {
    case expectedSurfaceSelectionFrame
}

private func consumeBootstrapSurfaceSelectionRequest(
    producerLease: BridgeProductProducerLease,
    installation: BridgeProductSessionInstallation,
    productAdmission: BridgeProductAdmissionContext
) async throws -> BridgeProductPaneSurfaceSelectionRequestedFrame {
    let decoder = try BridgeProductMetadataFrameDecoder()
    for _ in 0..<8 {
        guard (await installation.session.producerSnapshot()).queuedFrameCount > 0 else {
            break
        }
        let queuedFrame = try #require(
            await consumeNextBridgeProductProducerFrame(
                for: producerLease,
                from: installation.session,
                productAdmission: productAdmission
            )
        )
        for frame in try decoder.append(queuedFrame.data) {
            if case .paneSurfaceSelectionRequested(let request) = frame {
                return request
            }
        }
    }
    throw BootstrapSurfaceSelectionReplayError.expectedSurfaceSelectionFrame
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

@MainActor
private final class BootstrapReplacementOverlapState {
    weak var controller: BridgePaneController?
    var deliveredInstallations: [BridgeProductSessionInstallation] = []
    var replacementMetadataProducer: BridgeProductProducerLease?
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
