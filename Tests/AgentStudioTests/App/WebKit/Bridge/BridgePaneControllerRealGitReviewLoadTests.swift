import AgentStudioGit
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

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
            installTestCoreAtomsIfNeeded()
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
            let untrackedItem = try #require(
                package.itemsById.values.first { $0.headPath == "untracked.txt" }
            )
            #expect(untrackedItem.contentRoles.base == nil)
            let untrackedHeadHandle = try #require(untrackedItem.contentRoles.head)
            let untrackedHeadContent = try await harness.reviewSourceProvider.loadContent(
                BridgeContentLoadRequest(
                    handle: untrackedHeadHandle,
                    requestedGeneration: package.reviewGeneration
                )
            )
            #expect(untrackedHeadContent.data == Data("new file\n".utf8))
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

        @Test("a real contribution publishes complete dirty state and excludes target-only movement")
        func realContributionPublishesCompleteDirtyStateAndExcludesTargetOnlyMovement() async throws {
            // Arrange
            let repoURL = try FilesystemTestGitRepo.create(named: "bridge-review-contribution")
            defer { FilesystemTestGitRepo.destroy(repoURL) }
            let fixture = try seedCompleteContribution(at: repoURL)
            let harness = try await RealGitReviewLoadHarness.make(repositoryURL: repoURL)
            defer {
                harness.controller.teardown()
                harness.removeSharedContentRoot()
            }
            let metadataLease = try await harness.openReviewMetadataSubscription()
            let initialEventsTask = Task { @MainActor in
                let sourceAccepted = try await harness.nextReviewMetadataEvent(for: metadataLease)
                let snapshot = try await harness.nextReviewMetadataEvent(for: metadataLease)
                return (sourceAccepted, snapshot)
            }

            // Act
            let initialResult = try #require(
                await harness.controller.loadInitialReviewPackageIfPossible(correlationId: nil)
            )
            guard case .success = initialResult else {
                Issue.record("Expected the real contribution package to load: \(initialResult)")
                return
            }
            let (initialSourceAcceptedEvent, initialSnapshotEvent) = try await initialEventsTask.value
            let initialPackage = try #require(harness.controller.paneState.diff.packageMetadata)

            // Assert
            guard case .sourceAccepted = initialSourceAcceptedEvent,
                case .snapshot(let initialSnapshot) = initialSnapshotEvent,
                case .contribution(let initialOrigin) = initialPackage.comparisonOrigin
            else {
                Issue.record("Expected contribution source acceptance, snapshot, and origin")
                return
            }
            #expect(initialSnapshot.comparisonOrigin == initialPackage.comparisonOrigin)
            #expect(initialSnapshot.reviewedSubjectLabel == "real-git-review")
            #expect(initialOrigin.symbolicTarget == .localDefaultBranch(branchName: "main"))
            #expect(initialOrigin.resolvedTargetOID == fixture.initialTargetOID)
            #expect(initialOrigin.reviewedHeadOID == fixture.reviewedHeadOID)
            #expect(initialOrigin.baseOID == fixture.sharedBaseOID)
            let initialPaths = Set(initialPackage.itemsById.values.compactMap(\.headPath))
            #expect(initialPaths.isSuperset(of: fixture.expectedContributionPaths))
            #expect(!initialPaths.contains("target-only.txt"))
            try await assertCompleteContributionContent(
                package: initialPackage,
                provider: harness.reviewSourceProvider
            )

            let successorTargetOID = try advanceTargetOnlyHistory(at: repoURL)
            let successorEventsTask = Task { @MainActor in
                let reset = try await harness.nextReviewMetadataEvent(for: metadataLease)
                let sourceAccepted = try await harness.nextReviewMetadataEvent(for: metadataLease)
                let snapshot = try await harness.nextReviewMetadataEvent(for: metadataLease)
                return (reset, sourceAccepted, snapshot)
            }
            harness.controller.refreshAdmissionCoordinator.recordInvalidation(
                fileChangeset: nil,
                requiresReviewRefresh: true
            )
            let reservation = try #require(
                harness.controller.refreshAdmissionCoordinator.reserveForegroundRefreshPass(
                    for: .review
                )
            )

            let refreshOutcome = await harness.controller.refreshCurrentReviewPackage(
                reservation: reservation,
                foregroundWorkAdmission: reservation.foregroundWorkAdmission,
                productAdmission: harness.productAdmission
            )
            harness.controller.refreshAdmissionCoordinator.completeRefreshPass(
                reservation,
                outcome: refreshOutcome
            )
            let (resetEvent, successorSourceAcceptedEvent, successorSnapshotEvent) =
                try await successorEventsTask.value
            let successorPackage = try #require(harness.controller.paneState.diff.packageMetadata)

            #expect(refreshOutcome == .succeeded)
            guard case .reset(let reset) = resetEvent,
                case .sourceAccepted = successorSourceAcceptedEvent,
                case .snapshot(let successorSnapshot) = successorSnapshotEvent,
                case .contribution(let successorOrigin) = successorPackage.comparisonOrigin
            else {
                Issue.record("Expected target movement to reset and publish a successor contribution snapshot")
                return
            }
            #expect(successorPackage.reviewGeneration == initialPackage.reviewGeneration.next())
            #expect(successorPackage != initialPackage)
            #expect(successorOrigin.resolvedTargetOID == successorTargetOID)
            #expect(successorOrigin.reviewedHeadOID == initialOrigin.reviewedHeadOID)
            #expect(successorOrigin.baseOID == initialOrigin.baseOID)
            #expect(successorPackage.itemsById.keys == initialPackage.itemsById.keys)
            #expect(!successorPackage.itemsById.values.compactMap(\.headPath).contains("target-only.txt"))
            #expect(reset.comparisonOrigin == successorPackage.comparisonOrigin)
            #expect(successorSnapshot.comparisonOrigin == successorPackage.comparisonOrigin)
            #expect(successorSnapshot.identity.publicationId != initialSnapshot.identity.publicationId)
            #expect(initialPackage.comparisonOrigin == .contribution(initialOrigin))
            #expect(initialPackage.itemsById.values.compactMap(\.headPath).contains("target-only.txt") == false)

            #expect(await harness.controller.teardown().value)
            #expect((await harness.installation.session.producerSnapshot()).hasZeroResidue)
            await assertBridgeConstructionCoordinatorDrained(harness.constructionCoordinator)
            #expect(await harness.reviewDataClient.registeredContentLocatorCount() == 0)
            #expect(harness.sharedContentBackingChildren().isEmpty)
        }
    }
}

private struct CompleteContributionFixture {
    let expectedContributionPaths: Set<String>
    let initialTargetOID: String
    let reviewedHeadOID: String
    let sharedBaseOID: String
}

private func seedCompleteContribution(at repositoryURL: URL) throws -> CompleteContributionFixture {
    try "initial\n".write(
        to: repositoryURL.appending(path: "tracked.txt"),
        atomically: true,
        encoding: .utf8
    )
    try FilesystemTestGitRepo.runGit(at: repositoryURL, args: ["add", "tracked.txt"])
    try FilesystemTestGitRepo.runGit(at: repositoryURL, args: ["commit", "-m", "shared base"])
    let sharedBaseOID = try normalizedGitOID(
        FilesystemTestGitRepo.runGit(at: repositoryURL, args: ["rev-parse", "HEAD"])
    )

    try FilesystemTestGitRepo.runGit(at: repositoryURL, args: ["switch", "-c", "feature/review"])
    try "committed\n".write(
        to: repositoryURL.appending(path: "committed.txt"),
        atomically: true,
        encoding: .utf8
    )
    try FilesystemTestGitRepo.runGit(at: repositoryURL, args: ["add", "committed.txt"])
    try FilesystemTestGitRepo.runGit(at: repositoryURL, args: ["commit", "-m", "reviewed commit"])
    let reviewedHeadOID = try normalizedGitOID(
        FilesystemTestGitRepo.runGit(at: repositoryURL, args: ["rev-parse", "HEAD"])
    )

    try FilesystemTestGitRepo.runGit(at: repositoryURL, args: ["switch", "main"])
    try "target only\n".write(
        to: repositoryURL.appending(path: "target-only.txt"),
        atomically: true,
        encoding: .utf8
    )
    try FilesystemTestGitRepo.runGit(at: repositoryURL, args: ["add", "target-only.txt"])
    try FilesystemTestGitRepo.runGit(at: repositoryURL, args: ["commit", "-m", "target-only commit"])
    let initialTargetOID = try normalizedGitOID(
        FilesystemTestGitRepo.runGit(at: repositoryURL, args: ["rev-parse", "HEAD"])
    )

    try FilesystemTestGitRepo.runGit(at: repositoryURL, args: ["switch", "feature/review"])
    try "staged\n".write(
        to: repositoryURL.appending(path: "staged.txt"),
        atomically: true,
        encoding: .utf8
    )
    try FilesystemTestGitRepo.runGit(at: repositoryURL, args: ["add", "staged.txt"])
    try "initial\nunstaged\n".write(
        to: repositoryURL.appending(path: "tracked.txt"),
        atomically: true,
        encoding: .utf8
    )
    try "untracked\n".write(
        to: repositoryURL.appending(path: "untracked.txt"),
        atomically: true,
        encoding: .utf8
    )
    return CompleteContributionFixture(
        expectedContributionPaths: ["committed.txt", "staged.txt", "tracked.txt", "untracked.txt"],
        initialTargetOID: initialTargetOID,
        reviewedHeadOID: reviewedHeadOID,
        sharedBaseOID: sharedBaseOID
    )
}

private func advanceTargetOnlyHistory(at repositoryURL: URL) throws -> String {
    let targetTreeOID = try normalizedGitOID(
        FilesystemTestGitRepo.runGit(at: repositoryURL, args: ["rev-parse", "main^{tree}"])
    )
    let targetParentOID = try normalizedGitOID(
        FilesystemTestGitRepo.runGit(at: repositoryURL, args: ["rev-parse", "main"])
    )
    let successorTargetOID = try normalizedGitOID(
        FilesystemTestGitRepo.runGit(
            at: repositoryURL,
            args: ["commit-tree", targetTreeOID, "-p", targetParentOID, "-m", "advance target only"]
        )
    )
    try FilesystemTestGitRepo.runGit(
        at: repositoryURL,
        args: ["update-ref", "refs/heads/main", successorTargetOID, targetParentOID]
    )
    return successorTargetOID
}

private func normalizedGitOID(_ output: String) throws -> String {
    let oid = output.trimmingCharacters(in: .whitespacesAndNewlines)
    return try #require(oid.isEmpty ? nil : oid)
}

private func assertCompleteContributionContent(
    package: BridgeReviewPackage,
    provider: BridgeGitReviewSourceProvider
) async throws {
    let expectedContentByPath: [String: String] = [
        "committed.txt": "committed\n",
        "staged.txt": "staged\n",
        "tracked.txt": "initial\nunstaged\n",
        "untracked.txt": "untracked\n",
    ]
    for (path, expectedContent) in expectedContentByPath {
        let item = try #require(package.itemsById.values.first { $0.headPath == path })
        let headHandle = try #require(item.contentRoles.head)
        let loadedContent = try await provider.loadContent(
            BridgeContentLoadRequest(
                handle: headHandle,
                requestedGeneration: package.reviewGeneration
            )
        )
        #expect(loadedContent.data == Data(expectedContent.utf8))
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
            appRootURL: testBridgeAppRootURL(),
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
        while true {
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
            case .subscriptionData(let dataFrame):
                guard case .reviewMetadata(let event) = dataFrame.data else {
                    throw RealGitReviewMetadataEventError.expectedReviewMetadataEvent
                }
                return event
            case .panePresentation:
                continue
            default:
                throw RealGitReviewMetadataEventError.expectedReviewMetadataEvent
            }
        }
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
