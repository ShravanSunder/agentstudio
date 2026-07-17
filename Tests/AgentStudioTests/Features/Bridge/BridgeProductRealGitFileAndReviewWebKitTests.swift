import Foundation
import Testing

@testable import AgentStudio

private struct BridgeProductWebKitCarrierApplicationReceipt: Equatable, Sendable {
    let accepted: Bool
    let publicationId: UUID
}

@MainActor
private final class BridgeProductWebKitCarrierControllerTarget {
    weak var controller: BridgePaneController?
    private(set) var applicationReceipts: [BridgeProductWebKitCarrierApplicationReceipt] = []
    private(set) var reviewContentSource: BridgePaneProductReviewContentSource?

    func install(_ controller: BridgePaneController) {
        self.controller = controller
        reviewContentSource = BridgePaneProductReviewContentSource(
            loaderCache: controller.reviewContentLoaderCache,
            acquireContentLease: { [weak controller] descriptor, productAdmission in
                controller?.reviewPublicationCoordinator.acquireContentLease(
                    handleId: descriptor.descriptorId,
                    packageId: descriptor.packageId,
                    requestedGeneration: BridgeReviewGeneration(descriptor.reviewGeneration),
                    sourceIdentity: descriptor.sourceIdentity,
                    productAdmission: productAdmission
                )
            },
            settleContentLease: { [weak controller] lease in
                controller?.reviewPublicationCoordinator.settleContentLease(lease) == true
            }
        )
    }

    func committedPublication(
        productAdmission: BridgeProductAdmissionContext
    ) -> BridgeReviewCommittedPublication? {
        controller?.reviewPublicationCoordinator.committedPublicationForReplay(
            productAdmission: productAdmission
        )
    }

    func isCurrentPublication(
        _ publicationId: UUID,
        productAdmission: BridgeProductAdmissionContext
    ) -> Bool {
        controller?.reviewPublicationCoordinator.isCurrentPublication(
            publicationId: publicationId,
            productAdmission: productAdmission
        ) == true
    }

    func recordApplication(
        _ publicationId: UUID,
        productAdmission: BridgeProductAdmissionContext
    ) -> Bool {
        let accepted =
            controller?.reviewPublicationCoordinator.recordWorkerApplication(
                publicationId: publicationId,
                productAdmission: productAdmission
            ) == true
        applicationReceipts.append(
            BridgeProductWebKitCarrierApplicationReceipt(
                accepted: accepted,
                publicationId: publicationId
            )
        )
        return accepted
    }
}

private struct BridgeProductWebKitCarrierReviewContentRelay:
    BridgePaneProductReviewContentProducing
{
    let target: BridgeProductWebKitCarrierControllerTarget

    func authoritativeItemId(
        for request: BridgeProductReviewContentRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async -> String? {
        guard let source = await target.reviewContentSource else { return nil }
        return await source.authoritativeItemId(
            for: request,
            productAdmission: productAdmission
        )
    }

    func contentBody(
        for request: BridgeProductReviewContentRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> BridgePaneProductReviewContentBody {
        guard let source = await target.reviewContentSource else {
            throw BridgePaneProductReviewContentSourceError.unavailablePackage
        }
        return try await source.contentBody(
            for: request,
            productAdmission: productAdmission
        )
    }
}

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    struct BridgeProductRealGitFileAndReviewWebKitTests {
        private struct LiveProof {
            let fileDOMAfterFileSwitch: BridgeProductWebKitCarrierDOMSnapshot
            let fileModeActivated: Bool
            let filePathSelected: Bool
            let native: BridgeProductWebKitCarrierNativeSnapshot
            let reviewDOMBeforeFileSwitch: BridgeProductWebKitCarrierDOMSnapshot
            let sourceOracle: LiveSourceOracle
            let trace: BridgeProductWebKitCarrierTrace
        }

        private struct LiveSourceOracle {
            let canaryText: String
            let path: String
        }

        private struct TransactionalPublicationHarness {
            let controller: BridgePaneController
            let controllerTarget: BridgeProductWebKitCarrierControllerTarget
            let fileMetadataSource: BridgeWebKitTrackingFileMetadataSource
            let installation: BridgeProductSessionInstallation
            let productAdmission: BridgeProductAdmissionContext
            let reviewMetadataSource: BridgeWebKitFailingReviewMetadataSource
            let traceRecorder: BridgeProductWebKitCarrierTraceRecorder
        }

        private struct FirstPublicationCheckpoint {
            let fileSnapshot: BridgeProductWebKitCarrierFileSubscriptionSnapshot
            let nativeSnapshot: BridgeProductWebKitCarrierNativeSnapshot
            let publication: BridgeReviewCommittedPublication
            let retiringLease: BridgeReviewContentAuthorityLease
            let reviewSnapshot: BridgeProductWebKitCarrierReviewMetadataSnapshot
            let trace: BridgeProductWebKitCarrierTrace
        }

        private struct TransactionalControllerInput {
            let committedCallTarget: BridgePaneProductCommittedCallTarget
            let installation: BridgeProductSessionInstallation
            let paneId: UUID
            let productAdmissionGate: BridgeProductAdmissionGate
            let productProvider: BridgePaneProductSchemeProvider
            let repoId: UUID
            let repoURL: URL
            let traceRecorder: BridgeProductWebKitCarrierTraceRecorder
            let worktreeId: UUID
        }

        private struct TransactionalPublicationProof {
            let applicationReceiptsAfterReplay: [BridgeProductWebKitCarrierApplicationReceipt]
            let applicationReceiptsBeforeReplay: [BridgeProductWebKitCarrierApplicationReceipt]
            let fileAfterFailure: BridgeProductWebKitCarrierFileSubscriptionSnapshot
            let fileBeforeFailure: BridgeProductWebKitCarrierFileSubscriptionSnapshot
            let finalPublicationState: BridgeReviewPublicationStateSnapshot
            let firstPublication: BridgeReviewCommittedPublication
            let nativeAfterFailure: BridgeProductWebKitCarrierNativeSnapshot
            let nativeBeforeFailure: BridgeProductWebKitCarrierNativeSnapshot
            let reviewAfterFailure: BridgeProductWebKitCarrierReviewMetadataSnapshot
            let reviewBeforeFailure: BridgeProductWebKitCarrierReviewMetadataSnapshot
            let retiringPublicationState: BridgeReviewPublicationStateSnapshot
            let secondPublication: BridgeReviewCommittedPublication
            let traceAfterFailure: BridgeProductWebKitCarrierTrace
            let traceBeforeFailure: BridgeProductWebKitCarrierTrace
        }

        private enum TransactionalPublicationTestError: Error {
            case initialPublicationDidNotApply
            case metadataSubscriptionsDidNotOpen
            case publicationFailureDidNotReopenReview
            case replayDidNotApply
        }

        init() {
            installTestAtomRegistryIfNeeded()
        }

        @Test("bundled comm worker carries real-git File and Review product data through production WebKit")
        func bundledWorkerCarriesRealGitFileAndReviewProductData() async throws {
            // Arrange
            let repoURL = try FilesystemTestGitRepo.create(named: "bridge-product-file-review-webkit")
            defer { FilesystemTestGitRepo.destroy(repoURL) }
            try FilesystemTestGitRepo.seedTrackedAndUntrackedChanges(at: repoURL)
            let sourceOracle = LiveSourceOracle(canaryText: "updated", path: "tracked.txt")
            let traceRecorder = BridgeProductWebKitCarrierTraceRecorder()
            let controller = makeController(
                repoURL: repoURL,
                traceRecorder: traceRecorder
            )

            // Act
            let run = try await collectLiveProof(
                controller: controller,
                sourceOracle: sourceOracle,
                traceRecorder: traceRecorder
            )

            // Assert
            assertProof(run)
        }

        @Test("Review publication failure replays committed B without replacing File or the pane worker")
        func reviewPublicationFailureReplaysCommittedBWithoutReplacingFileOrWorker() async throws {
            // Arrange
            let repoURL = try FilesystemTestGitRepo.create(named: "bridge-product-review-replay-webkit")
            defer { FilesystemTestGitRepo.destroy(repoURL) }
            try FilesystemTestGitRepo.seedTrackedAndUntrackedChanges(at: repoURL)
            try seedMultiWindowReviewChanges(at: repoURL)
            let harness = makeTransactionalPublicationHarness(repoURL: repoURL)

            // Act
            let run = try await collectTransactionalPublicationProof(
                harness: harness,
                repoURL: repoURL
            )

            // Assert
            assertTransactionalPublicationProof(run)
        }

        private func makeTransactionalPublicationHarness(
            repoURL: URL
        ) -> TransactionalPublicationHarness {
            let paneId = UUIDv7.generate()
            let repoId = UUIDv7.generate()
            let worktreeId = UUIDv7.generate()
            let traceRecorder = BridgeProductWebKitCarrierTraceRecorder()
            let controllerTarget = BridgeProductWebKitCarrierControllerTarget()
            let fileMetadataSource = makeTrackingFileMetadataSource(
                paneId: paneId,
                repoId: repoId,
                repoURL: repoURL,
                worktreeId: worktreeId
            )
            let reviewMetadataSource = BridgeWebKitFailingReviewMetadataSource()
            let (productProvider, committedCallTarget) = makeTransactionalProductProvider(
                controllerTarget: controllerTarget,
                fileMetadataSource: fileMetadataSource,
                reviewMetadataSource: reviewMetadataSource,
                traceRecorder: traceRecorder
            )
            let productAdmissionGate = BridgeProductAdmissionGate()
            let installation = BridgePaneController.makeInitialProductSessionInstallation(
                paneSessionId: paneId.uuidString,
                provider: productProvider,
                productAdmissionGate: productAdmissionGate
            )
            let controller = makeTransactionalController(
                TransactionalControllerInput(
                    committedCallTarget: committedCallTarget,
                    installation: installation,
                    paneId: paneId,
                    productAdmissionGate: productAdmissionGate,
                    productProvider: productProvider,
                    repoId: repoId,
                    repoURL: repoURL,
                    traceRecorder: traceRecorder,
                    worktreeId: worktreeId
                )
            )
            controllerTarget.install(controller)
            return TransactionalPublicationHarness(
                controller: controller,
                controllerTarget: controllerTarget,
                fileMetadataSource: fileMetadataSource,
                installation: installation,
                productAdmission: productAdmissionGate.acquire()!,
                reviewMetadataSource: reviewMetadataSource,
                traceRecorder: traceRecorder
            )
        }

        private func makeTrackingFileMetadataSource(
            paneId: UUID,
            repoId: UUID,
            repoURL: URL,
            worktreeId: UUID
        ) -> BridgeWebKitTrackingFileMetadataSource {
            BridgeWebKitTrackingFileMetadataSource(
                source: BridgePaneProductFileMetadataSource(
                    authority: BridgePaneProductFileSourceAuthority(
                        paneId: paneId,
                        worktree: Worktree(
                            id: worktreeId,
                            repoId: repoId,
                            name: "bridge-product-review-replay",
                            path: repoURL
                        )
                    )
                )
            )
        }

        private func makeTransactionalProductProvider(
            controllerTarget: BridgeProductWebKitCarrierControllerTarget,
            fileMetadataSource: BridgeWebKitTrackingFileMetadataSource,
            reviewMetadataSource: BridgeWebKitFailingReviewMetadataSource,
            traceRecorder: BridgeProductWebKitCarrierTraceRecorder
        ) -> (BridgePaneProductSchemeProvider, BridgePaneProductCommittedCallTarget) {
            let committedCallTarget = BridgePaneProductCommittedCallTarget()
            let provider = BridgePaneProductSchemeProvider(
                fileMetadataSource: fileMetadataSource,
                reviewMetadataSource: reviewMetadataSource,
                reviewContentSource: BridgeProductWebKitCarrierReviewContentRelay(
                    target: controllerTarget
                ),
                reviewPublicationReplay: { productAdmission in
                    controllerTarget.committedPublication(productAdmission: productAdmission)
                },
                isReviewPublicationCurrent: { publicationId, productAdmission in
                    controllerTarget.isCurrentPublication(
                        publicationId,
                        productAdmission: productAdmission
                    )
                },
                recordReviewPublicationApplication: { publicationId, productAdmission in
                    controllerTarget.recordApplication(
                        publicationId,
                        productAdmission: productAdmission
                    )
                },
                markReviewItemViewed: { itemId, productAdmission in
                    _ = productAdmission.withValidAdmission {
                        controllerTarget.controller?.runtime.paneState.review.markFileViewed(itemId)
                    }
                },
                handleReviewIntakeReady: { request, productAdmission in
                    await committedCallTarget.applyReviewIntakeReady(
                        request,
                        productAdmission: productAdmission
                    )
                },
                applyActiveViewerModeUpdate: { call, productAdmission in
                    await committedCallTarget.applyActiveViewerModeUpdate(
                        call,
                        productAdmission: productAdmission
                    )
                },
                lifecycleTraceRecorder: BridgeProductMetadataLifecycleTraceRecorder(
                    recorder: traceRecorder
                )
            )
            return (provider, committedCallTarget)
        }

        private func makeTransactionalController(
            _ input: TransactionalControllerInput
        ) -> BridgePaneController {
            BridgePaneController(
                paneId: input.paneId,
                state: BridgePaneState(
                    panelKind: .diffViewer,
                    source: .workspace(
                        rootPath: input.repoURL.path,
                        baseline: .localDefaultBranch(branchName: "main")
                    )
                ),
                metadata: PaneMetadata(
                    paneId: PaneId(uuid: input.paneId),
                    contentType: .diff,
                    launchDirectory: input.repoURL,
                    title: "Bridge Product Review Replay",
                    facets: PaneContextFacets(
                        repoId: input.repoId,
                        worktreeId: input.worktreeId,
                        worktreeName: "bridge-product-review-replay",
                        cwd: input.repoURL
                    )
                ),
                reviewSourceProvider: BridgeReviewSourceProviderFactory.gitProvider(
                    repositoryPath: input.repoURL
                ),
                telemetryRuntimePolicy: .live,
                telemetryScopeGate: BridgeTelemetryScopeGate(enabledScopes: []),
                telemetryRecorder: input.traceRecorder,
                productSessionDependencies: BridgePaneProductSessionDependencies(
                    installation: input.installation,
                    owner: BridgePaneController.makeProductSessionOwner(
                        paneSessionId: input.paneId.uuidString,
                        provider: input.productProvider,
                        productAdmissionGate: input.productAdmissionGate,
                        activeInstallation: input.installation
                    ),
                    committedCallTarget: input.committedCallTarget,
                    productProvider: input.productProvider
                )
            )
        }

        private func collectTransactionalPublicationProof(
            harness: TransactionalPublicationHarness,
            repoURL: URL
        ) async throws -> BridgeProductWebKitCarrierRunResult<TransactionalPublicationProof> {
            try await BridgeProductWebKitCarrierTestSupport.withHostedController(
                harness.controller
            ) { controller in
                controller.loadApp()
                try await waitForMetadataSubscriptions(harness)
                let firstCheckpoint = try await prepareFirstPublicationCheckpoint(
                    controller: controller,
                    harness: harness
                )
                return try await exerciseFailedPublicationAndReplay(
                    controller: controller,
                    firstCheckpoint: firstCheckpoint,
                    harness: harness,
                    repoURL: repoURL
                )
            }
        }

        private func waitForMetadataSubscriptions(
            _ harness: TransactionalPublicationHarness
        ) async throws {
            guard
                await BridgeProductWebKitCarrierTestSupport.waitUntil(
                    timeout: .seconds(15),
                    condition: {
                        let fileSnapshot = await harness.fileMetadataSource.snapshot()
                        let reviewSnapshot = await harness.reviewMetadataSource.snapshot()
                        return !fileSnapshot.openedSubscriptions.isEmpty
                            && !reviewSnapshot.openedSubscriptions.isEmpty
                    })
            else {
                throw TransactionalPublicationTestError.metadataSubscriptionsDidNotOpen
            }
        }

        private func prepareFirstPublicationCheckpoint(
            controller: BridgePaneController,
            harness: TransactionalPublicationHarness
        ) async throws -> FirstPublicationCheckpoint {
            guard
                await BridgeProductWebKitCarrierTestSupport.waitUntil(
                    timeout: .seconds(15),
                    condition: {
                        harness.controllerTarget.applicationReceipts.count == 1
                            && harness.controllerTarget.applicationReceipts[0].accepted
                    }),
                let publication = harness.controllerTarget.committedPublication(
                    productAdmission: harness.productAdmission
                ),
                let firstHandle = publication.contentHandles.first,
                let retiringLease = controller.reviewPublicationCoordinator.acquireContentLease(
                    handleId: firstHandle.handleId,
                    packageId: publication.package.packageId,
                    requestedGeneration: publication.package.reviewGeneration,
                    sourceIdentity: publication.package.query.queryId,
                    productAdmission: harness.productAdmission
                )
            else {
                throw TransactionalPublicationTestError.initialPublicationDidNotApply
            }
            await harness.reviewMetadataSource.armFailure(after: publication.publicationId)
            return FirstPublicationCheckpoint(
                fileSnapshot: await harness.fileMetadataSource.snapshot(),
                nativeSnapshot: await BridgeProductWebKitCarrierTestSupport.nativeSnapshot(
                    controller
                ),
                publication: publication,
                retiringLease: retiringLease,
                reviewSnapshot: await harness.reviewMetadataSource.snapshot(),
                trace: await harness.traceRecorder.scrubbedTrace()
            )
        }

        private func exerciseFailedPublicationAndReplay(
            controller: BridgePaneController,
            firstCheckpoint: FirstPublicationCheckpoint,
            harness: TransactionalPublicationHarness,
            repoURL: URL
        ) async throws -> TransactionalPublicationProof {
            try "publication B\n".write(
                to: repoURL.appending(path: "bridge-window-000.txt"),
                atomically: true,
                encoding: .utf8
            )
            controller.scheduleReviewPackageReloadForProductResync(reason: .productResync)
            guard
                await BridgeProductWebKitCarrierTestSupport.waitUntil(
                    timeout: .seconds(15),
                    condition: {
                        let snapshot = await harness.reviewMetadataSource.snapshot()
                        return snapshot.replayIsBlocked && snapshot.didCorruptFinalWindow
                    }),
                let secondPublication = harness.controllerTarget.committedPublication(
                    productAdmission: harness.productAdmission
                ),
                secondPublication.publicationId != firstCheckpoint.publication.publicationId
            else {
                throw TransactionalPublicationTestError.publicationFailureDidNotReopenReview
            }
            let receiptsBeforeReplay = harness.controllerTarget.applicationReceipts
            let fileAfterFailure = await harness.fileMetadataSource.snapshot()
            let reviewAfterFailure = await harness.reviewMetadataSource.snapshot()
            let nativeAfterFailure = await BridgeProductWebKitCarrierTestSupport.nativeSnapshot(
                controller
            )
            let retiringState = controller.reviewPublicationCoordinator.diagnosticSnapshot
            let traceAfterFailure = await harness.traceRecorder.scrubbedTrace()
            await harness.reviewMetadataSource.releaseReplay()
            guard
                await BridgeProductWebKitCarrierTestSupport.waitUntil(
                    timeout: .seconds(15),
                    condition: {
                        harness.controllerTarget.applicationReceipts.count == 2
                            && harness.controllerTarget.applicationReceipts.last?.publicationId
                                == secondPublication.publicationId
                            && harness.controllerTarget.applicationReceipts.last?.accepted == true
                    })
            else {
                throw TransactionalPublicationTestError.replayDidNotApply
            }
            let finalState = controller.reviewPublicationCoordinator.diagnosticSnapshot
            let receiptsAfterReplay = harness.controllerTarget.applicationReceipts
            _ = controller.reviewPublicationCoordinator.settleContentLease(
                firstCheckpoint.retiringLease
            )
            return TransactionalPublicationProof(
                applicationReceiptsAfterReplay: receiptsAfterReplay,
                applicationReceiptsBeforeReplay: receiptsBeforeReplay,
                fileAfterFailure: fileAfterFailure,
                fileBeforeFailure: firstCheckpoint.fileSnapshot,
                finalPublicationState: finalState,
                firstPublication: firstCheckpoint.publication,
                nativeAfterFailure: nativeAfterFailure,
                nativeBeforeFailure: firstCheckpoint.nativeSnapshot,
                reviewAfterFailure: reviewAfterFailure,
                reviewBeforeFailure: firstCheckpoint.reviewSnapshot,
                retiringPublicationState: retiringState,
                secondPublication: secondPublication,
                traceAfterFailure: traceAfterFailure,
                traceBeforeFailure: firstCheckpoint.trace
            )
        }

        private func assertTransactionalPublicationProof(
            _ run: BridgeProductWebKitCarrierRunResult<TransactionalPublicationProof>
        ) {
            let proof = run.value
            let firstPublicationId = proof.firstPublication.publicationId
            let secondPublicationId = proof.secondPublication.publicationId
            #expect(
                proof.applicationReceiptsBeforeReplay == [
                    BridgeProductWebKitCarrierApplicationReceipt(
                        accepted: true,
                        publicationId: firstPublicationId
                    )
                ],
                "transport-acknowledged invalid B must not produce an application receipt"
            )
            #expect(
                proof.applicationReceiptsAfterReplay == [
                    BridgeProductWebKitCarrierApplicationReceipt(
                        accepted: true,
                        publicationId: firstPublicationId
                    ),
                    BridgeProductWebKitCarrierApplicationReceipt(
                        accepted: true,
                        publicationId: secondPublicationId
                    ),
                ],
                "the worker must apply exact A then exact replayed B once"
            )
            #expect(proof.reviewAfterFailure.didCorruptFinalWindow)
            #expect(proof.reviewAfterFailure.corruptedPublicationId == secondPublicationId)
            #expect(
                proof.reviewAfterFailure.openedSubscriptions.count
                    == proof.reviewBeforeFailure.openedSubscriptions.count + 1
            )
            #expect(
                proof.reviewAfterFailure.cancelledSubscriptionIds.count
                    == proof.reviewBeforeFailure.cancelledSubscriptionIds.count + 1
            )
            #expect(
                proof.reviewAfterFailure.deliveryAttempts.suffix(2).allSatisfy {
                    $0.publicationId == secondPublicationId
                        && $0.package == proof.secondPublication.package
                },
                "Review reopen must replay the exact committed B publication and payload"
            )
            #expect(proof.fileAfterFailure == proof.fileBeforeFailure)
            #expect(
                proof.nativeAfterFailure.fileWorkerDerivationEpoch
                    == proof.nativeBeforeFailure.fileWorkerDerivationEpoch
            )
            #expect(
                proof.nativeAfterFailure.workerInstanceId
                    == proof.nativeBeforeFailure.workerInstanceId
            )
            #expect(
                proof.traceAfterFailure.completedReviewPublicationCount
                    == proof.traceBeforeFailure.completedReviewPublicationCount + 1,
                "the invalid first B delivery must be transport-observed before worker application fails"
            )
            #expect(
                proof.retiringPublicationState.active?.publicationId == secondPublicationId
            )
            #expect(
                proof.retiringPublicationState.retiring.map(\.publicationId)
                    == [firstPublicationId]
            )
            #expect(proof.finalPublicationState.active?.publicationId == secondPublicationId)
            #expect(proof.finalPublicationState.retiring.isEmpty)
            #expect(run.teardownSnapshot.hasZeroResidue)
        }

        private func seedMultiWindowReviewChanges(at repoURL: URL) throws {
            for index in 0..<70 {
                let filename = String(format: "bridge-window-%03d.txt", index)
                try "publication A \(index)\n".write(
                    to: repoURL.appending(path: filename),
                    atomically: true,
                    encoding: .utf8
                )
            }
        }

        private func makeController(
            repoURL: URL,
            traceRecorder: BridgeProductWebKitCarrierTraceRecorder
        ) -> BridgePaneController {
            let paneId = UUIDv7.generate()
            return BridgePaneController(
                paneId: paneId,
                state: BridgePaneState(
                    panelKind: .diffViewer,
                    source: .workspace(
                        rootPath: repoURL.path,
                        baseline: .localDefaultBranch(branchName: "main")
                    )
                ),
                metadata: PaneMetadata(
                    paneId: PaneId(uuid: paneId),
                    contentType: .diff,
                    launchDirectory: repoURL,
                    title: "Bridge Product Carrier",
                    facets: PaneContextFacets(
                        repoId: UUIDv7.generate(),
                        worktreeId: UUIDv7.generate(),
                        worktreeName: "bridge-product-carrier",
                        cwd: repoURL
                    )
                ),
                reviewSourceProvider: BridgeReviewSourceProviderFactory.gitProvider(
                    repositoryPath: repoURL
                ),
                telemetryRuntimePolicy: .live,
                telemetryScopeGate: BridgeTelemetryScopeGate(enabledScopes: []),
                telemetryRecorder: traceRecorder
            )
        }

        private func collectLiveProof(
            controller: BridgePaneController,
            sourceOracle: LiveSourceOracle,
            traceRecorder: BridgeProductWebKitCarrierTraceRecorder
        ) async throws -> BridgeProductWebKitCarrierRunResult<LiveProof> {
            try await BridgeProductWebKitCarrierTestSupport.withHostedController(controller) { hostedController in
                hostedController.loadApp()

                _ = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(15)) {
                    let dom = await BridgeProductWebKitCarrierTestSupport.domSnapshot(
                        hostedController.page
                    )
                    let native = await BridgeProductWebKitCarrierTestSupport.nativeSnapshot(
                        hostedController
                    )
                    return dom?.hasAppRoot == true && native.lifecycle == "active"
                }
                _ = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(15)) {
                    let trace = await traceRecorder.scrubbedTrace()
                    return trace.hasCanonicalEagerSubscriptions && trace.hasFileMetadataWindow
                }
                _ = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(15)) {
                    await traceRecorder.scrubbedTrace().hasReviewMetadataPublication
                }
                _ = await BridgeProductWebKitCarrierTestSupport.waitUntil(timeout: .seconds(15)) {
                    let dom = await BridgeProductWebKitCarrierTestSupport.domSnapshot(
                        hostedController.page
                    )
                    guard let dom, let reviewRenderedItemId = dom.reviewRenderedItemId else {
                        return false
                    }
                    return dom.hasReviewShell
                        && dom.hasReviewCodeViewPanel
                        && dom.reviewSelectedContentState == "ready"
                        && dom.reviewRenderedItemId == reviewRenderedItemId
                }
                let reviewDOMBeforeFileSwitch =
                    await BridgeProductWebKitCarrierTestSupport.domSnapshot(
                        hostedController.page
                    ) ?? .unavailable
                let fileModeActivated = await BridgeProductWebKitCarrierTestSupport.activateFileMode(
                    hostedController.page
                )
                let filePathSelected: Bool
                if fileModeActivated {
                    filePathSelected = await BridgeProductWebKitCarrierTestSupport.waitUntil(
                        timeout: .seconds(15)
                    ) {
                        await BridgeProductWebKitCarrierTestSupport.selectFilePath(
                            hostedController.page,
                            path: sourceOracle.path
                        )
                    }
                } else {
                    filePathSelected = false
                }
                _ = await BridgeProductWebKitCarrierTestSupport.waitUntil(
                    timeout: .seconds(15)
                ) {
                    let dom = await BridgeProductWebKitCarrierTestSupport.domSnapshot(
                        hostedController.page
                    )
                    return dom?.fileReadableText.contains(sourceOracle.canaryText) == true
                }
                let fileDOMAfterFileSwitch =
                    await BridgeProductWebKitCarrierTestSupport.domSnapshot(
                        hostedController.page
                    ) ?? .unavailable

                return LiveProof(
                    fileDOMAfterFileSwitch: fileDOMAfterFileSwitch,
                    fileModeActivated: fileModeActivated,
                    filePathSelected: filePathSelected,
                    native: await BridgeProductWebKitCarrierTestSupport.nativeSnapshot(hostedController),
                    reviewDOMBeforeFileSwitch: reviewDOMBeforeFileSwitch,
                    sourceOracle: sourceOracle,
                    trace: await traceRecorder.scrubbedTrace()
                )
            }
        }

        private func assertProof(
            _ run: BridgeProductWebKitCarrierRunResult<LiveProof>
        ) {
            let fileDOM = run.value.fileDOMAfterFileSwitch
            let reviewDOM = run.value.reviewDOMBeforeFileSwitch
            #expect(
                reviewDOM.hasAppRoot && fileDOM.hasAppRoot,
                "W0 product seam: the current bundled BridgeWeb app did not mount"
            )
            #expect(
                run.value.native.lifecycle == "active",
                "W0 product seam: the bundled worker did not open the production product session; native=\(run.value.native)"
            )
            #expect(
                run.value.trace.hasCanonicalEagerSubscriptions,
                "W0 product seam: the worker did not open canonical eager File+Review subscriptions; trace=\(run.value.trace)"
            )
            #expect(
                run.value.trace.hasFileMetadataWindow,
                "W0 product seam: production agentstudio-git File metadata did not reach the worker stream; trace=\(run.value.trace)"
            )
            #expect(
                run.value.trace.hasReviewMetadataPublication,
                "W0 product seam: production agentstudio-git Review metadata did not reach the worker stream; trace=\(run.value.trace)"
            )
            #expect(
                run.value.native.nextControlRequestSequence > 1,
                "W0 product seam: worker-initiated product command POSTs were not acknowledged; native=\(run.value.native)"
            )
            #expect(
                run.value.native.nextMetadataStreamSequence > 1,
                "W0 product seam: streamed metadata frames and bodyless observations did not advance; native=\(run.value.native)"
            )
            #expect(
                run.value.native.inFlightControlRequestSequence == nil,
                "W0 product seam: a product command remained in flight; native=\(run.value.native)"
            )
            #expect(
                reviewDOM.hasReviewModeHost && fileDOM.hasFileModeHost,
                "W0 product seam: the canonical File+Review viewer hosts were not both constructed; reviewDOM=\(reviewDOM), fileDOM=\(fileDOM)"
            )
            #expect(
                reviewDOM.hasReviewShell,
                "W0 construction seam: Review metadata crossed the worker but no product Review shell mounted; reviewDOM=\(reviewDOM), trace=\(run.value.trace)"
            )
            #expect(
                reviewDOM.hasReviewCodeViewPanel
                    && reviewDOM.reviewSelectedContentState == "ready"
                    && reviewDOM.reviewSelectedContentLineCount > 0,
                "W0 content-observation seam: Swift emitted Review content, but the worker did not acknowledge and drain the concurrent content streams into a ready CodeView; reviewDOM=\(reviewDOM), native=\(run.value.native)"
            )
            #expect(
                reviewDOM.reviewSelectedDisplayPath == run.value.sourceOracle.path,
                "G0 PACKAGED SELECTED IDENTITY MISSING: selected Review path did not match the live-git oracle; selected=\(reviewDOM.reviewSelectedDisplayPath ?? "missing"), expected=\(run.value.sourceOracle.path)"
            )
            #expect(
                reviewDOM.reviewRenderedItemId?.isEmpty == false,
                "G0 PACKAGED SEMANTIC ITEM MISSING: rendered Review item did not retain its canonical semantic identity"
            )
            #expect(
                run.value.fileModeActivated,
                "G0 PACKAGED FILE MODE MISSING: the real bundled File control was not available"
            )
            #expect(
                run.value.filePathSelected,
                "G0 PACKAGED FILE SELECTION MISSING: File mode did not select the live-git source through the real tree"
            )
            #expect(
                fileDOM.fileReadableText.contains(run.value.sourceOracle.canaryText),
                "W0 content-observation seam: File readable DOM did not contain the real-git canary"
            )
            #expect(
                run.teardownSnapshot.hasZeroResidue,
                "W0 teardown seam: production product session retained transport residue; snapshot=\(run.teardownSnapshot)"
            )
        }

    }
}
