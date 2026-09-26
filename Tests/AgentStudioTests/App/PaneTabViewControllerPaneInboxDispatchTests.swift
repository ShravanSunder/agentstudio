import AppKit
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite("PaneTabViewController PaneInbox dispatch", .serialized)
struct PaneTabViewControllerPaneInboxDispatchTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("retired Cmd-Shift-U shortcut does not dispatch PaneInbox")
    func retiredCmdShiftUKeyEventDoesNotOpenPaneInbox() async throws {
        try await withAsyncTestCoreAtoms { atoms in
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
                    _ = try #require(harness.store.addDrawerPane(to: parentPane.id))
                    let event = try #require(cmdShiftUEvent())

                    #expect(!harness.controller.handleAppOwnedKeyEvent(event))
                    #expect(harness.paneInboxPresenter.request == nil)
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
