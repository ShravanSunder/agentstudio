import Foundation
import Testing

@Suite("Observability debug launch metadata script contracts")
struct ObservabilityDebugLaunchMetadataScriptTests {
    @Test("debug launcher records sidebar proof launch and auth metadata")
    func debugLauncherRecordsSidebarProofLaunchAndAuthMetadata() throws {
        let script = try String(contentsOfFile: "scripts/run-debug-observability.sh", encoding: .utf8)

        #expect(script.contains("AGENTSTUDIO_OBSERVABILITY_ACTIVATION_MODE"))
        #expect(script.contains("AGENTSTUDIO_OBSERVABILITY_IPC_AUTH_MODE"))
        #expect(script.contains("launch_activation_mode=background"))
        #expect(script.contains("launch_activation_mode=direct_executable"))
        #expect(script.contains("ipc_auth_mode=unsafe_no_auth"))
        #expect(script.contains("open_app \"$app_path\" \"$launch_log\" \"-g\""))
    }

    @Test("debug verifier reports launch and auth metadata")
    func debugVerifierReportsLaunchAndAuthMetadata() throws {
        let script = try String(contentsOfFile: "scripts/verify-debug-observability.sh", encoding: .utf8)

        #expect(script.contains("AGENTSTUDIO_OBSERVABILITY_ACTIVATION_MODE"))
        #expect(script.contains("AGENTSTUDIO_OBSERVABILITY_IPC_AUTH_MODE"))
        #expect(script.contains("activation_mode=${state_activation_mode:-unknown}"))
        #expect(script.contains("ipc_auth_mode=${state_ipc_auth_mode:-authenticated}"))
        #expect(script.contains("sidebar-performance-proof"))
        #expect(script.contains("sidebar-performance-proof requires background LaunchServices activation mode"))
        #expect(script.contains("sidebar-performance-proof requires authenticated IPC auth mode"))
    }
}
