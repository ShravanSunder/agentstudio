import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct BridgePaneControllerProductBootstrapDeliveryTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("failed bootstrap delivery revokes exposed authority before retry")
    func failedBootstrapDeliveryRevokesExposedAuthorityBeforeRetry() async throws {
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
        var deliveredInstallations: [BridgeProductSessionInstallation] = []
        let controller = BridgePaneController(
            paneId: paneId,
            state: BridgePaneState(panelKind: .diffViewer, source: .commit(sha: "delivery-failure")),
            productSessionDependencies: BridgePaneProductSessionDependencies(
                installation: initialInstallation,
                owner: owner
            ),
            productSessionBootstrapSink: { _, _, installation, _, _ in
                deliveredInstallations.append(installation)
                if deliveredInstallations.count == 1 {
                    throw BridgeError.encoding("simulated ambiguous delivery failure")
                }
            }
        )

        // Act
        await controller.enqueueProductSessionBootstrapRequest(
            requestId: "failed-initial-bootstrap",
            reason: .initial
        )
        let staleCapability = try BridgeProductCapabilityHeaderEncoding.encode(
            initialInstallation.capabilityBytes
        )
        let staleReply = try await collectBridgeProductSchemeReply(
            adapter: initialInstallation.productAdapter,
            request: bridgeProductSchemeRequest(
                route: BridgeProductWireContract.commandRoute,
                capability: staleCapability,
                body: Data("{}".utf8)
            )
        )
        await controller.enqueueProductSessionBootstrapRequest(
            requestId: "retry-initial-bootstrap",
            reason: .initial
        )

        // Assert
        #expect(staleReply.response?.statusCode == 403)
        #expect(deliveredInstallations.count == 2)
        let replacementInstallation = try #require(deliveredInstallations.last)
        #expect(
            replacementInstallation.bootstrap.workerInstanceId
                != initialInstallation.bootstrap.workerInstanceId
        )
        #expect(replacementInstallation.capabilityBytes != initialInstallation.capabilityBytes)
        #expect(await controller.teardown().value)
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
        let teardownTask = controller.teardown()
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
}

private actor BridgeProductBootstrapDeliverySuspension {
    private var deliveryIsSuspended = false
    private var deliverySuspendedWaiters: [CheckedContinuation<Void, Never>] = []
    private var deliveryResumeContinuation: CheckedContinuation<Void, Never>?

    func suspendDelivery() async {
        deliveryIsSuspended = true
        let waiters = deliverySuspendedWaiters
        deliverySuspendedWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        await withCheckedContinuation { continuation in
            deliveryResumeContinuation = continuation
        }
    }

    func waitUntilDeliveryIsSuspended() async {
        guard !deliveryIsSuspended else { return }
        await withCheckedContinuation { continuation in
            deliverySuspendedWaiters.append(continuation)
        }
    }

    func resumeDelivery() {
        deliveryResumeContinuation?.resume()
        deliveryResumeContinuation = nil
    }
}
