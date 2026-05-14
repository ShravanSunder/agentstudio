import AppKit
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("PaneTabViewController PaneInbox dispatch", .serialized)
struct PaneTabViewControllerPaneInboxDispatchTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("dispatcher PaneInbox command reaches the active parent pane scope")
    func dispatcherShowPaneInboxNotificationsOpensActiveParentScope() throws {
        let harness = makeHarness()
        let previousHandler = CommandDispatcher.shared.handler
        let previousRouter = CommandDispatcher.shared.appCommandRouter
        defer {
            CommandDispatcher.shared.handler = previousHandler
            CommandDispatcher.shared.appCommandRouter = previousRouter
            try? FileManager.default.removeItem(at: harness.tempDir)
        }
        CommandDispatcher.shared.handler = harness.controller
        CommandDispatcher.shared.appCommandRouter = nil

        let parentPane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))

        #expect(CommandDispatcher.shared.canDispatch(.showPaneInboxNotifications))

        CommandDispatcher.shared.dispatch(.showPaneInboxNotifications)

        #expect(harness.paneInboxPresenter.request?.parentPaneId == parentPane.id)
        #expect(harness.paneInboxPresenter.request?.paneIds == [parentPane.id, drawerPane.id])
        #expect(harness.paneInboxPresenter.request?.intent == .open)
    }

    @Test("Cmd-Shift-I app-owned key event reaches PaneInbox command dispatch")
    func cmdShiftIKeyEventOpensPaneInboxForActiveParentScope() throws {
        let harness = makeHarness()
        let previousHandler = CommandDispatcher.shared.handler
        let previousRouter = CommandDispatcher.shared.appCommandRouter
        defer {
            CommandDispatcher.shared.handler = previousHandler
            CommandDispatcher.shared.appCommandRouter = previousRouter
            try? FileManager.default.removeItem(at: harness.tempDir)
        }
        CommandDispatcher.shared.handler = harness.controller
        CommandDispatcher.shared.appCommandRouter = nil

        let parentPane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        let event = try #require(cmdShiftIEvent())

        #expect(harness.controller.handleAppOwnedKeyEvent(event))

        #expect(harness.paneInboxPresenter.request?.parentPaneId == parentPane.id)
        #expect(harness.paneInboxPresenter.request?.paneIds == [parentPane.id, drawerPane.id])
        #expect(harness.paneInboxPresenter.request?.intent == .open)
    }

    private func cmdShiftIEvent() -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "I",
            charactersIgnoringModifiers: "i",
            isARepeat: false,
            keyCode: 34
        )
    }
}
