import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioBridge

@MainActor
struct RefreshAdmissionIntegrationFixture {
    let baseEndpoint: BridgeSourceEndpoint
    let headEndpoint: BridgeSourceEndpoint
    let refreshedComparison: BridgeEndpointComparison
    let reviewProvider: BridgeReviewSourceProviderFake
    let fileMetadataSource: RefreshAdmissionTrackingFileMetadataSource
    let metadataProducerLease: BridgeProductProducerLease
    let productInstallation: BridgeProductSessionInstallation
    let productAdmission: BridgeProductAdmissionContext
    let productProvider: BridgePaneProductSchemeProvider
    let controller: BridgePaneController

    func loadInitialReviewPackage() async throws {
        controller.applyBridgePaneActivity(.foreground)
        await waitForActiveReviewRefreshTaskToFinish(controller)
        #expect(controller.paneState.diff.packageMetadata?.orderedItemIds == ["item-initial"])
    }

    func makeChangeset(paths: [String], batchSequence: UInt64) -> FileChangeset {
        FileChangeset(
            worktreeId: headEndpoint.worktreeId,
            repoId: headEndpoint.repoId,
            rootPath: URL(fileURLWithPath: "/tmp/bridge-refresh-admission"),
            paths: paths,
            timestamp: .now,
            batchSeq: batchSequence
        )
    }

    func currentCommittedReviewPublication() throws -> BridgeReviewCommittedPublication {
        try #require(
            controller.reviewPublicationCoordinator.committedPublicationForReplay(
                productAdmission: productAdmission
            )
        )
    }

    func consumeNextMetadataFrame() async throws -> BridgeProductMetadataFrame {
        guard
            let queuedFrame = await consumeNextBridgeProductProducerFrame(
                for: metadataProducerLease,
                from: productInstallation.session,
                productAdmission: productAdmission
            )
        else {
            throw RefreshAdmissionIntegrationError.expectedMetadataFrame
        }
        let decoder = try BridgeProductMetadataFrameDecoder()
        return try #require(try decoder.append(queuedFrame.data).first)
    }

    func consumeQueuedMetadataFrames() async throws -> [BridgeProductMetadataFrame] {
        var frames: [BridgeProductMetadataFrame] = []
        while await productInstallation.session.producerSnapshot().queuedFrameCount > 0 {
            frames.append(try await consumeNextMetadataFrame())
        }
        return frames
    }

    func openFileMetadataSubscription() async throws {
        let request = try refreshAdmissionFileSubscriptionOpenRequest(
            installation: productInstallation
        )
        let dispatcher = BridgeProductSchemeControlDispatcher(
            session: productInstallation.session,
            provider: productProvider,
            productAdmission: productAdmission
        )
        let capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(
            productInstallation.capabilityBytes
        )
        guard
            case .response(let responseBytes) = try await dispatcher.dispatch(
                exactRequestBytes: try JSONEncoder().encode(request),
                presentedCapability: capabilityHeader
            ),
            case .subscriptionOpenAccepted = try BridgeProductStrictJSON.decode(
                BridgeProductControlResponse.self,
                from: responseBytes
            )
        else {
            throw RefreshAdmissionIntegrationError.fileSubscriptionDidNotOpen
        }
        guard case .subscriptionAccepted = try await consumeNextMetadataFrame() else {
            throw RefreshAdmissionIntegrationError.expectedSubscriptionAcceptedFrame
        }
    }

    func openReviewMetadataSubscription() async throws {
        let request = try refreshAdmissionReviewSubscriptionOpenRequest(
            installation: productInstallation
        )
        let dispatcher = BridgeProductSchemeControlDispatcher(
            session: productInstallation.session,
            provider: productProvider,
            productAdmission: productAdmission
        )
        let capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(
            productInstallation.capabilityBytes
        )
        guard
            case .response(let responseBytes) = try await dispatcher.dispatch(
                exactRequestBytes: try JSONEncoder().encode(request),
                presentedCapability: capabilityHeader
            ),
            case .subscriptionOpenAccepted = try BridgeProductStrictJSON.decode(
                BridgeProductControlResponse.self,
                from: responseBytes
            )
        else {
            throw RefreshAdmissionIntegrationError.reviewSubscriptionDidNotOpen
        }
        guard case .subscriptionAccepted = try await consumeNextMetadataFrame() else {
            throw RefreshAdmissionIntegrationError.expectedSubscriptionAcceptedFrame
        }
    }

    func finish() async {
        _ = await controller.teardown().value
    }
}

@MainActor
func makeRefreshAdmissionIntegrationFixture(
    comparisonGate: BridgeComparisonGate? = nil,
    failsChangesetPublication: Bool = false,
    retryableChangesetFailureCount: Int = 0,
    failsReviewReservation: Bool = false,
    failsReviewDelivery: Bool = false,
    fileChangesetPublicationGate: RefreshAdmissionCancellationIgnoringProducerGate? = nil,
    fileMetadataProducerGate: RefreshAdmissionCancellationIgnoringProducerGate? = nil,
    reviewMetadataReservationGate: RefreshAdmissionReviewReservationGate? = nil,
    initialContributionTarget: WorkspaceReviewContributionTarget? = nil,
    contributionTargetCommit:
        (@MainActor @Sendable (WorkspaceReviewContributionTarget) -> BridgePaneStateMutationResult)? = nil
) async throws -> RefreshAdmissionIntegrationFixture {
    let baseEndpoint = makeBridgeEndpoint(endpointId: "baseline-headMinusOne", kind: .gitRef)
    let headEndpoint = makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree)
    let initialFile = makeBridgeEndpointChangedFile(
        fileId: "initial",
        path: "Sources/App/Initial.swift",
        sizeBytes: 100
    )
    let refreshedFile = makeBridgeEndpointChangedFile(
        fileId: "refreshed",
        path: "Sources/App/Refreshed.swift",
        sizeBytes: 100
    )
    let reviewProvider = makeRefreshAdmissionReviewProvider(
        baseEndpoint: baseEndpoint,
        headEndpoint: headEndpoint,
        initialFile: initialFile,
        initialContributionTarget: initialContributionTarget,
        comparisonGate: comparisonGate
    )
    let fileMetadataSource = RefreshAdmissionTrackingFileMetadataSource(
        failsChangesetPublication: failsChangesetPublication,
        retryableChangesetFailureCount: retryableChangesetFailureCount,
        changesetPublicationGate: fileChangesetPublicationGate,
        metadataProducerGate: fileMetadataProducerGate
    )
    let reviewMetadataSource = RefreshAdmissionGatedReviewMetadataSource(
        failsReservation: failsReviewReservation,
        failsDelivery: failsReviewDelivery,
        reservationGate: reviewMetadataReservationGate
    )
    let refreshWorkAdmission = BridgePaneRefreshWorkAdmissionTestContext.foregroundOnMainActor()
    let productProvider = BridgePaneProductSchemeProvider(
        fileMetadataSource: fileMetadataSource,
        reviewMetadataSource: reviewMetadataSource,
        reviewContentSource: BridgeUnavailablePaneProductReviewContentSource(),
        markReviewItemViewed: { _, _ in },
        refreshWorkAdmissionSource: refreshWorkAdmission.source
    )
    let paneId = UUIDv7.generate()
    let productAdmissionGate = BridgeProductAdmissionGate()
    let installation = BridgePaneController.makeInitialProductSessionInstallation(
        paneSessionId: paneId.uuidString,
        provider: productProvider,
        productAdmissionGate: productAdmissionGate
    )
    let controller = BridgePaneController(
        paneId: paneId,
        state: BridgePaneState(
            panelKind: .diffViewer,
            source: .workspace(
                rootPath: "/tmp/bridge-refresh-admission",
                baseline: initialContributionTarget.map(WorkspaceBaseline.init(contributionTarget:))
                    ?? .staged)
        ),
        appRootURL: testBridgeAppRootURL(),
        metadata: PaneMetadata(
            contentType: .diff,
            title: "Refresh admission",
            facets: PaneContextFacets(
                repoId: headEndpoint.repoId,
                worktreeId: headEndpoint.worktreeId,
                cwd: URL(fileURLWithPath: "/tmp/bridge-refresh-admission")
            )
        ),
        reviewSourceProvider: reviewProvider,
        initialPaneActivity: .dormant,
        productSessionDependencies: BridgePaneProductSessionDependencies(
            installation: installation,
            owner: BridgePaneController.makeProductSessionOwner(
                paneSessionId: paneId.uuidString,
                provider: productProvider,
                productAdmissionGate: productAdmissionGate,
                activeInstallation: installation
            ),
            productProvider: productProvider
        ),
        contributionTargetCommit: contributionTargetCommit
    )
    let productAdmission = try #require(productAdmissionGate.acquire())
    let metadataProducerLease = try await installRefreshAdmissionMetadataProducer(
        installation: installation,
        productProvider: productProvider,
        productAdmission: productAdmission
    )
    return RefreshAdmissionIntegrationFixture(
        baseEndpoint: baseEndpoint,
        headEndpoint: headEndpoint,
        refreshedComparison: BridgeEndpointComparison(
            baseEndpoint: baseEndpoint,
            headEndpoint: headEndpoint,
            changedFiles: [refreshedFile]
        ),
        reviewProvider: reviewProvider,
        fileMetadataSource: fileMetadataSource,
        metadataProducerLease: metadataProducerLease,
        productInstallation: installation,
        productAdmission: productAdmission,
        productProvider: productProvider,
        controller: controller
    )
}

private func makeRefreshAdmissionReviewProvider(
    baseEndpoint: BridgeSourceEndpoint,
    headEndpoint: BridgeSourceEndpoint,
    initialFile: BridgeEndpointChangedFile,
    initialContributionTarget: WorkspaceReviewContributionTarget?,
    comparisonGate: BridgeComparisonGate?
) -> BridgeReviewSourceProviderFake {
    let comparison = BridgeEndpointComparison(
        baseEndpoint: baseEndpoint,
        headEndpoint: headEndpoint,
        changedFiles: [initialFile]
    )
    let contributionCapture = initialContributionTarget.map { _ in
        BridgeContributionComparisonCapture(
            resolvedTargetOID: "resolved-target-oid",
            reviewedHeadOID: "reviewed-head-oid",
            baseRole: .commonCommit,
            baseOID: "contribution-base-oid",
            comparison: comparison
        )
    }
    return BridgeReviewSourceProviderFake(
        comparison: comparison,
        contentByHandleId: [:],
        contributionCapture: contributionCapture,
        comparisonGate: comparisonGate
    )
}
