import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct CommandBarTerminalCommandTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test
    func commandsScopeIncludesTerminalScrollAndPromptCommandsInTerminalGroup() {
        let store = WorkspaceStore()
        let pane = store.createPane()
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)
        let focus = WorkspacePaneFocus(
            activeTabId: tab.id,
            activePaneId: pane.id,
            paneContentType: .terminal,
            satisfiedRequirements: [.hasActivePane]
        )

        let items = CommandBarDataSource.items(
            scope: .commands,
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: AppCommandDispatcher.shared,
            focus: focus
        )

        let scroll = items.first { $0.command == .scrollToBottom }
        let pageUp = items.first { $0.command == .scrollPageUp }
        let previousPrompt = items.first { $0.command == .jumpToPreviousPrompt }
        let nextPrompt = items.first { $0.command == .jumpToNextPrompt }

        #expect(scroll?.group == "Terminal")
        #expect(pageUp?.group == "Terminal")
        #expect(previousPrompt?.group == "Terminal")
        #expect(nextPrompt?.group == "Terminal")
        #expect(scroll?.shortcutTrigger == AppShortcut.scrollToBottom.trigger)
        #expect(pageUp?.shortcutTrigger == AppShortcut.scrollPageUp.trigger)
        #expect(previousPrompt?.shortcutTrigger == AppShortcut.jumpToPreviousPrompt.trigger)
        #expect(nextPrompt?.shortcutTrigger == AppShortcut.jumpToNextPrompt.trigger)
    }
}
