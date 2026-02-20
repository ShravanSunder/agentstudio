import XCTest
@testable import AgentStudio

/// Tests for BridgeBootstrap JavaScript generator.
///
/// The bootstrap script runs at document start in the bridge content world.
/// It installs `window.__bridgeInternal` with relay functions, listens for
/// commands from page world with nonce validation, handles the bridge.ready
/// handshake, and dispatches push events to page world.
final class BridgeBootstrapTests: XCTestCase {

    // MARK: - Bridge Internal API

    func test_script_contains_bridgeInternal_global() {
        let script = BridgeBootstrap.generateScript(bridgeNonce: "test-nonce", pushNonce: "push-nonce")
        XCTAssertTrue(script.contains("window.__bridgeInternal"),
            "Bootstrap must install __bridgeInternal in bridge world")
    }

    // MARK: - Command Listener

    func test_script_contains_command_listener() {
        let script = BridgeBootstrap.generateScript(bridgeNonce: "test-nonce", pushNonce: "push-nonce")
        XCTAssertTrue(script.contains("__bridge_command"),
            "Bootstrap must listen for __bridge_command CustomEvents from page world")
    }

    // MARK: - Nonce Validation

    func test_script_contains_nonce_validation() {
        let script = BridgeBootstrap.generateScript(bridgeNonce: "test-nonce", pushNonce: "push-nonce")
        XCTAssertTrue(script.contains("test-nonce"),
            "Bootstrap must embed bridge nonce for command validation")
    }

    // MARK: - Push Relay

    func test_script_contains_push_relay() {
        let script = BridgeBootstrap.generateScript(bridgeNonce: "test-nonce", pushNonce: "push-nonce")
        XCTAssertTrue(script.contains("__bridge_push"),
            "Bootstrap must dispatch __bridge_push CustomEvents to page world")
    }

    // MARK: - Ready Listener

    func test_script_contains_ready_listener() {
        let script = BridgeBootstrap.generateScript(bridgeNonce: "test-nonce", pushNonce: "push-nonce")
        XCTAssertTrue(script.contains("__bridge_ready") || script.contains("bridge.ready"),
            "Bootstrap must relay bridge.ready from page world to Swift")
    }

    // MARK: - Handshake Dispatch

    func test_script_contains_handshake_dispatch() {
        let script = BridgeBootstrap.generateScript(bridgeNonce: "test-nonce", pushNonce: "push-nonce")
        XCTAssertTrue(script.contains("__bridge_handshake"),
            "Bootstrap must dispatch handshake with pushNonce to page world")
    }

    // MARK: - Nonce Uniqueness

    func test_different_nonces_produce_different_scripts() {
        let script1 = BridgeBootstrap.generateScript(bridgeNonce: "nonce-a", pushNonce: "push-a")
        let script2 = BridgeBootstrap.generateScript(bridgeNonce: "nonce-b", pushNonce: "push-b")
        XCTAssertNotEqual(script1, script2,
            "Different nonces should produce different bootstrap scripts")
    }

    // MARK: - Handshake Replay (P1)

    func test_script_contains_handshake_replay_listener() {
        let script = BridgeBootstrap.generateScript(bridgeNonce: "test-nonce", pushNonce: "push-nonce")
        XCTAssertTrue(script.contains("__bridge_handshake_request"),
            "Bootstrap must listen for __bridge_handshake_request so late page-world listeners can recover the pushNonce")
    }

    // MARK: - Push Envelope Metadata (P2)

    func test_push_relay_includes_revision_and_epoch_at_detail_level() {
        let script = BridgeBootstrap.generateScript(bridgeNonce: "test-nonce", pushNonce: "push-nonce")
        // merge and replace functions should accept revision and epoch params
        // and include __revision/__epoch at the event detail level
        XCTAssertTrue(script.contains("__revision: revision"),
            "Push relay must expose __revision at event detail level for stale guards")
        XCTAssertTrue(script.contains("__epoch: epoch"),
            "Push relay must expose __epoch at event detail level for epoch checks")
    }

    func test_applyEnvelope_extracts_metadata_from_envelope() {
        let script = BridgeBootstrap.generateScript(bridgeNonce: "test-nonce", pushNonce: "push-nonce")
        XCTAssertTrue(script.contains("envelope.__revision"),
            "applyEnvelope must extract __revision from envelope")
        XCTAssertTrue(script.contains("envelope.__epoch"),
            "applyEnvelope must extract __epoch from envelope")
    }
}
