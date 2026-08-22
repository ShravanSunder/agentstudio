import AgentStudioCore
import AgentStudioTestSupport
import Testing

@testable import AgentStudioCommandBar

@MainActor
@Suite("CommandBar retired Inbox scope")
struct CommandBarInboxCommandsTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("production Inbox scope is empty without an active command provider")
    func productionInboxScopeIsEmptyWithoutActiveCommandProvider() {
        let items = CommandBarDataSource.items(
            scope: .inbox,
            store: WorkspaceStore(),
            repoCache: RepoCacheAtom(),
            dispatcher: FakeAppCommandDispatcher(),
            notificationInboxCommands: nil
        )

        #expect(items.isEmpty)
    }
}
