import Foundation
import Testing

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    struct BridgeTelemetryBootstrapDeliveryTests {
        init() {
            installTestAtomRegistryIfNeeded()
        }

        @Test("telemetry-off bootstrap delivers an explicit unavailable result")
        func telemetryOffBootstrapDeliversExplicitUnavailableResult() async {
            // Arrange
            var deliveredInstallations: [BridgeTelemetrySessionInstallation?] = []
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(panelKind: .diffViewer, source: nil),
                telemetryRuntimePolicy: BridgeTelemetryRuntimePolicy(isDebugBuild: false),
                telemetryScopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web]),
                telemetryRecorder: TelemetryBootstrapRecorderSpy(),
                initialPaneActivity: .foreground,
                telemetrySessionBootstrapSink: { _, _, installation, _ in
                    deliveredInstallations.append(installation)
                }
            )
            defer { controller.teardown() }

            // Act
            await controller.enqueueTelemetrySessionBootstrapRequest(
                requestId: "telemetry-disabled",
                reason: .initial
            )

            // Assert
            #expect(controller.telemetrySessionOwner == nil)
            #expect(deliveredInstallations.count == 1)
            #expect(deliveredInstallations[0] == nil)
        }

        @Test("repeated page bootstrap rotates and revokes the old telemetry session")
        func repeatedPageBootstrapRotatesAndRevokesOldTelemetrySession() async throws {
            // Arrange
            let recorder = TelemetryBootstrapRecorderSpy()
            let initialInstallation = try BridgeTelemetrySessionInstallation.make(
                enabledScopes: [.web],
                endpointURL: "agentstudio://telemetry/batch",
                policy: .live,
                projector: BridgeTelemetryNativeProjector(recorder: recorder).project
            )
            let owner = BridgePaneTelemetrySessionOwner(initialInstallation: initialInstallation)
            var deliveredInstallations: [BridgeTelemetrySessionInstallation?] = []
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(panelKind: .diffViewer, source: nil),
                telemetryScopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web]),
                telemetryRecorder: recorder,
                initialPaneActivity: .foreground,
                telemetrySessionDependencies: BridgePaneTelemetrySessionDependencies(
                    installation: initialInstallation,
                    owner: owner
                ),
                telemetrySessionBootstrapSink: { _, _, installation, _ in
                    deliveredInstallations.append(installation)
                }
            )
            defer { controller.teardown() }

            // Act
            await controller.enqueueTelemetrySessionBootstrapRequest(
                requestId: "telemetry-initial",
                reason: .initial
            )
            await controller.enqueueTelemetrySessionBootstrapRequest(
                requestId: "telemetry-replacement",
                reason: .sidecarReplacement
            )
            let replacement = await owner.installation

            // Assert
            #expect(deliveredInstallations.count == 2)
            #expect(
                deliveredInstallations.compactMap { $0 }.map(\.bootstrap.telemetrySessionId)
                    == [
                        initialInstallation.bootstrap.telemetrySessionId,
                        replacement.bootstrap.telemetrySessionId,
                    ]
            )
            #expect(!(await initialInstallation.session.authorizes(initialInstallation.bootstrap.telemetryCapability)))
            #expect(await replacement.session.authorizes(replacement.bootstrap.telemetryCapability))
            #expect(replacement.bootstrap.telemetrySessionId != initialInstallation.bootstrap.telemetrySessionId)
        }
    }
}

private actor TelemetryBootstrapRecorderSpy: BridgePerformanceTraceRecording {
    func record(sample _: BridgeTelemetrySample, receivedAtUnixNano _: UInt64) async {}

    func recordDrop(
        reason _: BridgeTelemetryDropReason,
        droppedCount _: Int,
        firstRejectedEventName _: String?,
        receivedAtUnixNano _: UInt64
    ) async {}

    func drain() async throws {}
}
