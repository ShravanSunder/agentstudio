import Foundation
import Testing

@Suite("Observability TCC protected-data verifier scripts")
struct ObservabilityTCCProtectedDataVerifierScriptTests {
    @Test("debug and beta verifiers can require protected data grant")
    func verifiersCanRequireProtectedDataGrant() throws {
        let debugScript = try String(contentsOfFile: "scripts/verify-debug-observability.sh", encoding: .utf8)
        let betaScript = try String(contentsOfFile: "scripts/verify-beta-observability.sh", encoding: .utf8)

        for script in [debugScript, betaScript] {
            #expect(script.contains("AGENTSTUDIO_TCC_REQUIRE_PROTECTED_DATA_GRANT"))
            #expect(script.contains("agentstudio.tcc.access.target messages_data"))
            #expect(script.contains("agentstudio.tcc.access.result granted"))
            #expect(script.contains("TCC protected-data grant was required"))
        }
    }
}
