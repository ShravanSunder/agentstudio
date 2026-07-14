import Foundation
import Testing

@testable import AgentStudio

/// Tests for BridgeBootstrap JavaScript generator.
///
/// The bootstrap script runs at document start in the bridge content world.
/// It installs `window.__bridgeInternal` with relay functions, handles the one-shot
/// bridge.ready bootstrap, and dispatches push events to page world.
@Suite(.serialized)
final class BridgeBootstrapTests {

    // MARK: - Bridge Internal API

    @Test
    func test_script_contains_bridgeInternal_global() {
        let script = BridgeBootstrap.generateScript(bridgeNonce: "test-nonce", pushNonce: "push-nonce")
        #expect(script.contains("window.__bridgeInternal"), "Bootstrap must install __bridgeInternal in bridge world")
    }

    // MARK: - Command Relay Cutover

    @Test
    func test_script_does_not_install_page_world_command_listener() {
        let script = BridgeBootstrap.generateScript(bridgeNonce: "test-nonce", pushNonce: "push-nonce")
        #expect(
            !script.contains("__bridge_command"),
            "Bootstrap must not relay ordinary browser-to-native commands through page-world script messages")
    }

    // MARK: - Push Nonce

    @Test
    func test_script_contains_push_nonce_for_intake_and_push_validation() {
        let script = BridgeBootstrap.generateScript(bridgeNonce: "test-nonce", pushNonce: "push-nonce")
        #expect(script.contains("push-nonce"), "Bootstrap must embed push nonce for push/intake validation")
        #expect(!script.contains("test-nonce"), "Bootstrap must not embed command nonce for script-message RPC")
    }

    // MARK: - Push Relay

    @Test
    func test_script_contains_push_relay() {
        let script = BridgeBootstrap.generateScript(bridgeNonce: "test-nonce", pushNonce: "push-nonce")
        #expect(script.contains("__bridge_push"), "Bootstrap must dispatch __bridge_push CustomEvents to page world")
    }

    // MARK: - Ready Listener

    @Test
    func test_script_contains_ready_listener() {
        let script = BridgeBootstrap.generateScript(bridgeNonce: "test-nonce", pushNonce: "push-nonce")
        #expect(
            script.contains("__bridge_ready") || script.contains("bridge.ready"),
            "Bootstrap must relay bridge.ready from page world to Swift")
    }

    // MARK: - Handshake Dispatch

    @Test
    func test_script_contains_handshake_dispatch() {
        let script = BridgeBootstrap.generateScript(bridgeNonce: "test-nonce", pushNonce: "push-nonce")
        #expect(script.contains("__bridge_handshake"), "Bootstrap must dispatch handshake with pushNonce to page world")
    }

    // MARK: - Nonce Uniqueness

    @Test
    func test_different_nonces_produce_different_scripts() {
        let script1 = BridgeBootstrap.generateScript(bridgeNonce: "nonce-a", pushNonce: "push-a")
        let script2 = BridgeBootstrap.generateScript(bridgeNonce: "nonce-b", pushNonce: "push-b")
        #expect(script1 != script2, "Different nonces should produce different bootstrap scripts")
    }

    // MARK: - Handshake Replay (P1)

    @Test
    func test_script_contains_handshake_replay_listener() {
        let script = BridgeBootstrap.generateScript(bridgeNonce: "test-nonce", pushNonce: "push-nonce")
        #expect(
            script.contains("__bridge_handshake_request"),
            "Bootstrap must listen for __bridge_handshake_request so late page-world listeners can recover the pushNonce"
        )
    }

    // MARK: - Push Envelope Metadata (P2)

    @Test
    func test_push_relay_includes_revision_and_epoch_at_detail_level() {
        let script = BridgeBootstrap.generateScript(bridgeNonce: "test-nonce", pushNonce: "push-nonce")
        // merge and replace functions should accept revision and epoch params
        // and include __revision/__epoch at the event detail level
        #expect(
            script.contains("__revision: revision"),
            "Push relay must expose __revision at event detail level for stale guards")
        #expect(
            script.contains("__epoch: epoch"), "Push relay must expose __epoch at event detail level for epoch checks")
    }

    @Test
    func test_applyEnvelope_extracts_metadata_from_envelope() {
        let script = BridgeBootstrap.generateScript(bridgeNonce: "test-nonce", pushNonce: "push-nonce")
        #expect(script.contains("envelope.__revision"), "applyEnvelope must extract __revision from envelope")
        #expect(script.contains("envelope.__epoch"), "applyEnvelope must extract __epoch from envelope")
    }

    @Test
    func test_push_relay_preserves_store_at_detail_level() {
        let script = BridgeBootstrap.generateScript(bridgeNonce: "test-nonce", pushNonce: "push-nonce")
        #expect(script.contains("op: 'merge'"))
        #expect(script.contains("op: 'replace'"))
        #expect(
            script.contains("store: store"),
            "Push relay must expose store at event detail level so page-world receivers can route pushes")
    }

    @Test
    func test_handshake_carries_optional_telemetry_config() {
        let config = BridgeTelemetryBootstrapConfig.enabled(
            scopes: [.web, .webKit],
            scenario: "package_apply_content_fetch_v1"
        )
        let script = BridgeBootstrap.generateScript(
            bridgeNonce: "test-nonce",
            pushNonce: "push-nonce",
            telemetryConfig: config
        )
        #expect(script.contains("const TELEMETRY_CONFIG ="))
        #expect(!script.contains("endpointUrl"))
        #expect(!script.contains("maxSamplesPerBatch"))
        #expect(!script.contains("maxEncodedBatchBytes"))
        #expect(!script.contains("minimumFlushIntervalMilliseconds"))
        #expect(!script.contains("system.bridgeTelemetry"))
        #expect(script.contains("telemetryConfig: TELEMETRY_CONFIG"))
    }

    @Test
    func test_handshake_carries_viewer_open_anchor_for_time_to_first_interaction() {
        let config = BridgeTelemetryBootstrapConfig.enabled(
            scopes: [.web],
            scenario: "package_apply_content_fetch_v1",
            viewerOpenEpochUnixMillis: 1_750_000_000_000,
            viewerOpenTraceparent: "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"
        )
        let script = BridgeBootstrap.generateScript(
            bridgeNonce: "test-nonce",
            pushNonce: "push-nonce",
            telemetryConfig: config
        )
        #expect(script.contains("viewerOpenEpochUnixMillis"))
        #expect(script.contains("1750000000000"))
        #expect(script.contains("viewerOpenTraceparent"))
        #expect(script.contains("00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"))
    }

    @Test
    func test_script_publishes_review_frame_authority_attributes() {
        let script = BridgeBootstrap.generateScript(
            bridgeNonce: "test-nonce",
            pushNonce: "push-nonce",
            reviewPaneId: "pane-123",
            reviewStreamId: "review:pane-123"
        )
        #expect(script.contains("const REVIEW_PANE_ID = \"pane-123\""))
        #expect(script.contains("const REVIEW_STREAM_ID = \"review:pane-123\""))
        #expect(script.contains("data-bridge-review-pane-id"))
        #expect(script.contains("data-bridge-review-stream-id"))
    }

    @Test
    func test_script_selects_worktree_file_protocol_without_source_identity_relay() {
        let script = BridgeBootstrap.generateScript(
            bridgeNonce: "test-nonce",
            pushNonce: "push-nonce",
            appProtocol: "worktree-file"
        )

        #expect(script.contains("data-bridge-app-protocol"))
        #expect(script.contains("const APP_PROTOCOL = \"worktree-file\""))
        #expect(!script.contains("WORKTREE_FILE_SOURCE_SPEC"))
        #expect(!script.contains("data-bridge-worktree-file-source-spec"))
    }

    @Test
    func test_applyEnvelope_preserves_trace_context_at_detail_level() {
        let script = BridgeBootstrap.generateScript(bridgeNonce: "test-nonce", pushNonce: "push-nonce")
        #expect(script.contains("envelope.__traceContext"))
        #expect(script.contains("__traceContext: traceContext || null"))
        #expect(script.contains("this.merge(store, payload, revision, epoch, slice, traceContext)"))
        #expect(script.contains("this.replace(store, payload, revision, epoch, slice, traceContext)"))
    }

    @Test
    func test_applyEnvelope_preserves_slice_at_detail_level() {
        let script = BridgeBootstrap.generateScript(bridgeNonce: "test-nonce", pushNonce: "push-nonce")
        #expect(script.contains("const slice = envelope.slice"))
        #expect(script.contains("slice: slice"))
        #expect(script.contains("merge: function(store, data, revision, epoch, slice, traceContext)"))
        #expect(script.contains("replace: function(store, data, revision, epoch, slice, traceContext)"))
    }

    @Test
    func productSessionBootstrapIsRequestedDynamicallyWithoutEmbeddedAuthority() {
        let script = BridgeBootstrap.generateScript(
            bridgeNonce: "test-nonce",
            pushNonce: "push-nonce"
        )

        #expect(script.contains("bridge.productSession.bootstrap"))
        #expect(script.contains("detail.reason === 'workerReplacement'"))
        #expect(!script.contains("PRODUCT_SESSION_BOOTSTRAP"))
        #expect(!script.contains("PRODUCT_CAPABILITY_BYTES"))
        #expect(!script.contains("productCapability:"))
    }

    @Test
    func test_applyEnvelopeJSON_dispatches_string_payload_with_push_nonce() {
        let script = BridgeBootstrap.generateScript(bridgeNonce: "test-nonce", pushNonce: "push-nonce")
        #expect(script.contains("applyEnvelopeJSON: function(envelopeJSON)"))
        #expect(script.contains("__bridge_push_json"))
        #expect(script.contains("detail: { json: envelopeJSON, nonce: PUSH_NONCE }"))
    }

    @Test
    func test_applyIntakeFrameJSON_buffers_and_dispatches_to_host_port_and_page_event() {
        let script = BridgeBootstrap.generateScript(bridgeNonce: "test-nonce", pushNonce: "push-nonce")
        #expect(script.contains("applyIntakeFrameJSON: function(frameJSON)"))
        #expect(script.contains("dispatchIntakeFrameJSON(frameJSON)"))
        #expect(script.contains("PENDING_INTAKE_FRAME_JSON.push(frameJSON)"))
        #expect(script.contains("postHostIntakeFrameJSON(frameJSON)"))
        #expect(script.contains("dispatchPageIntakeFrameJSON(frameJSON)"))
        #expect(script.contains("__bridge_intake_json"))
        #expect(script.contains("detail: { json: frameJSON, nonce: PUSH_NONCE }"))
    }

    @Test
    func test_intake_frame_dispatch_buffers_and_replays_late_listener_frames() {
        let script = BridgeBootstrap.generateScript(bridgeNonce: "test-nonce", pushNonce: "push-nonce")
        #expect(script.contains("const PENDING_INTAKE_FRAME_JSON = []"))
        #expect(script.contains("function dispatchIntakeFrameJSON(frameJSON)"))
        #expect(script.contains("PENDING_INTAKE_FRAME_JSON.push(frameJSON)"))
        #expect(!script.contains("PENDING_INTAKE_FRAME_JSON.shift()"))
        #expect(script.contains("__bridge_intake_replay_request"))
        #expect(script.contains("for (const frameJSON of PENDING_INTAKE_FRAME_JSON)"))
        #expect(script.contains("dispatchPageIntakeFrameJSON(frameJSON)"))
    }

    @Test
    func test_intake_frame_dispatch_uses_host_intake_message_port() {
        let script = BridgeBootstrap.generateScript(bridgeNonce: "test-nonce", pushNonce: "push-nonce")
        #expect(script.contains("const HOST_INTAKE_PORTS = new Set()"))
        #expect(script.contains("function publishHostIntakePort()"))
        #expect(script.contains("type: 'agentstudio.bridge.hostIntakePort'"))
        #expect(script.contains("function postHostIntakeFrameJSON(frameJSON)"))
        #expect(script.contains("type: 'agentstudio.bridge.hostIntakeFrameJSON'"))
        #expect(script.contains("__bridge_host_intake_port_request"))
        #expect(script.contains("postHostIntakeFrameJSON(frameJSON)"))
    }

    @Test
    func test_protocolRPC_has_no_bootstrap_script_message_relay() {
        let script = BridgeBootstrap.generateScript(bridgeNonce: "test-nonce", pushNonce: "push-nonce")

        #expect(!script.contains("sendCommandJSON: function(commandJSON)"))
        #expect(!script.contains("__bridge_response"))
        #expect(!script.contains("PAGE_WORLD_ALLOWED_COMMAND_METHODS"))
        #expect(!script.contains("'bridge.intakeReady'"))
        #expect(!script.contains("'bridge.activeViewerMode.update'"))
        #expect(!script.contains("'worktreeFileSurface.requestFileDescriptor'"))
        #expect(!script.contains("pageWorldLegacy"))
    }
}
