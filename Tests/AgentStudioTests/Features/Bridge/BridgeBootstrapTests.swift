import Foundation
import Testing

@testable import AgentStudio

/// Tests for BridgeBootstrap JavaScript generator.
///
/// The bootstrap script runs at document start in the bridge content world.
/// It installs `window.__bridgeInternal` with relay functions, listens for
/// commands from page world with nonce validation, handles the bridge.ready
/// handshake, and dispatches push events to page world.
@Suite(.serialized)
final class BridgeBootstrapTests {

    // MARK: - Bridge Internal API

    @Test
    func test_script_contains_bridgeInternal_global() {
        let script = BridgeBootstrap.generateScript(bridgeNonce: "test-nonce", pushNonce: "push-nonce")
        #expect(script.contains("window.__bridgeInternal"), "Bootstrap must install __bridgeInternal in bridge world")
    }

    // MARK: - Command Listener

    @Test
    func test_script_contains_command_listener() {
        let script = BridgeBootstrap.generateScript(bridgeNonce: "test-nonce", pushNonce: "push-nonce")
        #expect(
            script.contains("__bridge_command"),
            "Bootstrap must listen for __bridge_command CustomEvents from page world")
    }

    // MARK: - Nonce Validation

    @Test
    func test_script_contains_nonce_validation() {
        let script = BridgeBootstrap.generateScript(bridgeNonce: "test-nonce", pushNonce: "push-nonce")
        #expect(script.contains("test-nonce"), "Bootstrap must embed bridge nonce for command validation")
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
        #expect(script.contains("system.bridgeTelemetry"))
        #expect(script.contains("telemetryConfig: TELEMETRY_CONFIG"))
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
    func test_applyEnvelopeJSON_dispatches_string_payload_with_push_nonce() {
        let script = BridgeBootstrap.generateScript(bridgeNonce: "test-nonce", pushNonce: "push-nonce")
        #expect(script.contains("applyEnvelopeJSON: function(envelopeJSON)"))
        #expect(script.contains("__bridge_push_json"))
        #expect(script.contains("detail: { json: envelopeJSON, nonce: PUSH_NONCE }"))
    }

    @Test
    func test_applyIntakeFrameJSON_dispatches_string_payload_with_push_nonce() {
        let script = BridgeBootstrap.generateScript(bridgeNonce: "test-nonce", pushNonce: "push-nonce")
        #expect(script.contains("applyIntakeFrameJSON: function(frameJSON)"))
        #expect(script.contains("__bridge_intake_json"))
        #expect(script.contains("detail: { json: frameJSON, nonce: PUSH_NONCE }"))
    }
}
