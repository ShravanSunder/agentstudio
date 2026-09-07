import AppKit
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct PaneTabViewControllerDrawerCommandTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("toggleDrawer opening an empty drawer sets empty drawer focus")
    func executeToggleDrawer_openEmptyDrawer_setsEmptyDrawerFocus() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        try await withWorkspaceCommandHarness(harness) {
            let parent = harness.store.createPane()
            let tab = Tab(paneId: parent.id)
            harness.store.appendTab(tab)
            harness.store.setActiveTab(tab.id)
            harness.store.setActivePane(parent.id, inTab: tab.id)
            atom(\.workspaceFocusOwner).focusMainPane(parent.id)

            await harness.executeCommand(.toggleDrawer)

            #expect(atom(\.workspaceFocusOwner).owner == .emptyDrawer(parentPaneId: parent.id))

        }
    }

    @Test("toggleDrawer reopening a drawer with an active pane restores drawer pane focus")
    func executeToggleDrawer_reopenDrawerWithActivePane_setsDrawerPaneFocus() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        try await withWorkspaceCommandHarness(harness) {
            let parent = harness.store.createPane()
            let tab = Tab(paneId: parent.id)
            harness.store.appendTab(tab)
            harness.store.setActiveTab(tab.id)
            harness.store.setActivePane(parent.id, inTab: tab.id)
            let drawerPane = try #require(harness.store.addDrawerPane(to: parent.id))

            await harness.executeCommand(.toggleDrawer)
            await harness.executeCommand(.toggleDrawer)

            #expect(atom(\.workspaceFocusOwner).owner == .drawerPane(parentPaneId: parent.id, paneId: drawerPane.id))

        }
    }

    @Test("toggleDrawer opening an empty drawer clears responder to window content")
    func executeToggleDrawer_openEmptyDrawer_clearsResponderToWindowContent() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        try await withWorkspaceCommandHarness(harness) {
            let parent = harness.store.createPane()
            let tab = Tab(paneId: parent.id)
            harness.store.appendTab(tab)
            harness.store.setActiveTab(tab.id)
            harness.store.setActivePane(parent.id, inTab: tab.id)

            let window = makePaneTabViewControllerCommandWindow(for: harness.controller)
            let mountedContent = FocusablePaneTabCommandMountedContentView()
            _ = try attachPaneHost(
                paneId: parent.id,
                in: harness,
                to: window,
                mountedContent: mountedContent
            )
            window.makeFirstResponder(mountedContent)

            await harness.executeCommand(.toggleDrawer)

            #expect(atom(\.workspaceFocusOwner).owner == .emptyDrawer(parentPaneId: parent.id))
            #expect(window.firstResponder === window.contentView)

        }
    }

    @Test("toggleDrawer closing the drawer restores main pane responder")
    func executeToggleDrawer_closeDrawer_restoresMainPaneResponder() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        try await withWorkspaceCommandHarness(harness) {
            let parent = harness.store.createPane()
            let tab = Tab(paneId: parent.id)
            harness.store.appendTab(tab)
            harness.store.setActiveTab(tab.id)
            harness.store.setActivePane(parent.id, inTab: tab.id)

            let window = makePaneTabViewControllerCommandWindow(for: harness.controller)
            let mountedContent = FocusablePaneTabCommandMountedContentView()
            let parentHost = try attachPaneHost(
                paneId: parent.id,
                in: harness,
                to: window,
                mountedContent: mountedContent
            )

            await harness.executeCommand(.toggleDrawer)
            await harness.executeCommand(.toggleDrawer)

            #expect(atom(\.workspaceFocusOwner).owner == .mainPane(paneId: parent.id))
            #expect(window.firstResponder === mountedContent || window.firstResponder === parentHost)

        }
    }

    @Test("enterDrawer focuses active drawer pane when drawer has panes")
    func executeEnterDrawer_focusesActiveDrawerPane() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        try await withWorkspaceCommandHarness(harness) {
            let parent = harness.store.createPane()
            let tab = Tab(paneId: parent.id)
            harness.store.appendTab(tab)
            harness.store.setActiveTab(tab.id)
            let drawerPane = try #require(harness.store.addDrawerPane(to: parent.id))

            await harness.executeCommand(.enterDrawer)

            #expect(harness.store.drawerView(forParent: parent.id)?.activeChildId == drawerPane.id)

        }
    }

    @Test("enterDrawer on an expanded empty drawer switches to empty drawer focus")
    func executeEnterDrawer_emptyDrawer_projectsEmptyDrawerFocus() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        try await withWorkspaceCommandHarness(harness) {
            let parent = harness.store.createPane()
            let tab = Tab(paneId: parent.id)
            harness.store.appendTab(tab)
            harness.store.setActiveTab(tab.id)
            harness.store.setActivePane(parent.id, inTab: tab.id)
            harness.store.toggleDrawer(for: parent.id)

            await harness.executeCommand(.enterDrawer)

            #expect(atom(\.workspaceFocusOwner).owner == .emptyDrawer(parentPaneId: parent.id))

        }
    }

    @Test("enterDrawer on an expanded empty drawer clears the responder to window content")
    func executeEnterDrawer_emptyDrawer_clearsResponderToWindowContent() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        try await withWorkspaceCommandHarness(harness) {
            let parent = harness.store.createPane()
            let tab = Tab(paneId: parent.id)
            harness.store.appendTab(tab)
            harness.store.setActiveTab(tab.id)
            harness.store.setActivePane(parent.id, inTab: tab.id)
            harness.store.toggleDrawer(for: parent.id)

            let window = makePaneTabViewControllerCommandWindow(for: harness.controller)
            let mountedContent = FocusablePaneTabCommandMountedContentView()
            _ = try attachPaneHost(
                paneId: parent.id,
                in: harness,
                to: window,
                mountedContent: mountedContent
            )
            window.makeFirstResponder(mountedContent)

            await harness.executeCommand(.enterDrawer)

            #expect(atom(\.workspaceFocusOwner).owner == .emptyDrawer(parentPaneId: parent.id))
            #expect(window.firstResponder === window.contentView)

        }
    }

    @Test("drawer toggle focus trigger preserves empty drawer responder ownership after click open")
    func drawerToggleTrigger_openEmptyDrawer_keepsWindowContentResponder() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        try await withWorkspaceCommandHarness(harness) {
            let parent = harness.store.createPane()
            let tab = Tab(paneId: parent.id)
            harness.store.appendTab(tab)
            harness.store.setActiveTab(tab.id)
            harness.store.setActivePane(parent.id, inTab: tab.id)

            let window = makePaneTabViewControllerCommandWindow(for: harness.controller)
            let mountedContent = FocusablePaneTabCommandMountedContentView()
            _ = try attachPaneHost(
                paneId: parent.id,
                in: harness,
                to: window,
                mountedContent: mountedContent
            )

            harness.store.toggleDrawer(for: parent.id)
            atom(\.workspaceFocusOwner).focusEmptyDrawer(parentPaneId: parent.id)
            window.makeFirstResponder(window.contentView)

            harness.controller.handlePaneFocusTrigger(.drawer(.toggle(parentPaneId: parent.id)))

            #expect(window.firstResponder === window.contentView)

        }
    }

    @Test("addDrawerPane command upgrades focus owner to the new drawer pane")
    func executeAddDrawerPane_updatesFocusOwnerToDrawerPane() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        try await withWorkspaceCommandHarness(harness) {
            let parent = harness.store.createPane()
            let tab = Tab(paneId: parent.id)
            harness.store.appendTab(tab)
            harness.store.setActiveTab(tab.id)
            harness.store.setActivePane(parent.id, inTab: tab.id)
            harness.store.toggleDrawer(for: parent.id)
            atom(\.workspaceFocusOwner).focusEmptyDrawer(parentPaneId: parent.id)

            await harness.executeCommand(.addDrawerPane)

            let firstDrawerPaneId = try #require(harness.store.drawerView(forParent: parent.id)?.activeChildId)
            #expect(
                atom(\.workspaceFocusOwner).owner == .drawerPane(parentPaneId: parent.id, paneId: firstDrawerPaneId))

        }
    }

    @Test("closeDrawerPane command routes through closePane and creates pane undo")
    func executeCloseDrawerPane_routesThroughClosePaneUndo() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        try await withWorkspaceCommandHarness(harness) {
            let parent = harness.store.createPane()
            let tab = Tab(paneId: parent.id)
            harness.store.appendTab(tab)
            harness.store.setActiveTab(tab.id)
            harness.store.setActivePane(parent.id, inTab: tab.id)
            let drawerPane = try #require(harness.store.addDrawerPane(to: parent.id))
            harness.store.setActiveDrawerPane(drawerPane.id, in: parent.id)

            await harness.executeCommand(.closeDrawerPane)

            #expect(harness.store.pane(parent.id)?.drawer?.paneIds.contains(drawerPane.id) == false)
            guard case .pane(let snapshot)? = harness.coordinator.undoStack.last else {
                Issue.record("Expected drawer close to produce pane undo snapshot")
                return
            }
            #expect(snapshot.pane.id == drawerPane.id)

        }
    }

    @Test("option-j from empty drawer focus falls through instead of being consumed")
    func optionJ_emptyDrawerFocus_fallsThrough() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        try await withWorkspaceCommandHarness(harness) {
            let left = harness.store.createPane()
            let parent = harness.store.createPane()
            let tab = Tab(paneId: left.id)
            harness.store.appendTab(tab)
            harness.store.insertPane(
                parent.id, inTab: tab.id, at: left.id, direction: .horizontal, position: .after,
                sizingMode: .halveTarget)
            harness.store.setActiveTab(tab.id)
            harness.store.setActivePane(parent.id, inTab: tab.id)
            harness.store.toggleDrawer(for: parent.id)
            atom(\.workspaceFocusOwner).focusEmptyDrawer(parentPaneId: parent.id)

            let event = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [.option],
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: "j",
                    charactersIgnoringModifiers: "j",
                    isARepeat: false,
                    keyCode: 38
                )
            )

            #expect(
                !harness.controller.handleAppOwnedKeyEvent(event, allowsModifiedEmptyDrawerShortcutWithTextFocus: false)
            )
            #expect(harness.store.tab(tab.id)?.activePaneId == parent.id)

        }
    }

    @Test("option-k in main row is swallowed without a concrete pane command")
    func optionK_mainPane_isSwallowedWithoutConcreteCommand() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        try await withWorkspaceCommandHarness(harness) {
            configureMainWindowKeyboardOwner(windowLifecycleStore: harness.windowLifecycleStore)

            let parent = harness.store.createPane()
            let tab = Tab(paneId: parent.id)
            harness.store.appendTab(tab)
            harness.store.setActiveTab(tab.id)
            harness.store.setActivePane(parent.id, inTab: tab.id)
            atom(\.workspaceFocusOwner).focusMainPane(parent.id)

            let event = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [.option],
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: "k",
                    charactersIgnoringModifiers: "k",
                    isARepeat: false,
                    keyCode: 40
                )
            )

            #expect(
                harness.controller.handleAppOwnedKeyEvent(event, allowsModifiedEmptyDrawerShortcutWithTextFocus: false))
            #expect(harness.store.pane(parent.id)?.drawer?.isExpanded == false)
            #expect(atom(\.workspaceFocusOwner).owner == .mainPane(paneId: parent.id))

        }
    }

    @Test("option-i in main row is swallowed without a concrete pane command")
    func optionI_mainPane_isSwallowedWithoutConcreteCommand() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        try await withWorkspaceCommandHarness(harness) {
            configureMainWindowKeyboardOwner(windowLifecycleStore: harness.windowLifecycleStore)

            let parent = harness.store.createPane()
            let tab = Tab(paneId: parent.id)
            harness.store.appendTab(tab)
            harness.store.setActiveTab(tab.id)
            harness.store.setActivePane(parent.id, inTab: tab.id)
            atom(\.workspaceFocusOwner).focusMainPane(parent.id)

            let event = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [.option],
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: "i",
                    charactersIgnoringModifiers: "i",
                    isARepeat: false,
                    keyCode: 34
                )
            )

            #expect(
                harness.controller.handleAppOwnedKeyEvent(event, allowsModifiedEmptyDrawerShortcutWithTextFocus: false))
            #expect(atom(\.workspaceFocusOwner).owner == .mainPane(paneId: parent.id))

        }
    }

    @Test("option-j returns to main-row movement after an empty drawer is dismissed")
    func optionJ_afterClosingEmptyDrawer_movesMainRow() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        try await withWorkspaceCommandHarness(harness) {
            configureMainWindowKeyboardOwner(windowLifecycleStore: harness.windowLifecycleStore)

            let left = harness.store.createPane()
            let parent = harness.store.createPane()
            let tab = Tab(paneId: left.id)
            harness.store.appendTab(tab)
            harness.store.insertPane(
                parent.id, inTab: tab.id, at: left.id, direction: .horizontal, position: .after,
                sizingMode: .halveTarget)
            harness.store.setActiveTab(tab.id)
            harness.store.setActivePane(parent.id, inTab: tab.id)
            harness.store.toggleDrawer(for: parent.id)
            atom(\.workspaceFocusOwner).focusEmptyDrawer(parentPaneId: parent.id)
            harness.store.toggleDrawer(for: parent.id)

            let event = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [.option],
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: "j",
                    charactersIgnoringModifiers: "j",
                    isARepeat: false,
                    keyCode: 38
                )
            )

            #expect(
                harness.controller.handleAppOwnedKeyEvent(event, allowsModifiedEmptyDrawerShortcutWithTextFocus: false))
            #expect(harness.store.tab(tab.id)?.activePaneId == left.id)

        }
    }

    @Test("focusDrawerPaneDown is a no-op when no drawer neighbor exists")
    func executeFocusDrawerPaneDown_withoutNeighbor_keepsSelection() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        try await withWorkspaceCommandHarness(harness) {
            let parent = harness.store.createPane()
            let tab = Tab(paneId: parent.id)
            harness.store.appendTab(tab)
            harness.store.setActiveTab(tab.id)
            let drawerPane = try #require(harness.store.addDrawerPane(to: parent.id))
            harness.store.setActiveDrawerPane(drawerPane.id, in: parent.id)

            await harness.executeCommand(.focusDrawerPaneDown)

            #expect(harness.store.drawerView(forParent: parent.id)?.activeChildId == drawerPane.id)

        }
    }

    @Test("focusDrawerPane1 focuses first drawer pane by drawer layout order")
    func executeFocusDrawerPane1_focusesFirstDrawerPaneByLayoutOrder() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        try await withWorkspaceCommandHarness(harness) {
            let (parent, drawerPanes) = try makeDrawerOrdinalPaneSet(in: harness, paneCount: 3)
            harness.store.setActiveDrawerPane(drawerPanes[2].id, in: parent.id)
            atom(\.workspaceFocusOwner).focusDrawerPane(parentPaneId: parent.id, paneId: drawerPanes[2].id)

            await harness.executeCommand(.focusDrawerPane1)

            #expect(harness.store.drawerView(forParent: parent.id)?.activeChildId == drawerPanes[0].id)
            #expect(
                atom(\.workspaceFocusOwner).owner == .drawerPane(parentPaneId: parent.id, paneId: drawerPanes[0].id))

        }
    }

    @Test("out-of-range focusDrawerPane ordinal is unavailable and no-ops")
    func executeFocusDrawerPane4_outOfRangeIsUnavailableAndNoOps() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        try await withWorkspaceCommandHarness(harness) {
            let (parent, drawerPanes) = try makeDrawerOrdinalPaneSet(in: harness, paneCount: 3)

            #expect(harness.controller.canExecute(.focusDrawerPane4) == false)

            await harness.executeCommand(.focusDrawerPane4)

            #expect(harness.store.drawerView(forParent: parent.id)?.activeChildId == drawerPanes[0].id)

        }
    }

    @Test("focusDrawerPane ordinal expands collapsed and minimized target before focusing")
    func executeFocusDrawerPane2_expandsCollapsedAndMinimizedTargetBeforeFocusing() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        try await withWorkspaceCommandHarness(harness) {
            let (parent, drawerPanes) = try makeDrawerOrdinalPaneSet(in: harness, paneCount: 3)
            harness.store.toggleDrawer(for: parent.id)
            #expect(harness.store.minimizeDrawerPane(drawerPanes[1].id, in: parent.id))

            await harness.executeCommand(.focusDrawerPane2)

            let updatedDrawer = try #require(harness.store.pane(parent.id)?.drawer)
            let updatedDrawerView = try #require(harness.store.drawerView(forParent: parent.id))
            #expect(updatedDrawer.isExpanded)
            #expect(!updatedDrawerView.minimizedPaneIds.contains(drawerPanes[1].id))
            #expect(updatedDrawerView.activeChildId == drawerPanes[1].id)
            #expect(
                atom(\.workspaceFocusOwner).owner == .drawerPane(parentPaneId: parent.id, paneId: drawerPanes[1].id))

        }
    }

    @Test("option-ijkl uses drawer movement after selecting a drawer pane directly")
    func optionIJKL_afterDirectDrawerSelection_staysInDrawerScope() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        try await withWorkspaceCommandHarness(harness) {
            configureMainWindowKeyboardOwner(windowLifecycleStore: harness.windowLifecycleStore)

            let left = harness.store.createPane()
            let parent = harness.store.createPane()
            let tab = Tab(paneId: left.id)
            harness.store.appendTab(tab)
            harness.store.insertPane(
                parent.id, inTab: tab.id, at: left.id, direction: .horizontal, position: .after,
                sizingMode: .halveTarget)
            harness.store.setActiveTab(tab.id)
            harness.store.setActivePane(parent.id, inTab: tab.id)

            let firstDrawerPane = try #require(harness.store.addDrawerPane(to: parent.id))
            let secondDrawerPane = try #require(
                harness.store.insertDrawerPane(
                    in: parent.id,
                    at: firstDrawerPane.id,
                    direction: .horizontal,
                    position: .after, sizingMode: .halveTarget
                )
            )

            harness.controller.handlePaneFocusTrigger(
                .drawer(.selectPane(parentPaneId: parent.id, drawerPaneId: secondDrawerPane.id))
            )

            let event = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [.option],
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: "j",
                    charactersIgnoringModifiers: "j",
                    isARepeat: false,
                    keyCode: 38
                )
            )

            #expect(
                harness.controller.handleAppOwnedKeyEvent(event, allowsModifiedEmptyDrawerShortcutWithTextFocus: false))
            #expect(harness.store.drawerView(forParent: parent.id)?.activeChildId == firstDrawerPane.id)
            #expect(harness.store.tab(tab.id)?.activePaneId == parent.id)

        }
    }

    @Test("navigateDrawerPane targeted command updates canonical focus owner and keeps option-j in drawer scope")
    func targetedNavigateDrawerPane_updatesFocusOwnerAndDrawerKeyboardScope() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        try await withWorkspaceCommandHarness(harness) {
            configureMainWindowKeyboardOwner(windowLifecycleStore: harness.windowLifecycleStore)

            let left = harness.store.createPane()
            let parent = harness.store.createPane()
            let tab = Tab(paneId: left.id)
            harness.store.appendTab(tab)
            harness.store.insertPane(
                parent.id, inTab: tab.id, at: left.id, direction: .horizontal, position: .after,
                sizingMode: .halveTarget)
            harness.store.setActiveTab(tab.id)
            harness.store.setActivePane(parent.id, inTab: tab.id)

            let firstDrawerPane = try #require(harness.store.addDrawerPane(to: parent.id))
            let secondDrawerPane = try #require(
                harness.store.insertDrawerPane(
                    in: parent.id,
                    at: firstDrawerPane.id,
                    direction: .horizontal,
                    position: .after, sizingMode: .halveTarget
                )
            )
            atom(\.workspaceFocusOwner).focusEmptyDrawer(parentPaneId: parent.id)

            await harness.executeCommand(.navigateDrawerPane, target: secondDrawerPane.id, targetType: .pane)

            #expect(
                atom(\.workspaceFocusOwner).owner == .drawerPane(parentPaneId: parent.id, paneId: secondDrawerPane.id))

            let event = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [.option],
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: "j",
                    charactersIgnoringModifiers: "j",
                    isARepeat: false,
                    keyCode: 38
                )
            )

            #expect(
                harness.controller.handleAppOwnedKeyEvent(event, allowsModifiedEmptyDrawerShortcutWithTextFocus: false))
            #expect(harness.store.drawerView(forParent: parent.id)?.activeChildId == firstDrawerPane.id)
            #expect(harness.store.tab(tab.id)?.activePaneId == parent.id)

        }
    }

}
