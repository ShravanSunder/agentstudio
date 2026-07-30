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

    @Test("menu activation rechecks New Window and Close Window through dispatcher")
    func windowMenuActivationRechecksDispatcher() async throws {
        let rejectingRouter = RejectingWindowMenuRouter()

        try await withIsolatedCommandDispatcher(
            configure: {
                AppCommandDispatcher.shared.handler = nil
                AppCommandDispatcher.shared.appCommandRouter = rejectingRouter
            },
            body: {
                let delegate = AppDelegate()

                delegate.dispatchNewWindowMenuCommand()
                delegate.dispatchCloseWindowMenuCommand()

                #expect(rejectingRouter.capabilityCommands == [.newWindow, .closeWindow])
                #expect(rejectingRouter.executedCommands.isEmpty)
            }
        )
    }

    @Test("File menu routes New Window and Close Window through dispatcher selectors")
    func fileMenuRoutesWindowCommandsThroughDispatcherSelectors() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/App/Boot/AppDelegate.swift"
            ),
            encoding: .utf8
        )

        #expect(
            source.contains(
                "menuItem(command: .newWindow, action: #selector(dispatchNewWindowMenuCommand))"
            )
        )
        #expect(
            source.contains(
                "menuItem(command: .closeWindow, action: #selector(dispatchCloseWindowMenuCommand))"
            )
        )
        #expect(source.contains("AppCommandDispatcher.shared.dispatch(.newWindow)"))
        #expect(source.contains("AppCommandDispatcher.shared.dispatch(.closeWindow)"))
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

@MainActor
private final class RejectingWindowMenuRouter: ShellCommandHandling {
    private(set) var capabilityCommands: [AppCommand] = []
    private(set) var executedCommands: [AppCommand] = []

    func canExecute(_ command: AppCommand) -> Bool {
        capabilityCommands.append(command)
        return false
    }

    func canExecute(_: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool {
        false
    }

    func execute(_ command: AppCommand) -> Bool {
        executedCommands.append(command)
        return true
    }

    func execute(_: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool {
        false
    }

    func showRepoCommandBar() {}
    func refreshWorktrees() {}
    func refocusActivePane() {}
}
