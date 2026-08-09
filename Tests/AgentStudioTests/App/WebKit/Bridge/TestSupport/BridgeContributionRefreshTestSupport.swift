import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
struct ContributionRefreshFixture {
    let controller: BridgePaneController
    let provider: BridgeReviewSourceProviderFake
    let paneId: UUID
    let repoId: UUID
    let worktreeId: UUID
    let symbolicBaseEndpoint: BridgeSourceEndpoint
    let workingTreeEndpoint: BridgeSourceEndpoint
    let successorCapture: BridgeContributionComparisonCapture
}

@MainActor
func makeContributionRefreshFixture() -> ContributionRefreshFixture {
    let symbolicBaseEndpoint = makeBridgeEndpoint(endpointId: "baseline-ref-target", kind: .gitRef)
    let workingTreeEndpoint = makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree)
    let initialCapture = BridgeContributionComparisonCapture(
        resolvedTargetOID: "target-oid-1",
        reviewedHeadOID: "head-oid-1",
        contributionBaseOID: "base-oid-1",
        comparison: BridgeEndpointComparison(
            baseEndpoint: symbolicBaseEndpoint,
            headEndpoint: workingTreeEndpoint,
            changedFiles: [
                makeBridgeEndpointChangedFile(
                    fileId: "initial",
                    path: "Sources/App/Initial.swift",
                    sizeBytes: 100
                )
            ]
        )
    )
    let successorCapture = BridgeContributionComparisonCapture(
        resolvedTargetOID: "target-oid-2",
        reviewedHeadOID: "head-oid-2",
        contributionBaseOID: "base-oid-2",
        comparison: BridgeEndpointComparison(
            baseEndpoint: symbolicBaseEndpoint,
            headEndpoint: workingTreeEndpoint,
            changedFiles: [
                makeBridgeEndpointChangedFile(
                    fileId: "successor",
                    path: "Sources/App/Successor.swift",
                    sizeBytes: 100
                )
            ]
        )
    )
    let provider = BridgeReviewSourceProviderFake(
        comparison: initialCapture.comparison,
        contentByHandleId: [:],
        contributionCapture: initialCapture
    )
    let paneId = UUIDv7.generate()
    let controller = BridgePaneController(
        paneId: paneId,
        state: BridgePaneState(
            panelKind: .diffViewer,
            source: .workspace(
                rootPath: "/tmp/contribution-refresh",
                baseline: .ref(name: "target")
            )
        ),
        appRootURL: testBridgeAppRootURL(),
        metadata: PaneMetadata(
            contentType: .diff,
            title: "Contribution refresh",
            facets: PaneContextFacets(
                repoId: symbolicBaseEndpoint.repoId,
                worktreeId: symbolicBaseEndpoint.worktreeId,
                worktreeName: "feature-review",
                cwd: URL(fileURLWithPath: "/tmp/contribution-refresh")
            )
        ),
        reviewSourceProvider: provider,
        initialPaneActivity: .foreground
    )
    return ContributionRefreshFixture(
        controller: controller,
        provider: provider,
        paneId: paneId,
        repoId: symbolicBaseEndpoint.repoId,
        worktreeId: symbolicBaseEndpoint.worktreeId,
        symbolicBaseEndpoint: symbolicBaseEndpoint,
        workingTreeEndpoint: workingTreeEndpoint,
        successorCapture: successorCapture
    )
}

@MainActor
func assertStaleContributionCaptureCannotCommit(
    fixture: ContributionRefreshFixture,
    productAdmission: BridgeProductAdmissionContext,
    successor: BridgeReviewCommittedPublication
) async throws {
    let staleCapture = BridgeContributionComparisonCapture(
        resolvedTargetOID: "target-oid-stale",
        reviewedHeadOID: "head-oid-stale",
        contributionBaseOID: "base-oid-stale",
        comparison: BridgeEndpointComparison(
            baseEndpoint: fixture.symbolicBaseEndpoint,
            headEndpoint: fixture.workingTreeEndpoint,
            changedFiles: [
                makeBridgeEndpointChangedFile(
                    fileId: "stale",
                    path: "Sources/App/Stale.swift",
                    sizeBytes: 100
                )
            ]
        )
    )
    let staleCaptureGate = BridgeContributionCaptureGate()
    await fixture.provider.setContributionCapture(staleCapture)
    await fixture.provider.setContributionCaptureGate(staleCaptureGate)
    await fixture.controller.handlePaneFilesystemContextEvent(
        .cwdSubtreeChanged(
            context: PaneFilesystemContext(
                paneId: PaneId(existingUUID: fixture.paneId),
                repoId: fixture.repoId,
                cwd: URL(fileURLWithPath: "/tmp/contribution-refresh"),
                worktreeId: fixture.worktreeId
            ),
            paths: ["Sources/App/Stale.swift"],
            batchSeq: 2
        )
    )
    await staleCaptureGate.waitForStart()
    #expect(fixture.controller.nextReviewGeneration == 3)
    let replacementCaptureGate = BridgeContributionCaptureGate()
    await fixture.provider.setContributionCaptureGate(replacementCaptureGate)
    fixture.controller.nextReviewGeneration = fixture.controller.nextReviewGeneration.next()
    await staleCaptureGate.releaseAll()
    await replacementCaptureGate.waitForStart()

    let publication = try #require(
        fixture.controller.reviewPublicationCoordinator.committedPublicationForReplay(
            productAdmission: productAdmission
        )
    )
    #expect(publication == successor)
    #expect(fixture.controller.paneState.diff.packageMetadata?.orderedItemIds == ["item-successor"])
    #expect(fixture.controller.nextReviewGeneration == 5)
    #expect(
        (await fixture.provider.recordedContributionRequests()).map { $0.reviewGenerationValue }
            == [1, 2, 3, 5]
    )
    #expect(await fixture.provider.recordedComparisonRequestsCount() == 0)
    await replacementCaptureGate.releaseAll()
    await waitForActiveReviewRefreshTaskToFinish(fixture.controller)
}
