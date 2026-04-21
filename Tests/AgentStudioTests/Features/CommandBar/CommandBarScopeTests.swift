import Testing

@testable import AgentStudio

@Suite("CommandBarScope")
struct CommandBarScopeTests {
    @Test(".inbox scope exists")
    func inboxScopeExists() {
        let _: CommandBarScope = .inbox
    }
}
