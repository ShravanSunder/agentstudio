import Foundation
import Testing

@Suite("Observability debug launch metadata script contracts")
struct ObservabilityDebugLaunchMetadataScriptTests {
    @Test("debug launcher records background-by-default launch and auth metadata")
    func debugLauncherRecordsSidebarProofLaunchAndAuthMetadata() throws {
        let script = try String(contentsOfFile: "scripts/run-debug-observability.sh", encoding: .utf8)

        #expect(script.contains("AGENTSTUDIO_OBSERVABILITY_ACTIVATION_MODE"))
        #expect(script.contains("AGENTSTUDIO_OBSERVABILITY_IPC_AUTH_MODE"))
        #expect(script.contains("DEBUG_LAUNCH_ACTIVATE=\"${AGENTSTUDIO_DEBUG_LAUNCH_ACTIVATE:-0}\""))
        #expect(script.contains("AGENTSTUDIO_DEBUG_LAUNCH_ACTIVATE must be 0 or 1"))
        #expect(script.contains("launch_activation_flag=\"-g\""))
        #expect(script.contains("launch_activation_mode=background"))
        #expect(script.contains("if [ \"$DEBUG_LAUNCH_ACTIVATE\" = \"1\" ]; then"))
        #expect(script.contains("launch_activation_flag=\"\""))
        #expect(script.contains("launch_activation_mode=foreground"))
        #expect(script.contains("launch_activation_mode=unknown"))
        #expect(script.contains("ipc_auth_mode=unsafe_no_auth"))
        #expect(script.contains("open_app \"$app_path\" \"$launch_log\" \"$launch_activation_flag\""))
    }

    @Test("debug verifier reports launch and auth metadata")
    func debugVerifierReportsLaunchAndAuthMetadata() throws {
        let script = try String(contentsOfFile: "scripts/verify-debug-observability.sh", encoding: .utf8)

        #expect(script.contains("AGENTSTUDIO_OBSERVABILITY_ACTIVATION_MODE"))
        #expect(script.contains("AGENTSTUDIO_OBSERVABILITY_IPC_AUTH_MODE"))
        #expect(script.contains("activation_mode=${state_activation_mode:-unknown}"))
        #expect(script.contains("ipc_auth_mode=${state_ipc_auth_mode:-unknown}"))
        #expect(script.contains("sidebar-performance-proof"))
        #expect(script.contains("sidebar-performance-proof requires background LaunchServices activation mode"))
        #expect(script.contains("sidebar-performance-proof requires authenticated IPC auth mode"))
        #expect(script.contains("agentstudio.startup_diagnostic.native_table_pilot.scale.count"))
        #expect(script.contains("agentstudio.startup_diagnostic.native_table_pilot.passed"))
        #expect(script.contains("agentstudio.startup_diagnostic.native_table_pilot.completed"))
        #expect(!script.contains("agentstudio.startup_diagnostic.projection_proof.succeeded"))
        #expect(script.contains("\\\"true\\\"|true|\\\"1\\\"|1"))
        #expect(!script.contains("agentstudio.startup_diagnostic.fixture.inbox_notification.count"))
    }
}
