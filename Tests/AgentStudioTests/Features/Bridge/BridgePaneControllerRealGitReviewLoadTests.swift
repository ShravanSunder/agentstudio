import Foundation
import Testing

@testable import AgentStudio

extension WebKitSerializedTests {
    /// End-to-end Review package load through the production git provider and
    /// direct product metadata source against a real git repository. Mirrors
    /// the shape a workspace pane gets from `openBridgeReview`: `.workspace`
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

            let paneId = UUIDv7.generate()
            let reviewMetadataSource = BridgePaneProductReviewMetadataSource(
                initialAvailability: .loading
            )
            let reviewMetadataEvents = RealGitReviewProductEventCapture()
            try await reviewMetadataSource.open(
                subscription: try realGitReviewProductSubscription()
            ) { event in
                await reviewMetadataEvents.append(event)
            }
            let productProvider = BridgePaneProductSchemeProvider(
                fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
                reviewMetadataSource: reviewMetadataSource,
                reviewContentSource: BridgeUnavailablePaneProductReviewContentSource(),
                markReviewItemViewed: { _ in }
            )
            let installation = BridgePaneController.makeInitialProductSessionInstallation(
                paneSessionId: paneId.uuidString,
                provider: productProvider
            )
            let controller = BridgePaneController(
                paneId: paneId,
                state: BridgePaneState(
                    panelKind: .diffViewer,
                    source: .workspace(
                        rootPath: repoURL.path,
                        baseline: .localDefaultBranch(branchName: "main")
                    )
                ),
                metadata: PaneMetadata(
                    contentType: .diff,
                    launchDirectory: repoURL,
                    title: "Bridge Review",
                    facets: PaneContextFacets(
                        repoId: UUIDv7.generate(),
                        worktreeId: UUIDv7.generate(),
                        worktreeName: "real-git-review",
                        cwd: repoURL
                    )
                ),
                reviewSourceProvider: BridgeReviewSourceProviderFactory.gitProvider(
                    repositoryPath: repoURL
                ),
                productSessionDependencies: BridgePaneProductSessionDependencies(
                    installation: installation,
                    owner: BridgePaneController.makeProductSessionOwner(
                        paneSessionId: paneId.uuidString,
                        provider: productProvider,
                        activeInstallation: installation
                    ),
                    productProvider: productProvider
                )
            )
            defer { controller.teardown() }
            controller.handleBridgeReady()

            // Act
            let result = await controller.loadInitialReviewPackageIfPossible(correlationId: nil)

            // Assert
            let completedResult = try #require(result)
            guard case .success = completedResult else {
                Issue.record("Real-git Review package load failed: \(String(describing: completedResult))")
                return
            }
            let package = try #require(controller.paneState.diff.packageMetadata)
            #expect(controller.paneState.diff.status == .ready)

            let events = await reviewMetadataEvents.events
            let acceptedEvent = try #require(
                events.first { event in
                    if case .sourceAccepted = event { return true }
                    return false
                }
            )
            let snapshotEvent = try #require(
                events.first { event in
                    if case .snapshot = event { return true }
                    return false
                }
            )
            #expect(acceptedEvent.packageId == package.packageId)
            #expect(acceptedEvent.generation == package.reviewGeneration.rawValue)
            #expect(snapshotEvent.packageId == package.packageId)
            #expect(snapshotEvent.revision == package.revision)
        }
    }
}

private actor RealGitReviewProductEventCapture {
    private(set) var events: [BridgeProductReviewMetadataEvent] = []

    func append(_ event: BridgeProductReviewMetadataEvent) {
        events.append(event)
    }
}

private func realGitReviewProductSubscription() throws -> BridgeProductSubscriptionSnapshot {
    let interestState = BridgeProductSubscriptionInterestState.reviewMetadata(interests: [])
    return BridgeProductSubscriptionSnapshot(
        subscription: .reviewMetadata,
        subscriptionId: "real-git-review-product-subscription",
        subscriptionKind: .reviewMetadata,
        workerDerivationEpoch: 1,
        interestRevision: 0,
        interestSha256: try interestState.sha256Hex(),
        interestState: interestState,
        hasStagedUpdate: false
    )
}
