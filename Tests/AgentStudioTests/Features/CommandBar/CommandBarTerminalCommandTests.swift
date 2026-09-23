import AgentStudioCore
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCommandBar

@MainActor
@Suite(.serialized)
struct CommandBarTerminalCommandTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test
    func commandsScopeIncludesTerminalScrollAndPromptCommandsInTerminalGroup() {
        let store = WorkspaceStore()
        let pane = store.createPane()
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let items = CommandBarDataSource.items(
            scope: .commands,
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: FakeAppCommandDispatcher()
        )

        let expectedCommands: [(AppCommand, AppShortcut)] = [
            (.scrollPageUp, .scrollPageUp),
            (.scrollPageDown, .scrollPageDown),
            (.scrollSmallStepUp, .scrollSmallStepUp),
            (.scrollSmallStepDown, .scrollSmallStepDown),
            (.scrollToBottom, .scrollToBottom),
            (.jumpToPreviousPrompt, .jumpToPreviousPrompt),
            (.jumpToNextPrompt, .jumpToNextPrompt),
        ]

        for (command, shortcut) in expectedCommands {
            let item = items.first { $0.command == command }
            #expect(item?.group == "Terminal")
            #expect(item?.shortcutTrigger == shortcut.trigger)
        }
    }
}
