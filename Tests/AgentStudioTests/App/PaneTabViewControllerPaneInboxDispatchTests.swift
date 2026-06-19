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
    func dispatcherShowPaneInboxNotificationsOpensActiveParentScope() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        try await withIsolatedCommandDispatcher(
            configure: {
                AppCommandDispatcher.shared.handler = harness.controller
                AppCommandDispatcher.shared.appCommandRouter = nil
            },
            body: {
                let parentPane = harness.store.createPane()
                let tab = Tab(paneId: parentPane.id)
                harness.store.appendTab(tab)
                harness.store.setActiveTab(tab.id)
                let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))

                #expect(AppCommandDispatcher.shared.canDispatch(.showPaneInboxNotifications))

                AppCommandDispatcher.shared.dispatch(.showPaneInboxNotifications)

                #expect(harness.paneInboxPresenter.request?.parentPaneId == parentPane.id)
                #expect(harness.paneInboxPresenter.request?.paneIds == [parentPane.id, drawerPane.id])
                #expect(harness.paneInboxPresenter.request?.intent == .open)
            }
        )
    }

    @Test("Cmd-Shift-U app-owned key event reaches PaneInbox command dispatch")
    func cmdShiftUKeyEventOpensPaneInboxForActiveParentScope() async throws {
        try await withAsyncTestAtomRegistry { atoms in
            let harness = makeHarness(windowLifecycleStore: atoms.windowLifecycle)
            defer { try? FileManager.default.removeItem(at: harness.tempDir) }
            configureMainWindowKeyboardOwner(atoms)

            try await withIsolatedCommandDispatcher(
                configure: {
                    AppCommandDispatcher.shared.handler = harness.controller
                    AppCommandDispatcher.shared.appCommandRouter = nil
                },
                body: {
                    let parentPane = harness.store.createPane()
                    let tab = Tab(paneId: parentPane.id)
                    harness.store.appendTab(tab)
                    harness.store.setActiveTab(tab.id)
                    let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
                    let event = try #require(cmdShiftUEvent())

                    #expect(harness.controller.handleAppOwnedKeyEvent(event))

                    #expect(harness.paneInboxPresenter.request?.parentPaneId == parentPane.id)
                    #expect(harness.paneInboxPresenter.request?.paneIds == [parentPane.id, drawerPane.id])
                    #expect(harness.paneInboxPresenter.request?.intent == .open)
                }
            )
        }
    }

    private func cmdShiftUEvent() -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "U",
            charactersIgnoringModifiers: "u",
            isARepeat: false,
            keyCode: 32
        )
    }
}
