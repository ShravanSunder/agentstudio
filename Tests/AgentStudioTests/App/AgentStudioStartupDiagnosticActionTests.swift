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

    @Test("startup diagnostic action parses command bar repo filter command")
    func parsesCommandBarRepoFilterCommand() throws {
        let action = try #require(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey: " command-bar-repo-filter "
            ]))

        #expect(action.kind == .commandBarRepoFilter)
        #expect(action.commandName == "commandBarRepoFilter")
    }

    @Test("startup diagnostic action parses add watch folder command and path")
    func parsesAddWatchFolderCommandAndPath() throws {
        let action = try #require(
            AgentStudioStartupDiagnosticAction.fromEnvironment([
                AgentStudioStartupDiagnosticAction.environmentKey: " add-watch-folder "
            ]))
        let folderURL = try #require(
            AgentStudioStartupDiagnosticAction.watchFolderURL(from: [
                AgentStudioStartupDiagnosticAction.watchFolderEnvironmentKey: " ~/agentstudio-fixture "
            ]))

        #expect(action.kind == .addWatchFolder)
        #expect(action.commandName == "addWatchFolder")
        #expect(folderURL.path.hasSuffix("/agentstudio-fixture"))
    }

    @Test("startup diagnostic watch folder path is optional")
    func watchFolderPathIsOptional() {
        #expect(AgentStudioStartupDiagnosticAction.watchFolderURL(from: [:]) == nil)
        #expect(
            AgentStudioStartupDiagnosticAction.watchFolderURL(from: [
                AgentStudioStartupDiagnosticAction.watchFolderEnvironmentKey: "   "
            ]) == nil)
    }
}
