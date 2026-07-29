import AppKit
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite("AppDelegate menu presentation", .serialized)
struct AppDelegateMenuPresentationTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("main menu presence follows presentation policy before dispatcher enablement")
    func mainMenuPresencePrecedesDispatcherEnablement() {
        withTestCoreAtoms { coreAtoms in
            let delegate = AppDelegate()
            delegate.atomStore = AtomRegistry(core: coreAtoms)
            delegate.store = WorkspaceStore()

            let dispatcher = AppCommandDispatcher.shared
            let previousWorkspaceHandler = dispatcher.handler
            let previousShellRouter = dispatcher.appCommandRouter
            let commandHandler = MockCommandHandler()
            commandHandler.canExecuteResult = false
            dispatcher.handler = commandHandler
            dispatcher.appCommandRouter = nil
            defer {
                dispatcher.handler = previousWorkspaceHandler
                dispatcher.appCommandRouter = previousShellRouter
            }

            let closeTabMenuItem = makeMenuItem(command: .closeTab)

            #expect(!delegate.validateMenuItem(closeTabMenuItem))
            #expect(closeTabMenuItem.isHidden)

            let pane = delegate.store.createPane()
            let tab = Tab(paneId: pane.id)
            delegate.store.appendTab(tab)
            delegate.store.setActiveTab(tab.id)
            delegate.store.setActivePane(pane.id, inTab: tab.id)
            coreAtoms.workspaceFocusOwner.focusMainPane(pane.id)

            #expect(!delegate.validateMenuItem(closeTabMenuItem))
            #expect(!closeTabMenuItem.isHidden)

            commandHandler.canExecuteResult = true

            #expect(delegate.validateMenuItem(closeTabMenuItem))
            #expect(!closeTabMenuItem.isHidden)
        }
    }

    private func makeMenuItem(command: AppCommand) -> NSMenuItem {
        let menuItem = NSMenuItem(
            title: command.definition.label,
            action: nil,
            keyEquivalent: ""
        )
        menuItem.representedObject = command.rawValue
        return menuItem
    }
}
