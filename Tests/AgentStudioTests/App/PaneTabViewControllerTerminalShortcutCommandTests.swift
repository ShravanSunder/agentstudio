import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneTabViewControllerTerminalShortcutCommandTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("cmd shift k through controller key path targets focused drawer pane")
    func handleAppOwnedKeyEvent_cmdShiftK_targetsFocusedDrawerPane() async throws {
        try await withAsyncTestAtomRegistry { atoms in
            let harness = makeHarness(windowLifecycleStore: atoms.windowLifecycle)
            defer { try? FileManager.default.removeItem(at: harness.tempDir) }
            configureMainWindowKeyboardOwner(atoms)

            let parentPane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
            let tab = Tab(paneId: parentPane.id)
            harness.store.appendTab(tab)
            harness.store.setActiveTab(tab.id)
            harness.store.setActivePane(parentPane.id, inTab: tab.id)

            let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
            let drawerId = try #require(harness.store.pane(parentPane.id)?.drawer?.drawerId)
            harness.store.tabArrangementAtom.addDrawerPaneView(
                drawerId: drawerId,
                parentPaneId: parentPane.id,
                drawerPaneId: drawerPane.id,
                inTab: tab.id
            )
            harness.store.setActiveDrawerPane(drawerPane.id, in: parentPane.id)
            atoms.workspaceFocusOwner.focusDrawerPane(parentPaneId: parentPane.id, paneId: drawerPane.id)

            let parentRuntime = RecordingCommandPaneRuntime(paneId: PaneId(uuid: parentPane.id))
            let drawerRuntime = RecordingCommandPaneRuntime(paneId: PaneId(uuid: drawerPane.id))
            harness.runtimeRegistry.register(parentRuntime)
            harness.runtimeRegistry.register(drawerRuntime)

            let event = try #require(
                makeKeyEvent(
                    modifierFlags: [.command, .shift],
                    characters: "K",
                    charactersIgnoringModifiers: "k",
                    keyCode: 40
                )
            )

            try await withIsolatedCommandDispatcher(
                configure: {
                    CommandDispatcher.shared.handler = harness.controller
                    CommandDispatcher.shared.appCommandRouter = nil
                },
                body: {
                    #expect(harness.controller.handleAppOwnedKeyEvent(event))
                    await waitForRecordedCommands(on: drawerRuntime, count: 1)
                    #expect(parentRuntime.receivedCommands.isEmpty)
                    let command = try #require(drawerRuntime.receivedCommands.first)
                    #expect(command.targetPaneId == PaneId(uuid: drawerPane.id))
                    guard case .terminal(.scrollToBottom) = command.command else {
                        Issue.record("Expected focused drawer pane to receive scrollToBottom")
                        return
                    }
                }
            )
        }
    }

    @Test("cmd k through controller key path is swallowed")
    func handleAppOwnedKeyEvent_cmdK_swallowsClearScrollback() async throws {
        try await withAsyncTestAtomRegistry { atoms in
            let harness = makeHarness(windowLifecycleStore: atoms.windowLifecycle)
            defer { try? FileManager.default.removeItem(at: harness.tempDir) }
            configureMainWindowKeyboardOwner(atoms)

            let event = try #require(
                makeKeyEvent(
                    modifierFlags: [.command],
                    characters: "k",
                    charactersIgnoringModifiers: "k",
                    keyCode: 40
                )
            )

            try await withIsolatedCommandDispatcher(
                configure: {
                    CommandDispatcher.shared.handler = harness.controller
                    CommandDispatcher.shared.appCommandRouter = nil
                },
                body: {
                    #expect(harness.controller.handleAppOwnedKeyEvent(event))
                }
            )
        }
    }

    @Test("cmd shift k is swallowed when sidebar owns keyboard")
    func handleAppOwnedKeyEvent_cmdShiftK_sidebarFocusSwallowsWithoutDispatch() async throws {
        try await withAsyncTestAtomRegistry { atoms in
            let harness = makeHarness(windowLifecycleStore: atoms.windowLifecycle)
            defer { try? FileManager.default.removeItem(at: harness.tempDir) }
            configureMainWindowKeyboardOwner(atoms)
            atoms.uiState.setSidebarSurface(.inbox)
            atoms.uiState.setSidebarHasFocus(true)

            let pane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Pane"))
            let tab = Tab(paneId: pane.id)
            harness.store.appendTab(tab)
            harness.store.setActiveTab(tab.id)
            harness.store.setActivePane(pane.id, inTab: tab.id)
            atoms.workspaceFocusOwner.focusMainPane(pane.id)

            let runtime = RecordingCommandPaneRuntime(paneId: PaneId(uuid: pane.id))
            harness.runtimeRegistry.register(runtime)

            let event = try #require(
                makeKeyEvent(
                    modifierFlags: [.command, .shift],
                    characters: "K",
                    charactersIgnoringModifiers: "k",
                    keyCode: 40
                )
            )

            try await withIsolatedCommandDispatcher(
                configure: {
                    CommandDispatcher.shared.handler = harness.controller
                    CommandDispatcher.shared.appCommandRouter = nil
                },
                body: {
                    #expect(harness.controller.handleAppOwnedKeyEvent(event))
                    await waitForRecordedCommands(on: runtime, count: 1, maxTurns: 5)
                    #expect(runtime.receivedCommands.isEmpty)
                }
            )
        }
    }

    @Test("cmd shift k is swallowed when focused pane is not terminal")
    func handleAppOwnedKeyEvent_cmdShiftK_nonTerminalPaneSwallowsWithoutDispatch() async throws {
        try await withAsyncTestAtomRegistry { atoms in
            let harness = makeHarness(windowLifecycleStore: atoms.windowLifecycle)
            defer { try? FileManager.default.removeItem(at: harness.tempDir) }
            configureMainWindowKeyboardOwner(atoms)

            let pane = harness.store.createPane(
                content: .webview(WebviewState(url: try #require(URL(string: "https://example.com")))),
                metadata: PaneMetadata(
                    contentType: .browser,
                    source: .floating(launchDirectory: nil, title: "Browser"),
                    title: "Browser"
                )
            )
            let tab = Tab(paneId: pane.id)
            harness.store.appendTab(tab)
            harness.store.setActiveTab(tab.id)
            harness.store.setActivePane(pane.id, inTab: tab.id)
            atoms.workspaceFocusOwner.focusMainPane(pane.id)

            let runtime = RecordingCommandPaneRuntime(paneId: PaneId(uuid: pane.id))
            harness.runtimeRegistry.register(runtime)

            let event = try #require(
                makeKeyEvent(
                    modifierFlags: [.command, .shift],
                    characters: "K",
                    charactersIgnoringModifiers: "k",
                    keyCode: 40
                )
            )

            try await withIsolatedCommandDispatcher(
                configure: {
                    CommandDispatcher.shared.handler = harness.controller
                    CommandDispatcher.shared.appCommandRouter = nil
                },
                body: {
                    #expect(harness.controller.handleAppOwnedKeyEvent(event))
                    await waitForRecordedCommands(on: runtime, count: 1, maxTurns: 5)
                    #expect(runtime.receivedCommands.isEmpty)
                }
            )
        }
    }

    @Test("targeted scrollToBottom targets requested drawer pane")
    func executeTargetedScrollToBottom_targetsRequestedDrawerPane() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        harness.store.setActivePane(parentPane.id, inTab: tab.id)

        let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        let drawerId = try #require(harness.store.pane(parentPane.id)?.drawer?.drawerId)
        harness.store.tabArrangementAtom.addDrawerPaneView(
            drawerId: drawerId,
            parentPaneId: parentPane.id,
            drawerPaneId: drawerPane.id,
            inTab: tab.id
        )
        harness.store.setActiveDrawerPane(drawerPane.id, in: parentPane.id)
        atom(\.workspaceFocusOwner).focusMainPane(parentPane.id)

        let parentRuntime = RecordingCommandPaneRuntime(paneId: PaneId(uuid: parentPane.id))
        let drawerRuntime = RecordingCommandPaneRuntime(paneId: PaneId(uuid: drawerPane.id))
        harness.runtimeRegistry.register(parentRuntime)
        harness.runtimeRegistry.register(drawerRuntime)

        harness.controller.execute(.scrollToBottom, target: drawerPane.id, targetType: .pane)

        await waitForRecordedCommands(on: drawerRuntime, count: 1)
        #expect(parentRuntime.receivedCommands.isEmpty)
        let command = try #require(drawerRuntime.receivedCommands.first)
        #expect(command.targetPaneId == PaneId(uuid: drawerPane.id))
        guard case .terminal(.scrollToBottom) = command.command else {
            Issue.record("Expected targeted drawer pane to receive scrollToBottom")
            return
        }
    }
}
