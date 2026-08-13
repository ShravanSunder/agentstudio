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
    struct BridgeReviewComparisonPresentationTests {
        init() {
            installTestCoreAtomsIfNeeded()
        }

        @Test("committed comparison update adopts the canonical workspace target")
        func committedComparisonUpdateAdoptsCanonicalWorkspaceTarget() async throws {
            let target = WorkspaceReviewContributionTarget.branch(name: "stack/base")
            let canonicalState = BridgePaneState(
                panelKind: .diffViewer,
                source: .workspace(
                    rootPath: "/tmp/worktree",
                    baseline: WorkspaceBaseline(contributionTarget: target)
                )
            )
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(
                    panelKind: .diffViewer,
                    source: .workspace(rootPath: "/tmp/worktree", baseline: .branch(name: "main"))
                ),
                appRootURL: testBridgeAppRootURL(),
                initialPaneActivity: .dormant,
                contributionTargetCommit: { _ in .applied(canonicalState) }
            )
            defer { controller.teardown() }
            let productAdmission = try #require(controller.productAdmissionGate.acquire())

            let didAdopt = await controller.handleCommittedProductReviewComparisonUpdate(
                BridgeProductReviewComparisonUpdateRequest(target: target),
                productAdmission: productAdmission
            )

            #expect(controller.bridgePaneState == canonicalState)
            #expect(didAdopt)
            #expect(controller.productAdmissionGate.diagnosticSnapshot.isOpen)
        }

        @Test("noncanonical committed comparison result closes pane admission")
        func noncanonicalCommittedComparisonResultClosesPaneAdmission() async throws {
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(
                    panelKind: .diffViewer,
                    source: .workspace(rootPath: "/tmp/worktree", baseline: .branch(name: "main"))
                ),
                appRootURL: testBridgeAppRootURL(),
                initialPaneActivity: .dormant,
                contributionTargetCommit: { _ in
                    .unchanged(
                        BridgePaneState(
                            panelKind: .diffViewer,
                            source: .workspace(
                                rootPath: "/tmp/worktree",
                                baseline: .branch(name: "different-target")
                            )
                        )
                    )
                }
            )
            defer { controller.teardown() }
            let productAdmission = try #require(controller.productAdmissionGate.acquire())

            let didAdopt = await controller.handleCommittedProductReviewComparisonUpdate(
                BridgeProductReviewComparisonUpdateRequest(target: .branch(name: "stack/base")),
                productAdmission: productAdmission
            )

            #expect(!didAdopt)
            #expect(!controller.productAdmissionGate.diagnosticSnapshot.isOpen)
        }

        @Test("contribution load publishes pending then exact settled snapshot identity")
        func contributionLoadPublishesPendingThenSettledSnapshotIdentity() async throws {
            let target = WorkspaceReviewContributionTarget.branch(name: "stack/base")
            let comparison = makeComparison()
            let provider = makeContributionProvider(comparison: comparison)
            let controller = makeController(
                target: target,
                comparison: comparison,
                provider: provider
            )
            defer { controller.teardown() }
            let initialPresentation = controller.refreshAdmissionCoordinator.productPresentationSnapshot

            let result = await controller.loadInitialReviewPackageIfPossible(correlationId: nil)
            let settledPresentation = controller.refreshAdmissionCoordinator.productPresentationSnapshot

            guard case .success = result else {
                Issue.record("Expected contribution load to succeed")
                return
            }
            #expect(initialPresentation.reviewComparison?.activeTarget == target)
            #expect(initialPresentation.reviewComparison?.attempt == .pending(reviewGeneration: 0))
            #expect(initialPresentation.reviewComparison?.displayedSnapshot == .absent)
            let package = try #require(controller.paneState.diff.packageMetadata)
            #expect(
                settledPresentation.reviewComparison
                    == BridgePaneReviewComparisonPresentation(
                        activeTarget: target,
                        attempt: .settled(reviewGeneration: package.reviewGeneration.rawValue),
                        displayedSnapshot: .current(
                            BridgePaneReviewDisplayedSnapshotIdentity(
                                packageId: package.packageId,
                                reviewGeneration: package.reviewGeneration.rawValue,
                                revision: package.revision
                            )
                        ),
                    )
            )
        }

        @Test("target update keeps predecessor stale and schedules one successor build")
        func targetUpdateKeepsPredecessorStaleAndSchedulesOneSuccessorBuild() async throws {
            let initialTarget = WorkspaceReviewContributionTarget.branch(name: "main")
            let successorTarget = WorkspaceReviewContributionTarget.branch(name: "stack/base")
            let comparison = makeComparison()
            let provider = makeContributionProvider(comparison: comparison)
            let canonicalSuccessorState = BridgePaneState(
                panelKind: .diffViewer,
                source: .workspace(
                    rootPath: "/tmp/worktree",
                    baseline: WorkspaceBaseline(contributionTarget: successorTarget)
                )
            )
            let controller = makeController(
                target: initialTarget,
                comparison: comparison,
                provider: provider,
                contributionTargetCommit: { _ in .applied(canonicalSuccessorState) }
            )
            defer { controller.teardown() }
            guard case .success = await controller.loadInitialReviewPackageIfPossible(correlationId: nil)
            else {
                Issue.record("Expected predecessor load to succeed")
                return
            }
            let predecessorPackage = try #require(controller.paneState.diff.packageMetadata)
            let predecessorIdentity = BridgePaneReviewDisplayedSnapshotIdentity(
                packageId: predecessorPackage.packageId,
                reviewGeneration: predecessorPackage.reviewGeneration.rawValue,
                revision: predecessorPackage.revision
            )
            let productAdmission = try #require(controller.productAdmissionGate.acquire())

            let didAdopt = await controller.handleCommittedProductReviewComparisonUpdate(
                BridgeProductReviewComparisonUpdateRequest(target: successorTarget),
                productAdmission: productAdmission
            )
            let pendingPresentation = controller.refreshAdmissionCoordinator.productPresentationSnapshot
            await waitForActiveReviewRefreshTaskToFinish(controller)
            let settledPresentation = controller.refreshAdmissionCoordinator.productPresentationSnapshot

            #expect(didAdopt)
            #expect(pendingPresentation.reviewComparison?.activeTarget == successorTarget)
            #expect(pendingPresentation.reviewComparison?.displayedSnapshot == .stale(predecessorIdentity))
            guard case .current(let successorIdentity) = settledPresentation.reviewComparison?.displayedSnapshot
            else {
                Issue.record("Expected current successor snapshot identity")
                return
            }
            #expect(successorIdentity != predecessorIdentity)
            #expect(await provider.recordedContributionRequests().count == 2)
            #expect(controller.pendingComparisonReviewGeneration == nil)
            #expect(controller.pendingReviewPackageBuildReasons.isEmpty)
        }

        @Test("filesystem reload preserves settled comparison presentation")
        func filesystemReloadPreservesSettledComparisonPresentation() async throws {
            let target = WorkspaceReviewContributionTarget.branch(name: "main")
            let comparison = makeComparison()
            let provider = makeContributionProvider(comparison: comparison)
            let controller = makeController(
                target: target,
                comparison: comparison,
                provider: provider
            )
            defer { controller.teardown() }
            guard case .success = await controller.loadInitialReviewPackageIfPossible(correlationId: nil)
            else {
                Issue.record("Expected initial contribution load to succeed")
                return
            }
            let settledBeforeRefresh = try #require(
                controller.refreshAdmissionCoordinator.productPresentationSnapshot.reviewComparison
            )
            let contributionCaptureGate = BridgeContributionCaptureGate()
            await provider.setContributionCaptureGate(contributionCaptureGate)

            controller.scheduleReviewPackageReloadForProductResync(reason: .filesystemRefresh)
            await contributionCaptureGate.waitForStart()
            let presentationDuringRefresh = controller.refreshAdmissionCoordinator
                .productPresentationSnapshot.reviewComparison
            await contributionCaptureGate.releaseAll()
            await waitForActiveReviewRefreshTaskToFinish(controller)

            #expect(presentationDuringRefresh == settledBeforeRefresh)
            #expect(
                controller.refreshAdmissionCoordinator.productPresentationSnapshot.reviewComparison?
                    .attempt == settledBeforeRefresh.attempt
            )
        }

        @Test("successor comparison clears and refreshes repository default identity")
        func successorComparisonClearsAndRefreshesRepositoryDefaultIdentity() async throws {
            // Arrange
            let initialTarget = WorkspaceReviewContributionTarget.branch(name: "main")
            let successorTarget = WorkspaceReviewContributionTarget.branch(name: "stack/base")
            let initialDefaultTarget = BridgeReviewComparisonDefaultTargetIdentity(
                remoteName: "origin",
                branchName: "main"
            )
            let successorDefaultTarget = BridgeReviewComparisonDefaultTargetIdentity(
                remoteName: "upstream",
                branchName: "trunk"
            )
            let comparison = makeComparison()
            let provider = makeContributionProvider(
                comparison: comparison,
                repositoryDefaultTarget: initialDefaultTarget
            )
            let canonicalSuccessorState = BridgePaneState(
                panelKind: .diffViewer,
                source: .workspace(
                    rootPath: "/tmp/worktree",
                    baseline: WorkspaceBaseline(contributionTarget: successorTarget)
                )
            )
            let controller = makeController(
                target: initialTarget,
                comparison: comparison,
                provider: provider,
                contributionTargetCommit: { _ in .applied(canonicalSuccessorState) }
            )
            defer { controller.teardown() }
            guard case .success = await controller.loadInitialReviewPackageIfPossible(correlationId: nil)
            else {
                Issue.record("Expected initial contribution load to succeed")
                return
            }
            #expect(
                controller.refreshAdmissionCoordinator.productPresentationSnapshot.reviewComparison?
                    .repositoryDefaultTarget == initialDefaultTarget
            )
            let defaultTargetGate = BridgeContributionCaptureGate()
            await provider.setRepositoryDefaultTarget(successorDefaultTarget)
            await provider.setDefaultTargetGate(defaultTargetGate)
            let productAdmission = try #require(controller.productAdmissionGate.acquire())

            // Act
            let didAdopt = await controller.handleCommittedProductReviewComparisonUpdate(
                BridgeProductReviewComparisonUpdateRequest(target: successorTarget),
                productAdmission: productAdmission
            )
            await defaultTargetGate.waitForStart()
            let pendingPresentation =
                controller.refreshAdmissionCoordinator.productPresentationSnapshot
            await defaultTargetGate.releaseAll()
            await waitForActiveReviewRefreshTaskToFinish(controller)
            let settledPresentation =
                controller.refreshAdmissionCoordinator.productPresentationSnapshot

            // Assert
            #expect(didAdopt)
            #expect(
                pendingPresentation.reviewComparison?.repositoryDefaultTarget
                    == initialDefaultTarget
            )
            #expect(
                settledPresentation.reviewComparison?.repositoryDefaultTarget
                    == successorDefaultTarget
            )
            #expect(await provider.recordedDefaultTargetReadCount() == 2)
        }

        private func makeComparison() -> BridgeEndpointComparison {
            BridgeEndpointComparison(
                baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
                headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
                changedFiles: []
            )
        }

        private func makeContributionProvider(
            comparison: BridgeEndpointComparison,
            repositoryDefaultTarget: BridgeReviewComparisonDefaultTargetIdentity? = nil
        ) -> BridgeReviewSourceProviderFake {
            BridgeReviewSourceProviderFake(
                comparison: comparison,
                contentByHandleId: [:],
                contributionCapture: BridgeContributionComparisonCapture(
                    resolvedTargetOID: "resolved-target-oid",
                    reviewedHeadOID: "reviewed-head-oid",
                    baseRole: .commonCommit,
                    baseOID: "contribution-base-oid",
                    comparison: comparison
                ),
                repositoryDefaultTarget: repositoryDefaultTarget
            )
        }

        private func makeController(
            target: WorkspaceReviewContributionTarget,
            comparison: BridgeEndpointComparison,
            provider: BridgeReviewSourceProviderFake,
            contributionTargetCommit:
                (@MainActor @Sendable (WorkspaceReviewContributionTarget) -> BridgePaneStateMutationResult)? = nil
        ) -> BridgePaneController {
            BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(
                    panelKind: .diffViewer,
                    source: .workspace(
                        rootPath: "/tmp/worktree",
                        baseline: WorkspaceBaseline(contributionTarget: target)
                    )
                ),
                appRootURL: testBridgeAppRootURL(),
                metadata: PaneMetadata(
                    contentType: .diff,
                    title: "Bridge Review",
                    facets: PaneContextFacets(worktreeId: comparison.headEndpoint.worktreeId)
                ),
                reviewSourceProvider: provider,
                initialPaneActivity: .foreground,
                contributionTargetCommit: contributionTargetCommit
            )
        }
    }
}
