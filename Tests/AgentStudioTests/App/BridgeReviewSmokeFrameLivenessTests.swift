import Testing

@testable import AgentStudio

struct BridgeReviewSmokeFrameLivenessTests {
    @Test("Bridge smoke render proof skips product verdict when the frame never becomes live")
    func bridgeSmokeRenderProofSkipsProductVerdictWhenFrameNeverBecomesLive() {
        var proof = makeFullyHydratedBridgeSmokeRenderProof()
        proof.frameLivenessRafAlive = "false"
        proof.frameLivenessRafFiredLatencyBucket = "not-fired"

        #expect(!proof.succeeded)
        #expect(proof.startupDiagnosticOutcome == "skipped")
        #expect(proof.startupDiagnosticSkipReason == "frame_not_live")
        #expect(
            proof.attributes["agentstudio.startup_diagnostic.bridge.frame_liveness.raf_alive"]
                == .string("false"))
        #expect(proof.attributes["agentstudio.startup_diagnostic.render_proof.succeeded"] == .bool(false))
    }
}
