import AppKit
import Testing

@testable import AgentStudio

@MainActor
@Suite("PaneTabViewController global shortcut routing")
struct PaneTabViewControllerGlobalShortcutRoutingTests {
    @Test("filterSidebar is only handled when the repos sidebar owns focus")
    func filterSidebarRequiresFocusedReposSidebar() {
        #expect(
            !AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(
                .filterSidebar,
                keyboardOwner: .mainWindowChain
            )
        )

        #expect(
            !AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(
                .filterSidebar,
                keyboardOwner: .sidebar(.inbox)
            )
        )

        #expect(
            AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(
                .filterSidebar,
                keyboardOwner: .sidebar(.repos)
            )
        )

        #expect(
            !AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(
                .filterSidebar,
                keyboardOwner: .managementLayer
            )
        )
    }

    @Test("surface switch shortcuts remain globally routable")
    func surfaceSwitchShortcutsRemainGlobal() {
        #expect(
            AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(
                .showInboxNotifications,
                keyboardOwner: .sidebar(.inbox)
            )
        )
        #expect(
            AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(
                .showWorktreeSidebar,
                keyboardOwner: .sidebar(.repos)
            )
        )
    }

    @Test("sidebar focus blocks workspace global shortcuts")
    func sidebarFocusBlocksWorkspaceGlobalShortcuts() {
        for shortcut in [AppShortcut.nextTab, .prevTab, .addDrawerPane, .showPaneInboxNotifications] {
            #expect(
                !AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(
                    shortcut,
                    keyboardOwner: .sidebar(.inbox)
                ),
                "\(shortcut) should not dispatch while inbox owns keyboard focus"
            )
        }
    }

    @Test("production global key path consults keyboard owner policy")
    func productionGlobalKeyPathConsultsKeyboardOwnerPolicy() async throws {
        try await withAsyncTestAtomRegistry { atoms in
            let harness = makeHarness()
            let handler = MockCommandHandler()
            configureMainWindowKeyboardOwner(atoms)
            atoms.uiState.setSidebarCollapsed(false)
            atoms.uiState.setSidebarSurface(.inbox)
            atoms.uiState.setSidebarHasFocus(true)

            let event = try #require(
                makeKeyEvent(
                    modifierFlags: [.command, .option],
                    characters: "l",
                    charactersIgnoringModifiers: "l",
                    keyCode: 37
                )
            )
            let trigger = try #require(ShortcutDecoder.decode(event: event))
            #expect(ShortcutDecoder.shortcut(for: trigger, in: .global) == .nextTab)

            try await withIsolatedCommandDispatcher(
                configure: {
                    CommandDispatcher.shared.handler = handler
                    CommandDispatcher.shared.appCommandRouter = nil
                },
                body: {
                    #expect(!harness.controller.handleAppOwnedKeyEvent(event))
                    #expect(handler.executedCommands.isEmpty)
                }
            )
        }
    }

    @Test("scope-aware pane shortcuts are blocked while sidebar owns keyboard")
    func scopeAwarePaneShortcutsAreBlockedBySidebarOwnership() async throws {
        try await withAsyncTestAtomRegistry { atoms in
            let harness = makeHarness()
            defer { try? FileManager.default.removeItem(at: harness.tempDir) }
            configureMainWindowKeyboardOwner(atoms)
            atoms.uiState.setSidebarSurface(.repos)
            atoms.uiState.setSidebarHasFocus(true)

            let first = harness.store.createPane(source: .floating(launchDirectory: nil, title: "First"))
            let second = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Second"))
            let tab = Tab(paneId: first.id)
            harness.store.appendTab(tab)
            harness.store.insertPane(
                second.id,
                inTab: tab.id,
                at: first.id,
                direction: .horizontal,
                position: .after,
                sizingMode: .halveTarget
            )
            harness.store.setActiveTab(tab.id)
            harness.store.setActivePane(second.id, inTab: tab.id)
            atoms.workspaceFocusOwner.focusMainPane(second.id)

            let event = try #require(
                makeKeyEvent(
                    modifierFlags: [.option],
                    characters: "j",
                    charactersIgnoringModifiers: "j",
                    keyCode: 38
                )
            )

            #expect(!harness.controller.handleAppOwnedKeyEvent(event))
            #expect(harness.store.tab(tab.id)?.activePaneId == second.id)
        }
    }

    @Test("scope-aware pane shortcuts do not steal text input")
    func scopeAwarePaneShortcutsDoNotStealTextInput() async throws {
        try await withAsyncTestAtomRegistry { atoms in
            let harness = makeHarness()
            defer { try? FileManager.default.removeItem(at: harness.tempDir) }
            configureMainWindowKeyboardOwner(atoms)

            let first = harness.store.createPane(source: .floating(launchDirectory: nil, title: "First"))
            let second = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Second"))
            let tab = Tab(paneId: first.id)
            harness.store.appendTab(tab)
            harness.store.insertPane(
                second.id,
                inTab: tab.id,
                at: first.id,
                direction: .horizontal,
                position: .after,
                sizingMode: .halveTarget
            )
            harness.store.setActiveTab(tab.id)
            harness.store.setActivePane(second.id, inTab: tab.id)
            atoms.workspaceFocusOwner.focusMainPane(second.id)

            let window = makePaneTabViewControllerCommandWindow(for: harness.controller)
            let textView = NSTextView()
            window.contentView?.addSubview(textView)
            #expect(window.makeFirstResponder(textView))

            let event = try #require(
                makeKeyEvent(
                    modifierFlags: [.option],
                    characters: "j",
                    charactersIgnoringModifiers: "j",
                    keyCode: 38,
                    windowNumber: window.windowNumber
                )
            )

            #expect(!harness.controller.handleAppOwnedKeyEvent(event))
            #expect(harness.store.tab(tab.id)?.activePaneId == second.id)
        }
    }

    @Test("old tab cycling shortcut is not decoded after migration")
    func oldTabCyclingShortcutIsNotDecodedAfterMigration() {
        let oldNextTabTrigger = ShortcutTrigger(key: .character(.rightBracket), modifiers: [.command, .shift])
        let oldPrevTabTrigger = ShortcutTrigger(key: .character(.leftBracket), modifiers: [.command, .shift])

        #expect(ShortcutDecoder.shortcut(for: oldNextTabTrigger, in: .global) == nil)
        #expect(ShortcutDecoder.shortcut(for: oldPrevTabTrigger, in: .global) == nil)
    }

    @Test("management layer preserves command-modified pass through")
    func managementLayerPreservesCommandModifiedPassThrough() {
        #expect(
            AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(
                .showPaneInboxNotifications,
                keyboardOwner: .managementLayer
            )
        )
    }

    @Test("tab rename transient surface blocks app shortcut dispatch")
    func tabRenameTransientSurfaceBlocksAppShortcutDispatch() {
        let workspaceWindowId = UUID()
        let context = KeyboardRoutingContext(
            stableOwner: .mainWindowChain,
            activeSurface: .transient(.tabRename(tabId: UUID())),
            workspaceWindowId: workspaceWindowId
        )

        for shortcut in AppShortcut.allCases where !AppShortcutDispatchPolicy.isCommandBarActivationShortcut(shortcut) {
            #expect(
                !AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(shortcut, context: context),
                "\(shortcut) should not dispatch while tab rename owns keyboard input"
            )
        }
    }

    @Test("transient surface does not affect another workspace window")
    func transientSurfaceDoesNotAffectAnotherWorkspaceWindow() {
        let context = KeyboardRoutingContext(
            stableOwner: .mainWindowChain,
            activeSurface: .stable(.mainWindowChain),
            workspaceWindowId: UUID()
        )

        #expect(AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(.nextTab, context: context))
    }

    @Test("command bar activation shortcuts are allowed through transient surfaces")
    func commandBarActivationShortcutsAreAllowedThroughTransientSurfaces() {
        let context = KeyboardRoutingContext(
            stableOwner: .managementLayer,
            activeSurface: .transient(.arrangementPanel(tabId: UUID())),
            workspaceWindowId: UUID()
        )

        for shortcut in [
            AppShortcut.newTab,
            .showCommandBarEverything,
            .showCommandBarCommands,
            .showCommandBarPanes,
        ] {
            #expect(
                AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(shortcut, context: context),
                "\(shortcut) should remain reserved for command bar activation"
            )
        }
    }

    @Test("non command bar shortcuts are blocked while command bar owns keyboard")
    func nonCommandBarShortcutsAreBlockedWhileCommandBarOwnsKeyboard() {
        let context = KeyboardRoutingContext(
            stableOwner: .mainWindowChain,
            activeSurface: .commandBar(scope: .everything),
            workspaceWindowId: UUID()
        )

        for shortcut in AppShortcut.allCases where !AppShortcutDispatchPolicy.isCommandBarActivationShortcut(shortcut) {
            #expect(
                !AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(shortcut, context: context),
                "\(shortcut) should not dispatch while command bar owns keyboard input"
            )
        }
    }

    @Test("non command bar shortcuts are blocked while arrangement owns keyboard")
    func nonCommandBarShortcutsAreBlockedWhileArrangementOwnsKeyboard() {
        let context = KeyboardRoutingContext(
            stableOwner: .mainWindowChain,
            activeSurface: .transient(.arrangementPanel(tabId: UUID())),
            workspaceWindowId: UUID()
        )

        for shortcut in AppShortcut.allCases where !AppShortcutDispatchPolicy.isCommandBarActivationShortcut(shortcut) {
            #expect(
                !AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(shortcut, context: context),
                "\(shortcut) should not dispatch while arrangement owns keyboard input"
            )
        }
    }

    @Test("destructive global shortcuts are blocked while transient surfaces own keyboard")
    func destructiveGlobalShortcutsAreBlockedWhileTransientSurfacesOwnKeyboard() {
        let context = KeyboardRoutingContext(
            stableOwner: .mainWindowChain,
            activeSurface: .transient(.editorChooser(paneId: UUID())),
            workspaceWindowId: UUID()
        )

        #expect(!AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(.closeWindow, context: context))
    }

    @Test("production global key path consults transient surface policy")
    func productionGlobalKeyPathConsultsTransientSurfacePolicy() async throws {
        try await withAsyncTestAtomRegistry { atoms in
            let harness = makeHarness()
            let handler = MockCommandHandler()
            configureMainWindowKeyboardOwner(atoms)
            let workspaceWindowId = try #require(atoms.windowLifecycle.focusedWindowId)
            _ = atoms.transientKeyboardSurface.present(
                .tabRename(tabId: UUID()),
                workspaceWindowId: workspaceWindowId
            )

            let event = try #require(
                makeKeyEvent(
                    modifierFlags: [.command, .option],
                    characters: "l",
                    charactersIgnoringModifiers: "l",
                    keyCode: 37
                )
            )
            let trigger = try #require(ShortcutDecoder.decode(event: event))
            #expect(ShortcutDecoder.shortcut(for: trigger, in: .global) == .nextTab)

            try await withIsolatedCommandDispatcher(
                configure: {
                    CommandDispatcher.shared.handler = handler
                    CommandDispatcher.shared.appCommandRouter = nil
                },
                body: {
                    #expect(!harness.controller.handleAppOwnedKeyEvent(event))
                    #expect(handler.executedCommands.isEmpty)
                }
            )
        }
    }

    @Test("transient surface blocks scope-aware pane shortcuts")
    func transientSurfaceBlocksScopeAwarePaneShortcuts() async throws {
        try await withAsyncTestAtomRegistry { atoms in
            let harness = makeHarness()
            defer { try? FileManager.default.removeItem(at: harness.tempDir) }
            configureMainWindowKeyboardOwner(atoms)
            let workspaceWindowId = try #require(atoms.windowLifecycle.focusedWindowId)
            _ = atoms.transientKeyboardSurface.present(
                .tabRename(tabId: UUID()),
                workspaceWindowId: workspaceWindowId
            )

            let first = harness.store.createPane(source: .floating(launchDirectory: nil, title: "First"))
            let second = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Second"))
            let tab = Tab(paneId: first.id)
            harness.store.appendTab(tab)
            harness.store.insertPane(
                second.id,
                inTab: tab.id,
                at: first.id,
                direction: .horizontal,
                position: .after,
                sizingMode: .halveTarget
            )
            harness.store.setActiveTab(tab.id)
            harness.store.setActivePane(second.id, inTab: tab.id)
            atoms.workspaceFocusOwner.focusMainPane(second.id)

            let event = try #require(
                makeKeyEvent(
                    modifierFlags: [.option],
                    characters: "j",
                    charactersIgnoringModifiers: "j",
                    keyCode: 38
                )
            )

            #expect(!harness.controller.handleAppOwnedKeyEvent(event))
            #expect(harness.store.tab(tab.id)?.activePaneId == second.id)
        }
    }
}
