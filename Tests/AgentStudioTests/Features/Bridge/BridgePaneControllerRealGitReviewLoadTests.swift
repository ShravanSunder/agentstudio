import AgentStudioGit
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
            defer {
                harness.controller.teardown()
                harness.removeSharedContentRoot()
            }
            let metadataLease = try await harness.openReviewMetadataSubscription()
            let metadataEventsTask = Task { @MainActor in
                let sourceAcceptedEvent = try await harness.nextReviewMetadataEvent(
                    for: metadataLease
                )
                let snapshotEvent = try await harness.nextReviewMetadataEvent(for: metadataLease)
                return (sourceAcceptedEvent, snapshotEvent)
            }

            // Act
            let result = await harness.controller.loadInitialReviewPackageIfPossible(correlationId: nil)
            let completedResult = try #require(result)
            guard case .success = completedResult else {
                metadataEventsTask.cancel()
                try await closeBridgeProductSessionProducer(
                    metadataLease,
                    in: harness.installation.session
                )
                _ = await metadataEventsTask.result
                Issue.record("Real-git Review package load failed: \(String(describing: completedResult))")
                return
            }
            let (sourceAcceptedEvent, snapshotEvent) = try await metadataEventsTask.value

            // Assert
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
            let trackedItem = try #require(
                package.itemsById.values.first { $0.headPath == "tracked.txt" }
            )
            let trackedBaseHandle = try #require(trackedItem.contentRoles.base)
            let trackedHeadHandle = try #require(trackedItem.contentRoles.head)
            let trackedBaseContent = try await harness.reviewSourceProvider.loadContent(
                BridgeContentLoadRequest(
                    handle: trackedBaseHandle,
                    requestedGeneration: package.reviewGeneration
                )
            )
            let trackedHeadContent = try await harness.reviewSourceProvider.loadContent(
                BridgeContentLoadRequest(
                    handle: trackedHeadHandle,
                    requestedGeneration: package.reviewGeneration
                )
            )
            #expect(trackedBaseContent.data == Data("initial\n".utf8))
            #expect(trackedHeadContent.data == Data("initial\nupdated\n".utf8))
            #expect(harness.controller.reviewSharedConstructionBinder != nil)
            let constructionSnapshot = await harness.constructionCoordinator.snapshot()
            #expect(constructionSnapshot.entryCount == 1)
            #expect(constructionSnapshot.leaseCount == 1)
            #expect(constructionSnapshot.payloadCount == 1)
            #expect(constructionSnapshot.locatorCount > 0)
            #expect(await harness.controller.teardown().value)
            #expect((await harness.installation.session.producerSnapshot()).hasZeroResidue)
            await assertBridgeConstructionCoordinatorDrained(harness.constructionCoordinator)
            #expect(await harness.reviewDataClient.registeredContentLocatorCount() == 0)
            #expect(harness.sharedContentBackingChildren().isEmpty)
        }
    }
}

@MainActor
private struct RealGitReviewLoadHarness {
    let capabilityHeader: String
    let controlDispatcher: BridgeProductSchemeControlDispatcher
    let controller: BridgePaneController
    let constructionCoordinator: BridgeWorktreeProductConstructionCoordinator
    let installation: BridgeProductSessionInstallation
    let productAdmission: BridgeProductAdmissionContext
    let productProvider: BridgePaneProductSchemeProvider
    let reviewDataClient: AgentStudioGitBridgeReviewDataClient<LibGit2AgentStudioGitLocalClient>
    let reviewSourceProvider: BridgeGitReviewSourceProvider
    let sharedContentRootURL: URL

    static func make(repositoryURL: URL) async throws -> Self {
        let paneId = UUIDv7.generate()
        let gitReadContext = makeBridgeGitReadContext(rootURL: repositoryURL)
        let constructionCoordinator = BridgeWorktreeProductConstructionCoordinator()
        let sharedContentRootURL = FileManager.default.temporaryDirectory
            .appending(path: "bridge-real-git-review-content-\(UUIDv7.generate().uuidString)")
        let reviewDataClient = AgentStudioGitBridgeReviewDataClient(
            repositoryPath: repositoryURL,
            client: LibGit2AgentStudioGitLocalClient(),
            gitReadContext: gitReadContext,
            sharedContentRootURL: sharedContentRootURL
        )
        let reviewSourceProvider = BridgeGitReviewSourceProvider(client: reviewDataClient)
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
            reviewSourceProvider: reviewSourceProvider,
            gitReadContext: gitReadContext,
            worktreeProductConstructionCoordinator: constructionCoordinator,
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
            constructionCoordinator: constructionCoordinator,
            installation: installation,
            productAdmission: productAdmission,
            productProvider: productProvider,
            reviewDataClient: reviewDataClient,
            reviewSourceProvider: reviewSourceProvider,
            sharedContentRootURL: sharedContentRootURL
        )
    }

    func sharedContentBackingChildren() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: sharedContentRootURL,
            includingPropertiesForKeys: nil
        )) ?? []
    }

    func removeSharedContentRoot() {
        try? FileManager.default.removeItem(at: sharedContentRootURL)
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
            throw RealGitReviewMetadataEventError.expectedReviewSubscriptionControlAccepted
        }
        var observedSubscriptionAcceptance = false
        for _ in 0..<2 {
            let frame = try realGitReviewMetadataFrame(
                from: try #require(
                    await consumeNextBridgeProductProducerFrame(
                        for: metadataLease,
                        from: installation.session,
                        productAdmission: productAdmission
                    )
                )
            )
            switch frame {
            case .panePresentation(let presentation):
                #expect(presentation.nativeActivity == .foreground)
            case .subscriptionAccepted:
                observedSubscriptionAcceptance = true
            default:
                throw RealGitReviewMetadataEventError.unexpectedReviewSubscriptionFrame(
                    String(describing: frame)
                )
            }
            if observedSubscriptionAcceptance { break }
        }
        guard observedSubscriptionAcceptance else {
            throw RealGitReviewMetadataEventError.expectedReviewSubscriptionFrameAccepted
        }
        return metadataLease
    }

    func nextReviewMetadataEvent(
        for metadataLease: BridgeProductProducerLease
    ) async throws -> BridgeProductReviewMetadataEvent {
        let frame = try realGitReviewMetadataFrame(
            from: try #require(
                await consumeNextBridgeProductProducerFrame(
                    for: metadataLease,
                    from: installation.session,
                    productAdmission: productAdmission
                )
            )
        )
        return try realGitReviewEvent(from: frame)
    }
}

private enum RealGitReviewMetadataEventError: Error {
    case expectedMetadataStreamAccepted
    case expectedReviewSubscriptionControlAccepted
    case expectedReviewSubscriptionFrameAccepted
    case unexpectedReviewSubscriptionFrame(String)
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
