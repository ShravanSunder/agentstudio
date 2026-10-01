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
                        baseline: .unstaged)
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
            let visibleInstallation = try #require(await controller.productSessionOwner.activeInstallation)
            let visibleAdmission = try #require(controller.productAdmissionGate.acquire())
            let visibleMetadataProducer = try await installRefreshAdmissionMetadataProducer(
                installation: visibleInstallation,
                productProvider: try #require(controller.productSchemeProvider),
                productAdmission: visibleAdmission
            )
            // G2 uses the page's accepted mode after the worker and metadata stream open.
            await sendPageActiveViewerMode(
                .review, controller: controller, productAdmission: visibleAdmission, sequence: 1
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
            try await closeBridgeProductSessionProducer(visibleMetadataProducer, in: visibleInstallation.session)

            // Act
            await controller.enqueueProductSessionBootstrapRequest(
                requestId: "failed-initial-bootstrap",
                reason: .initial
            )
            let initialInstallation = try #require(deliveredInstallations.first)
            await controller.enqueueProductSessionBootstrapRequest(
                requestId: "retry-initial-bootstrap",
                reason: .initial
            )
            let replacementInstallation = try #require(deliveredInstallations.last)
            #expect(
                (await controller.productSessionOwner.activeInstallation)?.bootstrap.workerInstanceId
                    == replacementInstallation.bootstrap.workerInstanceId
            )
            _ = try await assertRetiredPaneProductCommandRefusal(
                installation: initialInstallation,
                handler: BridgeSchemeHandler(
                    paneId: paneId, appRootURL: testBridgeAppRootURL(),
                    productSessionRouter: await controller.productSessionOwner.schemeRouter
                )
            )
            let productProvider = try #require(controller.productSchemeProvider)
            let replaySubscription = try await openBootstrapReviewReplaySubscription(
                controller: controller,
                installation: replacementInstallation,
                productProvider: productProvider
            )
            let replayPublication = try await consumeBootstrapReviewPublication(
                subscription: replaySubscription,
                installation: replacementInstallation
            )

            // Assert
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
            #expect(replayPublication.displayed?.packageId == committedPackage.packageId)
            #expect(replayPublication.displayed?.generation == committedPackage.reviewGeneration.rawValue)
            try await closeBridgeProductSessionProducer(
                replaySubscription.lease,
                in: replacementInstallation.session
            )
            #expect(await controller.beginTeardown().value)
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
            let teardownTask = controller.beginTeardown()
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
            #expect(await controller.beginTeardown().value)
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
            #expect(await controller.beginTeardown().value)
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
            #expect(await controller.beginTeardown().value)
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
            #expect(await controller.beginTeardown().value)
        }

        @Test(
            "explicit cold Review intake admits nil or current stream and rejects stale stream",
            arguments: ["background-warmup", "sequence_gap"]
        )
        func coldReviewIntakeAdmitsNilOrCurrentStreamAndRejectsStaleStream(reason: String) async throws {
            // Arrange
            let nilStreamController = makeColdReviewIntakeController()
            let currentStreamController = makeColdReviewIntakeController()
            let staleStreamController = makeColdReviewIntakeController()
            defer {
                // fire-and-forget: defer cannot await; cleanup only
                _ = nilStreamController.beginTeardown()
                // fire-and-forget: defer cannot await; cleanup only
                _ = currentStreamController.beginTeardown()
                // fire-and-forget: defer cannot await; cleanup only
                _ = staleStreamController.beginTeardown()
            }
            let nilStreamAdmission = try #require(nilStreamController.productAdmissionGate.acquire())
            let currentStreamAdmission = try #require(
                currentStreamController.productAdmissionGate.acquire()
            )
            let staleStreamAdmission = try #require(
                staleStreamController.productAdmissionGate.acquire()
            )

            // Listener readiness alone must not start initial Review construction.
            await nilStreamController.handleCommittedProductReviewIntakeReady(
                BridgeProductReviewIntakeReadyRequest(reason: nil, streamId: nil),
                productAdmission: nilStreamAdmission
            )
            #expect(nilStreamController.activeReviewRefreshTask == nil)
            #expect(nilStreamController.paneState.diff.packageMetadata == nil)

            // Act
            await nilStreamController.handleCommittedProductReviewIntakeReady(
                BridgeProductReviewIntakeReadyRequest(reason: reason, streamId: nil),
                productAdmission: nilStreamAdmission
            )
            await currentStreamController.handleCommittedProductReviewIntakeReady(
                BridgeProductReviewIntakeReadyRequest(
                    reason: reason,
                    streamId: currentStreamController.reviewProtocolStreamId()
                ),
                productAdmission: currentStreamAdmission
            )
            await staleStreamController.handleCommittedProductReviewIntakeReady(
                BridgeProductReviewIntakeReadyRequest(
                    reason: reason,
                    streamId: "review:stale-stream"
                ),
                productAdmission: staleStreamAdmission
            )

            // Assert
            let nilStreamLoadTask = nilStreamController.activeReviewRefreshTask
            let currentStreamLoadTask = currentStreamController.activeReviewRefreshTask
            #expect(staleStreamController.activeReviewRefreshTask == nil)
            #expect(staleStreamController.paneState.diff.packageMetadata == nil)
            // A fast admitted load may already be complete; its published result is the contract.
            await nilStreamLoadTask?.value
            await currentStreamLoadTask?.value
            #expect(nilStreamController.paneState.diff.status == .ready)
            #expect(nilStreamController.paneState.diff.packageMetadata != nil)
            #expect(currentStreamController.paneState.diff.status == .ready)
            #expect(currentStreamController.paneState.diff.packageMetadata != nil)
            #expect(await nilStreamController.beginTeardown().value)
            #expect(await currentStreamController.beginTeardown().value)
            #expect(await staleStreamController.beginTeardown().value)
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
                        baseline: .unstaged)
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
