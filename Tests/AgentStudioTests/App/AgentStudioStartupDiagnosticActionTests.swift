import Testing

@testable import AgentStudio

struct AgentStudioStartupDiagnosticActionTests {
    @Test("startup diagnostic action is disabled unless exact env value is present")
    func disabledUnlessExactEnvironmentValueIsPresent() {
        #expect(AgentStudioStartupDiagnosticAction.fromEnvironment([:]) == nil)
        #expect(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey: "off"
            ]) == nil)
        #expect(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey: "new-terminal"
            ]) == nil)
    }

    @Test("startup diagnostic action parses new tab command")
    func parsesNewTabCommand() throws {
        let action = try #require(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey: " new-tab "
            ]))

        #expect(action.kind == .newTab)
        #expect(action.commandName == "newTab")
    }
}
