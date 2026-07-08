extension BridgeReviewObservabilitySmokeRenderProof {
    var startupDiagnosticOutcome: String {
        if succeeded {
            return "succeeded"
        }
        return startupDiagnosticSkipReason == nil ? "blocked" : "skipped"
    }

    var startupDiagnosticSkipReason: String? {
        frameLivenessRafAlive == "false" ? "frame_not_live" : nil
    }
}
