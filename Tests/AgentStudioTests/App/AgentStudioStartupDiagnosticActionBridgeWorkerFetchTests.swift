import Testing

@testable import AgentStudio

extension AgentStudioStartupDiagnosticActionTests {
    @Test("startup diagnostic action parses bridge worker fetch scheme smoke command")
    func parsesBridgeWorkerFetchSchemeSmokeCommand() throws {
        let action = try #require(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey: " bridge-worker-fetch-scheme-smoke "
            ]))

        #expect(action.kind == .bridgeWorkerFetchSchemeSmoke)
        #expect(action.commandName == "bridgeWorkerFetchSchemeSmoke")
        #expect(action.suppressesAutomaticLaunchPaneRestore)
    }

    @Test("startup diagnostic action parses product stream WebKit feasibility command")
    func parsesBridgeProductStreamWebKitFeasibilityCommand() throws {
        let action = try #require(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey:
                    " bridge-product-stream-webkit-feasibility "
            ]))

        #expect(action.commandName == "bridgeProductStreamWebKitFeasibility")
        #expect(action.suppressesAutomaticLaunchPaneRestore)
    }
}
