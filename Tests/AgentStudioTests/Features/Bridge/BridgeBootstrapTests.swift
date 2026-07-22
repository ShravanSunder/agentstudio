import Foundation
import Testing

@testable import AgentStudio

/// Contract tests for the document-start bootstrap that remains after the product-transport hard cut.
@Suite(.serialized)
final class BridgeBootstrapTests {
    @Test
    func bootstrapOwnsReadinessAndSessionBootstrapOnly() {
        // Arrange
        let script = BridgeBootstrap.generateScript()

        // Act
        let forbiddenLegacyCarrierMarkers = [
            "window.__bridgeInternal",
            "__bridge_command",
            "__bridge_push",
            "__bridge_intake",
            "pushNonce",
            "PUSH_NONCE",
            "applyEnvelope",
            "applyIntakeFrameJSON",
        ]

        // Assert
        #expect(script.contains("__bridge_ready"))
        #expect(script.contains("bridge.ready"))
        #expect(script.contains("__bridge_product_session_bootstrap_request"))
        #expect(script.contains("__bridge_telemetry_session_bootstrap_request"))
        #expect(!forbiddenLegacyCarrierMarkers.contains(where: script.contains))
    }

    @Test
    func readyRelayRequiresAndPreservesThePageRequestIdentifier() {
        let script = BridgeBootstrap.generateScript()

        #expect(script.contains("typeof event.detail.requestId === 'string'"))
        #expect(script.contains("requestId.length === 0"))
        #expect(script.contains("id: requestId, method: 'bridge.ready'"))
        #expect(script.contains("params: {}"))
    }

    @Test
    func handshakePublishesBootstrapContextAndSupportsLateListenerReplay() {
        let script = BridgeBootstrap.generateScript()

        #expect(script.contains("__bridge_handshake"))
        #expect(script.contains("detail: { telemetryConfig: TELEMETRY_CONFIG }"))
        #expect(script.contains("__bridge_handshake_request"))
    }

    @Test
    func handshakeCarriesOptionalTelemetryConfigWithoutWorkerAuthority() {
        let config = BridgeTelemetryBootstrapConfig.enabled(
            scopes: [.web, .webKit],
            scenario: "package_apply_content_fetch_v1"
        )
        let script = BridgeBootstrap.generateScript(telemetryConfig: config)

        #expect(script.contains("const TELEMETRY_CONFIG ="))
        #expect(script.contains("telemetryConfig: TELEMETRY_CONFIG"))
        #expect(!script.contains("endpointUrl"))
        #expect(!script.contains("maxSamplesPerBatch"))
        #expect(!script.contains("maxEncodedBatchBytes"))
        #expect(!script.contains("minimumFlushIntervalMilliseconds"))
        #expect(!script.contains("system.bridgeTelemetry"))
    }

    @Test
    func handshakeCarriesViewerOpenAnchorForTimeToFirstInteraction() {
        let config = BridgeTelemetryBootstrapConfig.enabled(
            scopes: [.web],
            scenario: "package_apply_content_fetch_v1",
            viewerOpenEpochUnixMillis: 1_750_000_000_000,
            viewerOpenTraceparent: "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"
        )
        let script = BridgeBootstrap.generateScript(telemetryConfig: config)

        #expect(script.contains("viewerOpenEpochUnixMillis"))
        #expect(script.contains("1750000000000"))
        #expect(script.contains("viewerOpenTraceparent"))
        #expect(script.contains("00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"))
    }

    @Test
    func bootstrapPublishesReviewFrameAuthorityAttributes() {
        let script = BridgeBootstrap.generateScript(
            reviewPaneId: "pane-123",
            reviewStreamId: "review:pane-123"
        )

        #expect(script.contains("const REVIEW_PANE_ID = \"pane-123\""))
        #expect(script.contains("const REVIEW_STREAM_ID = \"review:pane-123\""))
        #expect(script.contains("data-bridge-review-pane-id"))
        #expect(script.contains("data-bridge-review-stream-id"))
    }

    @Test
    func bootstrapSelectsWorktreeFileProtocolWithoutSourceIdentityRelay() {
        let script = BridgeBootstrap.generateScript(appProtocol: "worktree-file")

        #expect(script.contains("data-bridge-app-protocol"))
        #expect(script.contains("const APP_PROTOCOL = \"worktree-file\""))
        #expect(!script.contains("WORKTREE_FILE_SOURCE_SPEC"))
        #expect(!script.contains("data-bridge-worktree-file-source-spec"))
    }

    @Test
    func productSessionBootstrapUsesCorrelatedRequestsAndAClosedReasonUnion() {
        let script = BridgeBootstrap.generateScript()

        #expect(script.contains("typeof detail.requestId === 'string'"))
        #expect(script.contains("detail.reason === 'initial'"))
        #expect(script.contains("detail.reason === 'workerReplacement'"))
        #expect(script.contains("method: 'bridge.productSession.bootstrap'"))
        #expect(script.contains("params: { reason: reason }"))
        #expect(!script.contains("PRODUCT_SESSION_BOOTSTRAP"))
        #expect(!script.contains("PRODUCT_CAPABILITY_BYTES"))
        #expect(!script.contains("productCapability:"))
    }

    @Test
    func telemetrySessionBootstrapUsesCorrelatedRequestsAndAClosedReasonUnion() {
        let script = BridgeBootstrap.generateScript()

        #expect(script.contains("detail.reason === 'initial'"))
        #expect(script.contains("detail.reason === 'sidecarReplacement'"))
        #expect(script.contains("method: 'bridge.telemetrySession.bootstrap'"))
        #expect(script.contains("params: { reason: reason }"))
    }

    @Test
    func bootstrapHasNoOrdinaryPageCommandRPCOrLegacyCarrierRelay() {
        let script = BridgeBootstrap.generateScript()

        #expect(!script.contains("sendCommandJSON"))
        #expect(!script.contains("__bridge_response"))
        #expect(!script.contains("PAGE_WORLD_ALLOWED_COMMAND_METHODS"))
        #expect(!script.contains("'bridge.intakeReady'"))
        #expect(!script.contains("'bridge.activeViewerMode.update'"))
        #expect(!script.contains("'worktreeFileSurface.requestFileDescriptor'"))
        #expect(!script.contains("pageWorldLegacy"))
    }
}
