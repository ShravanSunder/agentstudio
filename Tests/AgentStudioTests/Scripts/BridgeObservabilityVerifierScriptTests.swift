import Foundation
import Testing

@Suite("Bridge observability verifier script")
struct BridgeObservabilityVerifierScriptTests {
    @Test("verifier covers all bridge lanes with marker-scoped Victoria proof")
    func verifierCoversAllBridgeLanesWithMarkerScopedVictoriaProof() throws {
        let verifierScript = try String(
            contentsOfFile: "scripts/verify-bridge-observability.sh",
            encoding: .utf8
        )
        let miseConfig = try String(contentsOfFile: ".mise.toml", encoding: .utf8)

        #expect(verifierScript.contains("bridge-review-observability-smoke"))
        #expect(verifierScript.contains("scripts/verify-debug-observability.sh"))
        #expect(verifierScript.contains("performance.bridge.swift.package_build"))
        #expect(verifierScript.contains("performance.bridge.webkit.rpc_dispatch"))
        #expect(verifierScript.contains("performance.bridge.web.content_fetch"))
        #expect(verifierScript.contains("TRACES_QUERY_URL"))
        #expect(verifierScript.contains("span_attr:agentstudio.trace.name"))
        #expect(verifierScript.contains("span_attr:agentstudio.bridge.test.scenario"))
        #expect(verifierScript.contains("span_attr:agentstudio.bridge.rpc.method_class"))
        #expect(verifierScript.contains("agentstudio.bridge.rpc.method_class:telemetry"))
        #expect(verifierScript.contains("telemetry_self_rpc=absent"))
        #expect(verifierScript.contains("agentstudio.bridge.test.scenario"))
        #expect(verifierScript.contains("agentstudio.bridge.item_id"))
        #expect(miseConfig.contains("[tasks.verify-bridge-observability]"))
    }
}
