import AgentStudioTestHarness
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
    struct BridgePaneControllerBootstrapSupersessionTests {
        init() { installTestCoreAtomsIfNeeded() }

        @Test("reload suppresses an older replacement held before its tail and installs the new initial")
        func reloadSupersedesHeldReplacement() async throws {
            let delivery = BootstrapSupersessionDeliveryLedger()
            let controller = makeSupersessionController(delivery: delivery)
            await controller.enqueueProductSessionBootstrapRequest(requestId: "old-initial", reason: .initial)
            let first = try #require(await controller.productSessionOwner.activeInstallation)
            let heldTail = HeldStep<Void>("old-document replacement bootstrap tail")
            let tail = Task { try? await heldTail.arrive(()) }
            controller.productSessionBootstrapTransitionTail = Task { _ = await tail.value }
            try await heldTail.firstArrival()
            let handler = BridgeReadyMessageHandler()
            controller.configureReadyMessageHandler(handler)

            let old = try #require(
                handler.receiveValidatedBootstrapMessage(
                    .productSessionBootstrap(requestId: "old-replacement", reason: .workerReplacement)))
            #expect(controller.reloadWebView())
            let current = try #require(
                handler.receiveValidatedBootstrapMessage(
                    .productSessionBootstrap(requestId: "current-initial", reason: .initial)))
            #expect(
                controller.productSessionOwner.installationFenceProjection.snapshot.installation
                    == first.installationFence)
            heldTail.release()
            await tail.value
            await old.value
            await current.value
            _ = await controller.surfaceSelectionTransitionTail?.value

            #expect(delivery.requestIds == ["old-initial", "current-initial"])
            #expect(delivery.failures.isEmpty)
            let currentInstallation = try #require(await controller.productSessionOwner.activeInstallation)
            #expect(currentInstallation.bootstrap.workerInstanceId != first.bootstrap.workerInstanceId)
            #expect(currentInstallation.productAdapter.acquireAdmission()?.withValidAdmission { true } == true)
            #expect(controller.paneState.connection.health != .error)
            #expect(await controller.beginTeardown().value)
        }

        @Test("same-document replacement supersedes queued initial with one successful delivery")
        func replacementSupersedesInitialInSameDocument() async throws {
            let delivery = BootstrapSupersessionDeliveryLedger()
            let controller = makeSupersessionController(delivery: delivery)
            let first = try #require(await controller.productSessionOwner.activeInstallation)
            let heldTail = HeldStep<Void>("same-document bootstrap tail")
            let tail = Task { try? await heldTail.arrive(()) }
            controller.productSessionBootstrapTransitionTail = Task { _ = await tail.value }
            try await heldTail.firstArrival()
            let handler = BridgeReadyMessageHandler()
            controller.configureReadyMessageHandler(handler)
            let initial = try #require(
                handler.receiveValidatedBootstrapMessage(
                    .productSessionBootstrap(requestId: "superseded-initial", reason: .initial)))
            let replacement = try #require(
                handler.receiveValidatedBootstrapMessage(
                    .productSessionBootstrap(requestId: "latest-replacement", reason: .workerReplacement)))
            heldTail.release()
            await tail.value
            await initial.value
            await replacement.value

            #expect(delivery.requestIds == ["latest-replacement"])
            #expect(delivery.failures.isEmpty)
            #expect(
                await controller.productSessionOwner.activeInstallation?.bootstrap.workerInstanceId
                    != first.bootstrap.workerInstanceId)
            #expect(await controller.beginTeardown().value)
        }

        @Test("reload during owner activation suppresses its result and lets the new page retry its stale predecessor")
        func reloadDuringOwnerActivationUsesBoundedFailureResult() async throws {
            let revocation = HeldStep<String>("old bootstrap activation revoking its predecessor")
            let provider = BridgePaneProductSessionProviderGate(workerRevocation: revocation)
            let paneId = UUIDv7.generate()
            let paneGate = BridgeProductAdmissionGate()
            let first = BridgePaneController.makeInitialProductSessionInstallation(
                paneSessionId: paneId.uuidString, provider: provider, productAdmissionGate: paneGate)
            let owner = BridgePaneController.makeProductSessionOwner(
                paneSessionId: paneId.uuidString, provider: provider, productAdmissionGate: paneGate,
                activeInstallation: first)
            let delivery = BootstrapSupersessionDeliveryLedger()
            let controller = makeSupersessionController(
                delivery: delivery, paneId: paneId,
                dependencies: .init(installation: first, owner: owner))
            await controller.enqueueProductSessionBootstrapRequest(requestId: "old-initial", reason: .initial)
            let handler = BridgeReadyMessageHandler()
            controller.configureReadyMessageHandler(handler)
            let old = try #require(
                handler.receiveValidatedBootstrapMessage(
                    .productSessionBootstrap(requestId: "in-flight-replacement", reason: .workerReplacement)))
            #expect(try await revocation.firstArrival() == first.bootstrap.workerInstanceId)
            #expect(controller.reloadWebView())
            let current = try #require(
                handler.receiveValidatedBootstrapMessage(
                    .productSessionBootstrap(requestId: "current-initial", reason: .initial)))
            revocation.release()
            await old.value
            await current.value
            #expect(delivery.requestIds == ["old-initial"])
            #expect(delivery.failures == [.init(requestId: "current-initial", reason: .activationFailed)])
            #expect(controller.paneState.connection.health != .error)
            let retry = try #require(
                handler.receiveValidatedBootstrapMessage(
                    .productSessionBootstrap(requestId: "current-bounded-retry", reason: .workerReplacement)))
            await retry.value
            #expect(delivery.requestIds == ["old-initial", "current-bounded-retry"])
            #expect(await owner.activeInstallation?.productAdapter.acquireAdmission() != nil)
            #expect(await controller.beginTeardown().value)
        }

        @Test("obsolete delivery failure cannot retire a newer installation or clear its accepted selection")
        func obsoleteActivatedRequestKeepsNewerInstallationAndBinding() async throws {
            let delivery = BootstrapSupersessionDeliveryLedger()
            let heldDelivery = HeldStep<Void>("old activated candidate bootstrap delivery")
            let controller = makeSupersessionController(delivery: delivery, heldDelivery: heldDelivery)
            await controller.enqueueProductSessionBootstrapRequest(requestId: "old-initial", reason: .initial)
            let first = try #require(await controller.productSessionOwner.activeInstallation)
            _ = try installAcceptedSelection(controller: controller, installation: first)
            let heldSelection = HeldStep<Void>("obsolete bootstrap retained-selection replay")
            let selectionTail = Task { try? await heldSelection.arrive(()) }
            controller.surfaceSelectionTransitionTail = Task {
                _ = await selectionTail.value
                return true
            }
            try await heldSelection.firstArrival()
            let handler = BridgeReadyMessageHandler()
            controller.configureReadyMessageHandler(handler)
            let old = try #require(
                handler.receiveValidatedBootstrapMessage(
                    .productSessionBootstrap(requestId: "held-activated-replacement", reason: .workerReplacement)))
            try await heldDelivery.firstArrival()
            let obsolete = try #require(await controller.productSessionOwner.activeInstallation)
            #expect(controller.reloadWebView())
            let current = try #require(
                handler.receiveValidatedBootstrapMessage(
                    .productSessionBootstrap(requestId: "current-initial", reason: .initial)))
            // A different admitted owner transition wins while the old result is held.
            let pane = try #require(controller.productAdmissionGate.acquire())
            let newer = try await controller.productSessionOwner.prepareCandidate(productAdmission: pane)
            #expect(
                await controller.productSessionOwner.activatePreparedCandidate(newer, productAdmission: pane)
                    == .activated)
            let binding = try installAcceptedSelection(controller: controller, installation: newer)
            let before = controller.surfaceSelectionAuthority.diagnosticSnapshot
            heldDelivery.fail(BridgeError.encoding("obsolete delivery failed after reload"))
            await old.value
            await current.value
            heldSelection.release()
            await selectionTail.value
            _ = await controller.surfaceSelectionTransitionTail?.value

            #expect(delivery.requestIds == ["old-initial"])
            #expect(delivery.failures == [.init(requestId: "current-initial", reason: .activationFailed)])
            #expect(await controller.productSessionOwner.activeInstallation?.bootstrap == newer.bootstrap)
            #expect(newer.productAdapter.acquireAdmission()?.withValidAdmission { true } == true)
            #expect(obsolete.productAdapter.acquireAdmission() == nil)
            #expect(controller.surfaceSelectionAuthority.diagnosticSnapshot == before)
            #expect(controller.surfaceSelectionAuthority.diagnosticSnapshot.lastAcceptedRequest == binding)
            #expect(controller.paneState.connection.health != .error)
            #expect(await controller.beginTeardown().value)
        }

        @Test("native reload after the page's exhausted attempt sequence admits a fresh initial bootstrap")
        func nativeReloadRestartsAfterBoundedPageFailures() async throws {
            let delivery = BootstrapSupersessionDeliveryLedger()
            delivery.shouldFailDelivery = true
            let controller = makeSupersessionController(delivery: delivery)
            let handler = BridgeReadyMessageHandler()
            controller.configureReadyMessageHandler(handler)
            let initial = try #require(
                handler.receiveValidatedBootstrapMessage(
                    .productSessionBootstrap(requestId: "exhausted-initial", reason: .initial)))
            await initial.value
            // The page owns this existing four-replacement budget; native answers every request.
            for attempt in 0..<4 {
                let replacement = try #require(
                    handler.receiveValidatedBootstrapMessage(
                        .productSessionBootstrap(
                            requestId: "exhausted-replacement-\(attempt)", reason: .workerReplacement)))
                await replacement.value
            }
            #expect(delivery.failures.count == 5)
            #expect(delivery.requestIds.isEmpty)
            delivery.shouldFailDelivery = false
            #expect(controller.reloadWebView())
            let current = try #require(
                handler.receiveValidatedBootstrapMessage(
                    .productSessionBootstrap(requestId: "fresh-initial-after-native-reload", reason: .initial)))
            await current.value
            #expect(delivery.requestIds == ["fresh-initial-after-native-reload"])
            #expect(delivery.failures.count == 5)
            #expect(await controller.productSessionOwner.activeInstallation?.productAdapter.acquireAdmission() != nil)
            #expect(await controller.beginTeardown().value)
        }

        @Test("normal initial has no extra round trip and healthy replacement invalidates the prior binding")
        func healthyInitialAndReplacementKeepBindingSemantics() async throws {
            let delivery = BootstrapSupersessionDeliveryLedger()
            let controller = makeSupersessionController(delivery: delivery)
            let first = try #require(await controller.productSessionOwner.activeInstallation)
            let original = try installAcceptedSelection(controller: controller, installation: first)
            await controller.enqueueProductSessionBootstrapRequest(requestId: "healthy-initial", reason: .initial)
            #expect(delivery.requestIds == ["healthy-initial"])
            #expect(await controller.productSessionOwner.activeInstallation?.bootstrap == first.bootstrap)
            #expect(controller.surfaceSelectionAuthority.diagnosticSnapshot.lastAcceptedRequest == original)
            await controller.enqueueProductSessionBootstrapRequest(
                requestId: "healthy-replacement", reason: .workerReplacement)
            _ = await controller.surfaceSelectionTransitionTail?.value
            let next = try #require(await controller.productSessionOwner.activeInstallation)
            #expect(delivery.requestIds == ["healthy-initial", "healthy-replacement"])
            #expect(delivery.failures.isEmpty)
            #expect(controller.surfaceSelectionAuthority.diagnosticSnapshot.lastAcceptedRequest == nil)
            #expect(
                controller.surfaceSelectionAuthority.diagnosticSnapshot.currentRequest?.workerInstanceId
                    == next.bootstrap.workerInstanceId)
            #expect(await controller.beginTeardown().value)
        }
    }
}

@MainActor
private final class BootstrapSupersessionDeliveryLedger {
    struct Failure: Equatable {
        let requestId: String
        let reason: BridgeProductSessionBootstrapFailureReason
    }
    var requestIds: [String] = []
    var failures: [Failure] = []
    var shouldFailDelivery = false
}

@MainActor
private func makeSupersessionController(
    delivery: BootstrapSupersessionDeliveryLedger,
    heldDelivery: HeldStep<Void>? = nil,
    paneId: UUID = UUIDv7.generate(),
    dependencies: BridgePaneProductSessionDependencies? = nil
) -> BridgePaneController {
    BridgePaneController(
        paneId: paneId,
        state: BridgePaneState(panelKind: .fileViewer, source: .commit(sha: "rr2-v1-bootstrap")),
        appRootURL: testBridgeAppRootURL(), initialPaneActivity: .foreground,
        productSessionDependencies: dependencies,
        productSessionBootstrapSink: { _, requestId, _, _, admission in
            if delivery.shouldFailDelivery { throw BridgeError.encoding("native bootstrap delivery refused") }
            if requestId == "held-activated-replacement" { try await heldDelivery?.arrive(()) }
            _ = admission.withValidAdmission { delivery.requestIds.append(requestId) }
        },
        productSessionBootstrapFailureSink: { _, requestId, reason, _ in
            delivery.failures.append(.init(requestId: requestId, reason: reason))
        })
}

@MainActor
private func installAcceptedSelection(
    controller: BridgePaneController,
    installation: BridgeProductSessionInstallation
) throws -> BridgePaneSurfaceSelectionRequest {
    _ = controller.surfaceSelectionAuthority.retainIntent(surface: .review)
    let rebound = try controller.surfaceSelectionAuthority.rebindRetainedIntent(
        paneSessionId: installation.bootstrap.paneSessionId,
        workerInstanceId: installation.bootstrap.workerInstanceId)
    let binding = try #require(rebound)
    let disposition = controller.surfaceSelectionAuthority.admitReceipt(
        nativeSelectionRequestId: binding.requestId, mode: .review,
        paneSessionId: binding.paneSessionId, workerInstanceId: binding.workerInstanceId)
    #expect(disposition == .accepted)
    return binding
}
