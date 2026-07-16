import Testing

@testable import AgentStudio

struct BridgeProductPaintStartupDiagnosticTests {
    @Test("startup diagnostic action parses Bridge product paint correlation command")
    func parsesBridgeProductPaintCorrelationCommand() throws {
        let action = try #require(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey: " bridge-product-paint-correlation "
            ]))

        #expect(action.kind == .bridgeProductPaintCorrelation)
        #expect(action.commandName == "bridgeProductPaintCorrelation")
        #expect(action.suppressesAutomaticLaunchPaneRestore)
    }

    @Test("Bridge product paint diagnostic correlates Review and File through painted DOM")
    func bridgeProductPaintDiagnosticCorrelatesReviewAndFilePaint() {
        let javaScript = AppDelegate.bridgeProductPaintCorrelationJavaScript(
            relativePath: "tracked.txt",
            sha256: "expected-sha",
            canary: "expected-canary"
        )

        #expect(javaScript.contains("data-bridge-painted-source-correlations"))
        #expect(javaScript.contains("correlation?.surface === surface"))
        #expect(javaScript.contains("correlation?.observedSha256 === expectedSha256"))
        #expect(javaScript.contains("correlation?.disposition === 'painted'"))
        #expect(javaScript.contains("correlation?.text?.includes(expectedCanary)"))
        #expect(javaScript.contains("bridge-viewer-context-file"))
        #expect(javaScript.contains("data-item-path"))
        #expect(javaScript.contains("__bridgeFrameLivenessProbe?.rafAlive"))
    }
}
