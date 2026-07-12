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
        let initialInstallation = BridgePaneController.makeInitialProductSessionInstallation(
            paneSessionId: paneId.uuidString,
            provider: provider
        )
        let owner = BridgePaneController.makeProductSessionOwner(
            paneSessionId: paneId.uuidString,
            provider: provider,
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
            productSessionBootstrapSink: { _, _, installation, _ in
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
}
