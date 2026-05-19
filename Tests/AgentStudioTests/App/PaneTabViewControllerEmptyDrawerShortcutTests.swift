import AppKit
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneTabViewControllerEmptyDrawerShortcutTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("p creates first drawer pane while empty drawer has focus")
    func rawP_openEmptyDrawerWithEmptyDrawerFocus_createsFirstDrawerPane() async throws {
        try await withIsolatedCommandDispatcher(
            configure: {},
            body: {
                try withTestAtomRegistry { _ in
                    let harness = makeHarness()
                    defer { try? FileManager.default.removeItem(at: harness.tempDir) }

                    let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
                    let tab = Tab(paneId: parent.id)
                    harness.store.appendTab(tab)
                    harness.store.setActiveTab(tab.id)
                    harness.store.setActivePane(parent.id, inTab: tab.id)
                    harness.store.toggleDrawer(for: parent.id)
                    atom(\.workspaceFocusOwner).focusEmptyDrawer(parentPaneId: parent.id)
                    CommandDispatcher.shared.handler = harness.controller
                    CommandDispatcher.shared.appCommandRouter = nil

                    let event = try #require(rawPEvent(windowNumber: 0))

                    #expect(
                        harness.controller.handleAppOwnedKeyEvent(
                            event,
                            allowsModifiedEmptyDrawerShortcutWithTextFocus: false
                        )
                    )
                    #expect(harness.store.pane(parent.id)?.drawer?.paneIds.count == 1)
                }
            })
    }

    @Test("p creates first drawer pane through targeted command dispatcher")
    func rawP_openEmptyDrawerWithEmptyDrawerFocus_dispatchesTargetedCommand() async throws {
        try await withIsolatedCommandDispatcher(
            configure: {},
            body: {
                try withTestAtomRegistry { _ in
                    let harness = makeHarness()
                    let handler = MockCommandHandler()
                    defer { try? FileManager.default.removeItem(at: harness.tempDir) }

                    let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
                    let tab = Tab(paneId: parent.id)
                    harness.store.appendTab(tab)
                    harness.store.setActiveTab(tab.id)
                    harness.store.setActivePane(parent.id, inTab: tab.id)
                    harness.store.toggleDrawer(for: parent.id)
                    atom(\.workspaceFocusOwner).focusEmptyDrawer(parentPaneId: parent.id)
                    CommandDispatcher.shared.handler = handler
                    CommandDispatcher.shared.appCommandRouter = nil

                    let event = try #require(rawPEvent(windowNumber: 0))

                    #expect(
                        harness.controller.handleAppOwnedKeyEvent(
                            event,
                            allowsModifiedEmptyDrawerShortcutWithTextFocus: false
                        )
                    )
                    #expect(handler.executedCommands.count == 1)
                    #expect(handler.executedCommands.first?.0 == .addDrawerPane)
                    #expect(handler.executedCommands.first?.1 == parent.id)
                    #expect(handler.executedCommands.first?.2 == .pane)
                    #expect(harness.store.pane(parent.id)?.drawer?.paneIds.isEmpty == true)
                }
            })
    }

    @Test("p does not create first drawer pane while text input owns focus")
    func rawP_openEmptyDrawerWithTextInputFocus_fallsThrough() throws {
        try withTestAtomRegistry { _ in
            let harness = makeHarness()
            defer { try? FileManager.default.removeItem(at: harness.tempDir) }

            let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
            let tab = Tab(paneId: parent.id)
            harness.store.appendTab(tab)
            harness.store.setActiveTab(tab.id)
            harness.store.setActivePane(parent.id, inTab: tab.id)
            harness.store.toggleDrawer(for: parent.id)
            atom(\.workspaceFocusOwner).focusEmptyDrawer(parentPaneId: parent.id)

            let window = makePaneTabViewControllerCommandWindow(for: harness.controller)
            let textView = NSTextView()
            window.contentView?.addSubview(textView)
            #expect(window.makeFirstResponder(textView))
            #expect(window.firstResponder === textView)

            let event = try #require(rawPEvent(windowNumber: window.windowNumber))

            #expect(
                !harness.controller.handleAppOwnedKeyEvent(event, allowsModifiedEmptyDrawerShortcutWithTextFocus: false)
            )
            #expect(harness.store.pane(parent.id)?.drawer?.paneIds.isEmpty == true)
        }
    }

    @Test("performKeyEquivalent does not let raw p steal text input focus")
    func performKeyEquivalent_rawPWithTextInputFocus_fallsThrough() throws {
        try withTestAtomRegistry { _ in
            let harness = makeHarness()
            defer { try? FileManager.default.removeItem(at: harness.tempDir) }

            let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
            let tab = Tab(paneId: parent.id)
            harness.store.appendTab(tab)
            harness.store.setActiveTab(tab.id)
            harness.store.setActivePane(parent.id, inTab: tab.id)
            harness.store.toggleDrawer(for: parent.id)
            atom(\.workspaceFocusOwner).focusEmptyDrawer(parentPaneId: parent.id)

            let window = makePaneTabViewControllerCommandWindow(for: harness.controller)
            let textView = NSTextView()
            window.contentView?.addSubview(textView)
            #expect(window.makeFirstResponder(textView))
            #expect(window.firstResponder === textView)

            let event = try #require(rawPEvent(windowNumber: window.windowNumber))

            #expect(!harness.controller.performKeyEquivalent(with: event))
            #expect(harness.store.pane(parent.id)?.drawer?.paneIds.isEmpty == true)
        }
    }

    @Test("performKeyEquivalent lets cmd-shift-D create drawer pane while text input owns focus")
    func performKeyEquivalent_cmdShiftDWithTextInputFocus_createsFirstDrawerPane() async throws {
        try await withIsolatedCommandDispatcher(
            configure: {},
            body: {
                try withTestAtomRegistry { _ in
                    let harness = makeHarness()
                    defer { try? FileManager.default.removeItem(at: harness.tempDir) }

                    let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
                    let tab = Tab(paneId: parent.id)
                    harness.store.appendTab(tab)
                    harness.store.setActiveTab(tab.id)
                    harness.store.setActivePane(parent.id, inTab: tab.id)
                    harness.store.toggleDrawer(for: parent.id)
                    atom(\.workspaceFocusOwner).focusEmptyDrawer(parentPaneId: parent.id)
                    CommandDispatcher.shared.handler = harness.controller
                    CommandDispatcher.shared.appCommandRouter = nil

                    let window = makePaneTabViewControllerCommandWindow(for: harness.controller)
                    let textView = NSTextView()
                    window.contentView?.addSubview(textView)
                    #expect(window.makeFirstResponder(textView))
                    #expect(window.firstResponder === textView)

                    let event = try #require(
                        NSEvent.keyEvent(
                            with: .keyDown,
                            location: .zero,
                            modifierFlags: [.command, .shift],
                            timestamp: 0,
                            windowNumber: window.windowNumber,
                            context: nil,
                            characters: "D",
                            charactersIgnoringModifiers: "d",
                            isARepeat: false,
                            keyCode: 2
                        )
                    )

                    #expect(harness.controller.performKeyEquivalent(with: event))
                    #expect(harness.store.pane(parent.id)?.drawer?.paneIds.count == 1)
                }
            })
    }

    @Test("p creating the first drawer pane upgrades canonical focus owner to that drawer pane")
    func rawP_openEmptyDrawerWithEmptyDrawerFocus_updatesFocusOwnerToDrawerPane() async throws {
        try await withIsolatedCommandDispatcher(
            configure: {},
            body: {
                try withTestAtomRegistry { _ in
                    let harness = makeHarness()
                    defer { try? FileManager.default.removeItem(at: harness.tempDir) }

                    let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
                    let tab = Tab(paneId: parent.id)
                    harness.store.appendTab(tab)
                    harness.store.setActiveTab(tab.id)
                    harness.store.setActivePane(parent.id, inTab: tab.id)
                    harness.store.toggleDrawer(for: parent.id)
                    atom(\.workspaceFocusOwner).focusEmptyDrawer(parentPaneId: parent.id)
                    CommandDispatcher.shared.handler = harness.controller
                    CommandDispatcher.shared.appCommandRouter = nil

                    let event = try #require(rawPEvent(windowNumber: 0))

                    #expect(
                        harness.controller.handleAppOwnedKeyEvent(
                            event,
                            allowsModifiedEmptyDrawerShortcutWithTextFocus: false
                        )
                    )

                    let firstDrawerPaneId = try #require(harness.store.pane(parent.id)?.drawer?.activeChildId)
                    #expect(
                        atom(\.workspaceFocusOwner).owner
                            == .drawerPane(parentPaneId: parent.id, paneId: firstDrawerPaneId))
                }
            })
    }

    private func rawPEvent(windowNumber: Int) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            characters: "p",
            charactersIgnoringModifiers: "p",
            isARepeat: false,
            keyCode: 35
        )
    }
}
