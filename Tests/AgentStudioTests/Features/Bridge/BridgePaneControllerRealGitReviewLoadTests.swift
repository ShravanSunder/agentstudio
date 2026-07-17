import Foundation
import Testing

@testable import AgentStudio

extension WebKitSerializedTests {
    /// End-to-end Review package load through the production git provider and
    /// direct product metadata source against a real git repository. Mirrors
    /// the shape a workspace pane gets from `openBridgeReviewInNewTab`: `.workspace`
    /// with the `.localDefaultBranch("main")` baseline over a single-commit
    /// repository containing working-tree changes.
    @MainActor
    @Suite(.serialized)
    struct BridgePaneControllerRealGitReviewLoadTests {
        init() {
            installTestAtomRegistryIfNeeded()
        }

        @Test("a real single-commit repo publishes a ready Review product snapshot")
        func realGitSingleCommitRepoPublishesReadyReviewProductSnapshot() async throws {
            // Arrange
            let repoURL = try FilesystemTestGitRepo.create(named: "bridge-review-controller-load")
            defer { FilesystemTestGitRepo.destroy(repoURL) }
            try FilesystemTestGitRepo.seedTrackedAndUntrackedChanges(at: repoURL)
            let harness = try await RealGitReviewLoadHarness.make(repositoryURL: repoURL)
            defer { harness.controller.teardown() }
            let metadataLease = try await harness.openReviewMetadataSubscription()

            // Act
            let result = await harness.controller.loadInitialReviewPackageIfPossible(correlationId: nil)
            let sourceAcceptedEvent = try await harness.nextReviewMetadataEvent(for: metadataLease)
            let snapshotEvent = try await harness.nextReviewMetadataEvent(for: metadataLease)

            // Assert
            let completedResult = try #require(result)
            guard case .success = completedResult else {
                Issue.record("Real-git Review package load failed: \(String(describing: completedResult))")
                return
            }
            let package = try #require(harness.controller.paneState.diff.packageMetadata)
            #expect(harness.controller.paneState.diff.status == .ready)

            guard case .sourceAccepted = sourceAcceptedEvent,
                case .snapshot = snapshotEvent
            else {
                Issue.record("Expected Review sourceAccepted followed by snapshot")
                return
            }
            #expect(sourceAcceptedEvent.packageId == package.packageId)
            #expect(sourceAcceptedEvent.generation == package.reviewGeneration.rawValue)
            #expect(snapshotEvent.packageId == package.packageId)
            #expect(snapshotEvent.revision == package.revision)
            try await closeBridgeProductSessionProducer(metadataLease, in: harness.installation.session)
            #expect((await harness.installation.session.producerSnapshot()).hasZeroResidue)
        }
    }
}

@MainActor
private struct RealGitReviewLoadHarness {
    let capabilityHeader: String
    let controlDispatcher: BridgeProductSchemeControlDispatcher
    let controller: BridgePaneController
    let installation: BridgeProductSessionInstallation
    let productAdmission: BridgeProductAdmissionContext
    let productProvider: BridgePaneProductSchemeProvider

    static func make(repositoryURL: URL) async throws -> Self {
        let paneId = UUIDv7.generate()
        let controller = BridgePaneController(
            paneId: paneId,
            state: BridgePaneState(
                panelKind: .diffViewer,
                source: .workspace(
                    rootPath: repositoryURL.path,
                    baseline: .localDefaultBranch(branchName: "main")
                )
            ),
            metadata: PaneMetadata(
                contentType: .diff,
                launchDirectory: repositoryURL,
                title: "Bridge Review",
                facets: PaneContextFacets(
                    repoId: UUIDv7.generate(),
                    worktreeId: UUIDv7.generate(),
                    worktreeName: "real-git-review",
                    cwd: repositoryURL
                )
            ),
            reviewSourceProvider: BridgeReviewSourceProviderFactory.gitProvider(
                repositoryPath: repositoryURL
            ),
            initialPaneActivity: .foreground
        )
        let productProvider = try #require(controller.productSchemeProvider)
        let installation = try #require(
            await controller.productSessionOwner.activeInstallation
        )
        let productAdmission = try #require(controller.productAdmissionGate.acquire())
        let capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(
            installation.capabilityBytes
        )
        let controlDispatcher = BridgeProductSchemeControlDispatcher(
            session: installation.session,
            provider: productProvider,
            productAdmission: productAdmission
        )
        #expect(controller.handleBridgeReady())
        return Self(
            capabilityHeader: capabilityHeader,
            controlDispatcher: controlDispatcher,
            controller: controller,
            installation: installation,
            productAdmission: productAdmission,
            productProvider: productProvider
        )
    }

    func openReviewMetadataSubscription() async throws -> BridgeProductProducerLease {
        let workerOpenRequest = try realGitReviewWorkerOpenRequest(installation: installation)
        guard
            case .response = try await controlDispatcher.dispatch(
                exactRequestBytes: try realGitReviewControlRequestBytes(workerOpenRequest),
                presentedCapability: capabilityHeader
            )
        else {
            throw RealGitReviewMetadataEventError.expectedWorkerSessionAccepted
        }
        let metadataRequest = try realGitReviewMetadataRequest(installation: installation)
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
        let metadataOpeningFrame = try realGitReviewMetadataFrame(
            from: try #require(
                await consumeNextBridgeProductProducerFrame(
                    for: metadataLease,
                    from: installation.session,
                    productAdmission: productAdmission
                )
            )
        )
        guard case .metadataStreamAccepted = metadataOpeningFrame else {
            throw RealGitReviewMetadataEventError.expectedMetadataStreamAccepted
        }
        let reviewOpenRequest = try realGitReviewSubscriptionOpenRequest(
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
        guard
            case .response(let reviewOpenResponseBytes) = try await controlDispatcher.dispatch(
                exactRequestBytes: try realGitReviewControlRequestBytes(reviewOpenRequest),
                presentedCapability: capabilityHeader
            ),
            case .subscriptionOpenAccepted = try BridgeProductStrictJSON.decode(
                BridgeProductControlResponse.self,
                from: reviewOpenResponseBytes
            )
        else {
            throw RealGitReviewMetadataEventError.expectedReviewSubscriptionAccepted
        }
        let subscriptionAcceptedFrame = try realGitReviewMetadataFrame(
            from: try #require(
                await consumeNextBridgeProductProducerFrame(
                    for: metadataLease,
                    from: installation.session,
                    productAdmission: productAdmission
                )
            )
        )
        guard case .subscriptionAccepted = subscriptionAcceptedFrame else {
            throw RealGitReviewMetadataEventError.expectedReviewSubscriptionAccepted
        }
        return metadataLease
    }

    func nextReviewMetadataEvent(
        for metadataLease: BridgeProductProducerLease
    ) async throws -> BridgeProductReviewMetadataEvent {
        try realGitReviewEvent(
            from: try realGitReviewMetadataFrame(
                from: try #require(
                    await consumeNextBridgeProductProducerFrame(
                        for: metadataLease,
                        from: installation.session,
                        productAdmission: productAdmission
                    )
                )
            )
        )
    }
}

private enum RealGitReviewMetadataEventError: Error {
    case expectedMetadataStreamAccepted
    case expectedReviewSubscriptionAccepted
    case expectedReviewMetadataEvent
    case expectedSingleMetadataFrame
    case expectedWorkerSessionAccepted
}

private func realGitReviewWorkerOpenRequest(
    installation: BridgeProductSessionInstallation
) throws -> BridgeProductControlRequest {
    try realGitReviewControlRequest([
        "kind": "workerSession.open",
        "paneSessionId": installation.bootstrap.paneSessionId,
        "request": NSNull(),
        "requestId": "request-open-real-git-review",
        "requestSequence": 1,
        "wireVersion": BridgeProductWireContract.version,
        "workerInstanceId": installation.bootstrap.workerInstanceId,
    ])
}

private func realGitReviewSubscriptionOpenRequest(
    installation: BridgeProductSessionInstallation
) throws -> BridgeProductControlRequest {
    try realGitReviewControlRequest([
        "kind": "subscription.open",
        "paneSessionId": installation.bootstrap.paneSessionId,
        "requestId": "request-review-open-real-git-review",
        "requestSequence": 2,
        "subscription": ["subscriptionKind": "review.metadata"],
        "subscriptionId": "review-subscription-real-git-review",
        "wireVersion": BridgeProductWireContract.version,
        "workerDerivationEpoch": 1,
        "workerInstanceId": installation.bootstrap.workerInstanceId,
    ])
}

private func realGitReviewMetadataRequest(
    installation: BridgeProductSessionInstallation
) throws -> BridgeProductMetadataStreamRequest {
    try BridgeProductStrictJSON.decode(
        BridgeProductMetadataStreamRequest.self,
        from: JSONSerialization.data(
            withJSONObject: [
                "kind": "metadataStream.open",
                "metadataStreamId": "metadata-real-git-review",
                "paneSessionId": installation.bootstrap.paneSessionId,
                "resumeFromStreamSequence": NSNull(),
                "wireVersion": BridgeProductWireContract.version,
                "workerInstanceId": installation.bootstrap.workerInstanceId,
            ],
            options: [.sortedKeys]
        )
    )
}

private func realGitReviewControlRequest(
    _ object: [String: Any]
) throws -> BridgeProductControlRequest {
    try BridgeProductStrictJSON.decode(
        BridgeProductControlRequest.self,
        from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    )
}

private func realGitReviewControlRequestBytes(
    _ request: BridgeProductControlRequest
) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(request)
}

private func realGitReviewMetadataFrame(
    from queuedFrame: BridgeProductQueuedProducerFrame
) throws -> BridgeProductMetadataFrame {
    let decoder = try BridgeProductMetadataFrameDecoder()
    let frames = try decoder.append(queuedFrame.data)
    guard frames.count == 1, let frame = frames.first else {
        throw RealGitReviewMetadataEventError.expectedSingleMetadataFrame
    }
    return frame
}

private func realGitReviewEvent(
    from frame: BridgeProductMetadataFrame
) throws -> BridgeProductReviewMetadataEvent {
    guard case .subscriptionData(let dataFrame) = frame,
        case .reviewMetadata(let event) = dataFrame.data
    else {
        throw RealGitReviewMetadataEventError.expectedReviewMetadataEvent
    }
    return event
}
