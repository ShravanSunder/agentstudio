import Foundation
import Observation
import Testing

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite("Bridge product Review intake lock order", .serialized)
    struct BridgeProductReviewIntakeLockOrderTests {
        init() {
            installTestAtomRegistryIfNeeded()
        }

        @Test("committed Review intake releases product admission before foreground scheduling")
        func committedReviewIntakeUsesForegroundThenProductLockOrder() async throws {
            // Arrange
            let paneId = UUIDv7.generate()
            let baseEndpoint = makeBridgeEndpoint(
                endpointId: "review-intake-lock-order-base",
                kind: .gitRef
            )
            let headEndpoint = makeBridgeEndpoint(
                endpointId: "review-intake-lock-order-head",
                kind: .workingTree
            )
            let reviewSourceProvider = BridgeReviewSourceProviderFake(
                comparison: BridgeEndpointComparison(
                    baseEndpoint: baseEndpoint,
                    headEndpoint: headEndpoint,
                    changedFiles: []
                ),
                contentByHandleId: [:]
            )
            let controller = BridgePaneController(
                paneId: paneId,
                state: BridgePaneState(
                    panelKind: .diffViewer,
                    source: .workspace(rootPath: "Sources", baseline: .headMinusOne)
                ),
                metadata: PaneMetadata(
                    paneId: PaneId(existingUUID: paneId),
                    contentType: .diff,
                    launchDirectory: URL(fileURLWithPath: "Sources"),
                    title: "Review Intake Lock Order",
                    facets: PaneContextFacets(
                        repoId: headEndpoint.repoId,
                        worktreeId: headEndpoint.worktreeId,
                        worktreeName: "review-intake-lock-order",
                        cwd: URL(fileURLWithPath: "Sources")
                    )
                ),
                reviewSourceProvider: reviewSourceProvider,
                initialPaneActivity: .foreground
            )
            defer { controller.teardown() }
            let productAdmission = try #require(controller.productAdmissionGate.acquire())
            let foregroundWorkAdmission = try #require(
                controller.refreshAdmissionCoordinator.acquireForegroundWork()
            )
            controller.activeViewerModeSignalState = BridgeActiveViewerModeSignalState(
                sessionId: "review-intake-lock-order",
                lastSequence: 1,
                acceptedSignal: BridgeActiveViewerModeAcceptedSignal(
                    mode: .review,
                    activeSource: BridgeActiveViewerSource(
                        protocolId: .review,
                        streamId: "review:prior-stream",
                        generation: 1
                    ),
                    sequenceFloor: 1
                )
            )

            let foregroundMutationEntered = DispatchSemaphore(value: 0)
            let beginProductMutation = DispatchSemaphore(value: 0)
            let productMutationStarted = DispatchSemaphore(value: 0)
            let productMutationFinished = DispatchSemaphore(value: 0)
            let foregroundMutationFinished = DispatchSemaphore(value: 0)
            let lockOrderRecorder = ReviewIntakeLockOrderRecorder()
            DispatchQueue.global(qos: .userInitiated).async {
                _ = foregroundWorkAdmission.withValidAdmission {
                    foregroundMutationEntered.signal()
                    beginProductMutation.wait()
                    DispatchQueue.global(qos: .userInitiated).async {
                        productMutationStarted.signal()
                        let mutationWasAdmitted = productAdmission.withValidAdmission { true } == true
                        lockOrderRecorder.recordProductMutationAdmission(mutationWasAdmitted)
                        productMutationFinished.signal()
                    }
                    productMutationStarted.wait()
                    let productMutationCompletedBeforeForegroundRelease =
                        productMutationFinished.wait(timeout: .now() + .seconds(2)) == .success
                    lockOrderRecorder.recordCompletionBeforeForegroundRelease(
                        productMutationCompletedBeforeForegroundRelease
                    )
                }
                foregroundMutationFinished.signal()
            }
            #expect(waitForReviewIntakeSemaphore(foregroundMutationEntered))
            withObservationTracking {
                _ = controller.activeViewerModeSignalState
            } onChange: {
                beginProductMutation.signal()
            }

            // Act
            await controller.handleCommittedProductReviewIntakeReady(
                BridgeProductReviewIntakeReadyRequest(reason: nil, streamId: nil),
                productAdmission: productAdmission
            )
            let foregroundMutationDidFinish = waitForReviewIntakeSemaphore(
                foregroundMutationFinished
            )

            // Assert
            #expect(foregroundMutationDidFinish)
            #expect(lockOrderRecorder.productMutationWasAdmitted)
            #expect(lockOrderRecorder.productMutationCompletedBeforeForegroundRelease)
        }
    }
}

private func waitForReviewIntakeSemaphore(_ semaphore: DispatchSemaphore) -> Bool {
    semaphore.wait(timeout: .now() + .seconds(2)) == .success
}

private final class ReviewIntakeLockOrderRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedProductMutationWasAdmitted = false
    private var storedProductMutationCompletedBeforeForegroundRelease = false

    var productMutationWasAdmitted: Bool {
        lock.withLock { storedProductMutationWasAdmitted }
    }

    var productMutationCompletedBeforeForegroundRelease: Bool {
        lock.withLock { storedProductMutationCompletedBeforeForegroundRelease }
    }

    func recordProductMutationAdmission(_ wasAdmitted: Bool) {
        lock.withLock { storedProductMutationWasAdmitted = wasAdmitted }
    }

    func recordCompletionBeforeForegroundRelease(_ didComplete: Bool) {
        lock.withLock { storedProductMutationCompletedBeforeForegroundRelease = didComplete }
    }
}
