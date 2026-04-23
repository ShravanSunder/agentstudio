import AppKit
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneTabViewControllerDrawerCommandTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("toggleDrawer opening an empty drawer sets empty drawer focus")
    func executeToggleDrawer_openEmptyDrawer_setsEmptyDrawerFocus() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
        let tab = Tab(paneId: parent.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        harness.store.setActivePane(parent.id, inTab: tab.id)
        atom(\.workspaceFocusOwner).focusMainPane(parent.id)

        harness.controller.execute(.toggleDrawer)

        #expect(atom(\.workspaceFocusOwner).owner == .emptyDrawer(parentPaneId: parent.id))
    }

    @Test("toggleDrawer reopening a drawer with an active pane restores drawer pane focus")
    func executeToggleDrawer_reopenDrawerWithActivePane_setsDrawerPaneFocus() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
        let tab = Tab(paneId: parent.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        harness.store.setActivePane(parent.id, inTab: tab.id)
        let drawerPane = try #require(harness.store.addDrawerPane(to: parent.id))

        harness.controller.execute(.toggleDrawer)
        harness.controller.execute(.toggleDrawer)

        #expect(atom(\.workspaceFocusOwner).owner == .drawerPane(parentPaneId: parent.id, paneId: drawerPane.id))
    }

    @Test("toggleDrawer opening an empty drawer clears responder to window content")
    func executeToggleDrawer_openEmptyDrawer_clearsResponderToWindowContent() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
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

        harness.controller.execute(.toggleDrawer)

        #expect(atom(\.workspaceFocusOwner).owner == .emptyDrawer(parentPaneId: parent.id))
        #expect(window.firstResponder === window.contentView)
    }

    @Test("toggleDrawer closing the drawer restores main pane responder")
    func executeToggleDrawer_closeDrawer_restoresMainPaneResponder() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
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

        harness.controller.execute(.toggleDrawer)
        harness.controller.execute(.toggleDrawer)

        #expect(atom(\.workspaceFocusOwner).owner == .mainPane(paneId: parent.id))
        #expect(window.firstResponder === mountedContent || window.firstResponder === parentHost)
    }

    @Test("enterDrawer focuses active drawer pane when drawer has panes")
    func executeEnterDrawer_focusesActiveDrawerPane() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
        let tab = Tab(paneId: parent.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let drawerPane = try #require(harness.store.addDrawerPane(to: parent.id))

        harness.controller.execute(.enterDrawer)

        #expect(harness.store.pane(parent.id)?.drawer?.activePaneId == drawerPane.id)
    }

    @Test("enterDrawer on an expanded empty drawer switches to empty drawer focus")
    func executeEnterDrawer_emptyDrawer_projectsEmptyDrawerFocus() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
        let tab = Tab(paneId: parent.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        harness.store.setActivePane(parent.id, inTab: tab.id)
        harness.store.toggleDrawer(for: parent.id)

        harness.controller.execute(.enterDrawer)

        #expect(atom(\.workspaceFocusOwner).owner == .emptyDrawer(parentPaneId: parent.id))
    }

    @Test("enterDrawer on an expanded empty drawer clears the responder to window content")
    func executeEnterDrawer_emptyDrawer_clearsResponderToWindowContent() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
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

        harness.controller.execute(.enterDrawer)

        #expect(atom(\.workspaceFocusOwner).owner == .emptyDrawer(parentPaneId: parent.id))
        #expect(window.firstResponder === window.contentView)
    }

    @Test("drawer toggle focus trigger preserves empty drawer responder ownership after click open")
    func drawerToggleTrigger_openEmptyDrawer_keepsWindowContentResponder() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
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

    @Test("d creates first drawer pane while empty drawer has focus")
    func rawD_openEmptyDrawerWithEmptyDrawerFocus_createsFirstDrawerPane() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
        let tab = Tab(paneId: parent.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        harness.store.setActivePane(parent.id, inTab: tab.id)
        harness.store.toggleDrawer(for: parent.id)
        atom(\.workspaceFocusOwner).focusEmptyDrawer(parentPaneId: parent.id)

        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "d",
                charactersIgnoringModifiers: "d",
                isARepeat: false,
                keyCode: 2
            )
        )

        #expect(harness.controller.handleAppOwnedKeyEvent(event, requiresNeutralDrawerFocus: false))
        #expect(harness.store.pane(parent.id)?.drawer?.paneIds.count == 1)
    }

    @Test("d creating the first drawer pane upgrades canonical focus owner to that drawer pane")
    func rawD_openEmptyDrawerWithEmptyDrawerFocus_updatesFocusOwnerToDrawerPane() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
        let tab = Tab(paneId: parent.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        harness.store.setActivePane(parent.id, inTab: tab.id)
        harness.store.toggleDrawer(for: parent.id)
        atom(\.workspaceFocusOwner).focusEmptyDrawer(parentPaneId: parent.id)

        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "d",
                charactersIgnoringModifiers: "d",
                isARepeat: false,
                keyCode: 2
            )
        )

        #expect(harness.controller.handleAppOwnedKeyEvent(event, requiresNeutralDrawerFocus: false))

        let firstDrawerPaneId = try #require(harness.store.pane(parent.id)?.drawer?.activePaneId)
        #expect(atom(\.workspaceFocusOwner).owner == .drawerPane(parentPaneId: parent.id, paneId: firstDrawerPaneId))
    }

    @Test("addDrawerPane command upgrades focus owner to the new drawer pane")
    func executeAddDrawerPane_updatesFocusOwnerToDrawerPane() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
        let tab = Tab(paneId: parent.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        harness.store.setActivePane(parent.id, inTab: tab.id)
        harness.store.toggleDrawer(for: parent.id)
        atom(\.workspaceFocusOwner).focusEmptyDrawer(parentPaneId: parent.id)

        harness.controller.execute(.addDrawerPane)

        let firstDrawerPaneId = try #require(harness.store.pane(parent.id)?.drawer?.activePaneId)
        #expect(atom(\.workspaceFocusOwner).owner == .drawerPane(parentPaneId: parent.id, paneId: firstDrawerPaneId))
    }

    @Test("option-j from empty drawer focus falls through instead of being consumed")
    func optionJ_emptyDrawerFocus_fallsThrough() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let left = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Left"))
        let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
        let tab = Tab(paneId: left.id)
        harness.store.appendTab(tab)
        harness.store.insertPane(
            parent.id, inTab: tab.id, at: left.id, direction: .horizontal, position: .after, sizingMode: .halveTarget)
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

        #expect(!harness.controller.handleAppOwnedKeyEvent(event, requiresNeutralDrawerFocus: false))
        #expect(harness.store.tab(tab.id)?.activePaneId == parent.id)
    }

    @Test("option-k in main row is consumed without opening the drawer")
    func optionK_mainPane_isConsumedWithoutEnteringDrawer() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
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

        #expect(harness.controller.handleAppOwnedKeyEvent(event, requiresNeutralDrawerFocus: false))
        #expect(harness.store.pane(parent.id)?.drawer?.isExpanded == false)
        #expect(atom(\.workspaceFocusOwner).owner == .mainPane(paneId: parent.id))
    }

    @Test("option-i in main row is consumed without app-owned navigation")
    func optionI_mainPane_isConsumedWithoutNavigation() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
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

        #expect(harness.controller.handleAppOwnedKeyEvent(event, requiresNeutralDrawerFocus: false))
        #expect(atom(\.workspaceFocusOwner).owner == .mainPane(paneId: parent.id))
    }

    @Test("option-j returns to main-row movement after an empty drawer is dismissed")
    func optionJ_afterClosingEmptyDrawer_movesMainRow() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let left = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Left"))
        let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
        let tab = Tab(paneId: left.id)
        harness.store.appendTab(tab)
        harness.store.insertPane(
            parent.id, inTab: tab.id, at: left.id, direction: .horizontal, position: .after, sizingMode: .halveTarget)
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

        #expect(harness.controller.handleAppOwnedKeyEvent(event, requiresNeutralDrawerFocus: false))
        #expect(harness.store.tab(tab.id)?.activePaneId == left.id)
    }

    @Test("focusDrawerPaneDown is a no-op when no drawer neighbor exists")
    func executeFocusDrawerPaneDown_withoutNeighbor_keepsSelection() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
        let tab = Tab(paneId: parent.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let drawerPane = try #require(harness.store.addDrawerPane(to: parent.id))
        harness.store.setActiveDrawerPane(drawerPane.id, in: parent.id)

        harness.controller.execute(.focusDrawerPaneDown)

        #expect(harness.store.pane(parent.id)?.drawer?.activePaneId == drawerPane.id)
    }

    @Test("option-ijkl uses drawer movement after selecting a drawer pane directly")
    func optionIJKL_afterDirectDrawerSelection_staysInDrawerScope() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let left = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Left"))
        let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
        let tab = Tab(paneId: left.id)
        harness.store.appendTab(tab)
        harness.store.insertPane(
            parent.id, inTab: tab.id, at: left.id, direction: .horizontal, position: .after, sizingMode: .halveTarget)
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

        #expect(harness.controller.handleAppOwnedKeyEvent(event, requiresNeutralDrawerFocus: false))
        #expect(harness.store.pane(parent.id)?.drawer?.activePaneId == firstDrawerPane.id)
        #expect(harness.store.tab(tab.id)?.activePaneId == parent.id)
    }

    @Test("navigateDrawerPane targeted command updates canonical focus owner and keeps option-j in drawer scope")
    func targetedNavigateDrawerPane_updatesFocusOwnerAndDrawerKeyboardScope() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let left = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Left"))
        let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
        let tab = Tab(paneId: left.id)
        harness.store.appendTab(tab)
        harness.store.insertPane(
            parent.id, inTab: tab.id, at: left.id, direction: .horizontal, position: .after, sizingMode: .halveTarget)
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

        harness.controller.execute(.navigateDrawerPane, target: secondDrawerPane.id, targetType: .pane)

        #expect(atom(\.workspaceFocusOwner).owner == .drawerPane(parentPaneId: parent.id, paneId: secondDrawerPane.id))

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

        #expect(harness.controller.handleAppOwnedKeyEvent(event, requiresNeutralDrawerFocus: false))
        #expect(harness.store.pane(parent.id)?.drawer?.activePaneId == firstDrawerPane.id)
        #expect(harness.store.tab(tab.id)?.activePaneId == parent.id)
    }

    @Test("targeted detachDrawerPane resolves through command handling and promotes the drawer pane")
    func targetedDetachDrawerPane_promotesSelectedDrawerPane() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let left = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Left"))
        let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
        let tab = Tab(paneId: left.id)
        harness.store.appendTab(tab)
        harness.store.insertPane(
            parent.id, inTab: tab.id, at: left.id, direction: .horizontal, position: .after, sizingMode: .halveTarget)
        harness.store.setActiveTab(tab.id)
        harness.store.setActivePane(parent.id, inTab: tab.id)

        let drawerPane = try #require(harness.store.addDrawerPane(to: parent.id))
        atom(\.workspaceFocusOwner).focusDrawerPane(parentPaneId: parent.id, paneId: drawerPane.id)

        harness.controller.execute(.detachDrawerPane, target: drawerPane.id, targetType: .pane)

        #expect(harness.store.pane(drawerPane.id)?.parentPaneId == nil)
        #expect(harness.store.tab(tab.id)?.paneIds.contains(drawerPane.id) == true)
        #expect(harness.store.pane(parent.id)?.drawer?.paneIds.contains(drawerPane.id) == false)
    }

    @Test("dispatcher targeted detachDrawerPane works even when drawer pane is not the global focus owner")
    func dispatcherTargetedDetachDrawerPane_detachesClickedDrawerPaneWithoutDrawerPaneFocus() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let left = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Left"))
        let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
        let tab = Tab(paneId: left.id)
        harness.store.appendTab(tab)
        harness.store.insertPane(
            parent.id, inTab: tab.id, at: left.id, direction: .horizontal, position: .after, sizingMode: .halveTarget)
        harness.store.setActiveTab(tab.id)
        harness.store.setActivePane(parent.id, inTab: tab.id)
        _ = makePaneTabViewControllerCommandWindow(for: harness.controller)

        let firstDrawerPane = try #require(harness.store.addDrawerPane(to: parent.id))
        _ = try #require(harness.store.addDrawerPane(to: parent.id))
        atom(\.workspaceFocusOwner).focusMainPane(parent.id)

        CommandDispatcher.shared.dispatch(
            .detachDrawerPane,
            target: firstDrawerPane.id,
            targetType: .pane
        )

        #expect(harness.store.pane(firstDrawerPane.id)?.parentPaneId == nil)
        #expect(harness.store.tab(tab.id)?.paneIds.contains(firstDrawerPane.id) == true)
        #expect(harness.store.pane(parent.id)?.drawer?.paneIds.contains(firstDrawerPane.id) == false)
    }

    @Test("management layer create shortcut still works once option-ijkl are passed through")
    func executeManagementLayerCreateTerminal_openEmptyDrawer_createsFirstDrawerPane() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
        let tab = Tab(paneId: parent.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        harness.store.toggleDrawer(for: parent.id)
        atom(\.managementLayer).activate()

        harness.controller.execute(.managementLayerCreateTerminal)

        #expect(harness.store.pane(parent.id)?.drawer?.paneIds.count == 1)
    }

    @Test("managementLayerEnterDrawer enters the same drawer keyboard scope as enterDrawer")
    func executeManagementLayerEnterDrawer_focusesActiveDrawerPane() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
        let tab = Tab(paneId: parent.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let drawerPane = try #require(harness.store.addDrawerPane(to: parent.id))

        harness.controller.execute(.managementLayerEnterDrawer)

        #expect(harness.store.pane(parent.id)?.drawer?.activePaneId == drawerPane.id)
    }

    @Test("management layer entry adopts expanded drawer scope for create terminal")
    func executeManagementCreateTerminal_afterEnteringManagementLayerWithExpandedDrawer_targetsDrawer() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane(
            source: .floating(launchDirectory: nil, title: "Parent"),
            title: "Parent",
            provider: .zmx
        )
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        guard let existingDrawerPane = harness.store.addDrawerPane(to: parentPane.id) else {
            Issue.record("Expected drawer pane creation")
            return
        }

        harness.controller.execute(.toggleManagementLayer)

        let paneIdsBefore = Set(harness.store.panes.keys)
        let tabPaneIdsBefore = Set(harness.store.tab(tab.id)?.paneIds ?? [])
        let drawerPaneIdsBefore = Set(harness.store.pane(parentPane.id)?.drawer?.paneIds ?? [])

        harness.controller.execute(.managementLayerCreateTerminal)

        let paneIdsAfter = Set(harness.store.panes.keys)
        let createdPaneIds = paneIdsAfter.subtracting(paneIdsBefore)
        #expect(createdPaneIds.count == 1)
        let createdPaneId = try #require(createdPaneIds.first)

        let tabPaneIdsAfter = Set(harness.store.tab(tab.id)?.paneIds ?? [])
        let drawerPaneIdsAfter = Set(harness.store.pane(parentPane.id)?.drawer?.paneIds ?? [])

        #expect(tabPaneIdsAfter == tabPaneIdsBefore)
        #expect(drawerPaneIdsAfter == drawerPaneIdsBefore.union([createdPaneId]))
        #expect(
            harness.controller.managementNavigationScopeDescriptionForTesting
                == "drawer:\(parentPane.id.uuidString)"
        )
        #expect(harness.store.pane(existingDrawerPane.id) != nil)
    }

    @Test("managementLayerCreateBrowser targets drawer after drawer pane selection")
    func executeManagementCreateBrowser_selectedDrawerTargetsDrawer() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane(
            source: .floating(launchDirectory: nil, title: "Parent"),
            title: "Parent",
            provider: .zmx
        )
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        guard let drawerPane = harness.store.addDrawerPane(to: parentPane.id) else {
            Issue.record("Expected drawer pane creation")
            return
        }

        atom(\.managementLayer).activate()

        harness.controller.handlePaneFocusTrigger(
            .drawer(.selectPane(parentPaneId: parentPane.id, drawerPaneId: drawerPane.id))
        )

        let paneIdsBefore = Set(harness.store.panes.keys)
        let tabPaneIdsBefore = Set(harness.store.tab(tab.id)?.paneIds ?? [])
        let drawerPaneIdsBefore = Set(harness.store.pane(parentPane.id)?.drawer?.paneIds ?? [])

        harness.controller.execute(.managementLayerCreateBrowser)

        let paneIdsAfter = Set(harness.store.panes.keys)
        let createdPaneIds = paneIdsAfter.subtracting(paneIdsBefore)
        #expect(createdPaneIds.count == 1)
        let createdPaneId = try #require(createdPaneIds.first)
        let createdPane = try #require(harness.store.pane(createdPaneId))

        let tabPaneIdsAfter = Set(harness.store.tab(tab.id)?.paneIds ?? [])
        let drawerPaneIdsAfter = Set(harness.store.pane(parentPane.id)?.drawer?.paneIds ?? [])

        #expect(tabPaneIdsAfter == tabPaneIdsBefore)
        #expect(drawerPaneIdsAfter == drawerPaneIdsBefore.union([createdPaneId]))
        expectWebviewContent(createdPane, issuePrefix: "drawer selection browser creation")
        #expect(
            harness.controller.managementNavigationScopeDescriptionForTesting
                == "drawer:\(parentPane.id.uuidString)"
        )
    }

    @Test("managementLayerCreateBrowser in main row adds a split webview pane to the active tab")
    func executeManagementCreateBrowser_mainRowTargetsActiveTab() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane(
            source: .floating(launchDirectory: nil, title: "Parent"),
            title: "Parent",
            provider: .zmx
        )
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)

        harness.controller.execute(.toggleManagementLayer)

        let paneIdsBefore = Set(harness.store.panes.keys)
        let tabPaneIdsBefore = Set(harness.store.tab(tab.id)?.paneIds ?? [])

        harness.controller.execute(.managementLayerCreateBrowser)

        let paneIdsAfter = Set(harness.store.panes.keys)
        let createdPaneIds = paneIdsAfter.subtracting(paneIdsBefore)
        #expect(createdPaneIds.count == 1)
        let createdPaneId = try #require(createdPaneIds.first)
        let createdPane = try #require(harness.store.pane(createdPaneId))
        let tabPaneIdsAfter = Set(harness.store.tab(tab.id)?.paneIds ?? [])

        #expect(tabPaneIdsAfter == tabPaneIdsBefore.union([createdPaneId]))
        #expect(harness.store.pane(parentPane.id)?.drawer?.paneIds.isEmpty ?? true)
        expectWebviewContent(createdPane, issuePrefix: "main-row browser creation")
        #expect(harness.controller.managementNavigationScopeDescriptionForTesting == "mainRow")
    }

    @Test("management layer entry adopts expanded drawer scope for create browser")
    func executeManagementCreateBrowser_afterEnteringManagementLayerWithExpandedDrawer_targetsDrawer() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane(
            source: .floating(launchDirectory: nil, title: "Parent"),
            title: "Parent",
            provider: .zmx
        )
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        _ = harness.store.addDrawerPane(to: parentPane.id)

        harness.controller.execute(.toggleManagementLayer)

        let paneIdsBefore = Set(harness.store.panes.keys)
        let tabPaneIdsBefore = Set(harness.store.tab(tab.id)?.paneIds ?? [])
        let drawerPaneIdsBefore = Set(harness.store.pane(parentPane.id)?.drawer?.paneIds ?? [])

        harness.controller.execute(.managementLayerCreateBrowser)

        let paneIdsAfter = Set(harness.store.panes.keys)
        let createdPaneIds = paneIdsAfter.subtracting(paneIdsBefore)
        #expect(createdPaneIds.count == 1)
        let createdPaneId = try #require(createdPaneIds.first)
        let createdPane = try #require(harness.store.pane(createdPaneId))

        let tabPaneIdsAfter = Set(harness.store.tab(tab.id)?.paneIds ?? [])
        let drawerPaneIdsAfter = Set(harness.store.pane(parentPane.id)?.drawer?.paneIds ?? [])

        #expect(tabPaneIdsAfter == tabPaneIdsBefore)
        #expect(drawerPaneIdsAfter == drawerPaneIdsBefore.union([createdPaneId]))
        expectWebviewContent(createdPane, issuePrefix: "entry drawer browser creation")
        #expect(
            harness.controller.managementNavigationScopeDescriptionForTesting
                == "drawer:\(parentPane.id.uuidString)"
        )
    }

    @Test("collapsed drawer falls back to main row for management terminal creation")
    func executeManagementCreateTerminal_afterDrawerDismiss_targetsMainRow() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane(
            source: .floating(launchDirectory: nil, title: "Parent"),
            title: "Parent",
            provider: .zmx
        )
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        _ = harness.store.addDrawerPane(to: parentPane.id)

        harness.controller.execute(.toggleManagementLayer)
        harness.controller.execute(.toggleDrawer)

        let paneIdsBefore = Set(harness.store.panes.keys)
        let tabPaneIdsBefore = Set(harness.store.tab(tab.id)?.paneIds ?? [])
        let drawerPaneIdsBefore = Set(harness.store.pane(parentPane.id)?.drawer?.paneIds ?? [])

        harness.controller.execute(.managementLayerCreateTerminal)

        let paneIdsAfter = Set(harness.store.panes.keys)
        let createdPaneIds = paneIdsAfter.subtracting(paneIdsBefore)
        #expect(createdPaneIds.count == 1)
        let createdPaneId = try #require(createdPaneIds.first)

        let tabPaneIdsAfter = Set(harness.store.tab(tab.id)?.paneIds ?? [])
        let drawerPaneIdsAfter = Set(harness.store.pane(parentPane.id)?.drawer?.paneIds ?? [])

        #expect(tabPaneIdsAfter == tabPaneIdsBefore.union([createdPaneId]))
        #expect(drawerPaneIdsAfter == drawerPaneIdsBefore)
        #expect(harness.controller.managementNavigationScopeDescriptionForTesting == "mainRow")
    }

    @Test("collapsed drawer falls back to main row for management browser creation")
    func executeManagementCreateBrowser_afterDrawerDismiss_targetsMainRow() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane(
            source: .floating(launchDirectory: nil, title: "Parent"),
            title: "Parent",
            provider: .zmx
        )
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        _ = harness.store.addDrawerPane(to: parentPane.id)

        harness.controller.execute(.toggleManagementLayer)
        harness.controller.execute(.toggleDrawer)

        let paneIdsBefore = Set(harness.store.panes.keys)
        let tabPaneIdsBefore = Set(harness.store.tab(tab.id)?.paneIds ?? [])
        let drawerPaneIdsBefore = Set(harness.store.pane(parentPane.id)?.drawer?.paneIds ?? [])

        harness.controller.execute(.managementLayerCreateBrowser)

        let paneIdsAfter = Set(harness.store.panes.keys)
        let createdPaneIds = paneIdsAfter.subtracting(paneIdsBefore)
        #expect(createdPaneIds.count == 1)
        let createdPaneId = try #require(createdPaneIds.first)
        let createdPane = try #require(harness.store.pane(createdPaneId))

        let tabPaneIdsAfter = Set(harness.store.tab(tab.id)?.paneIds ?? [])
        let drawerPaneIdsAfter = Set(harness.store.pane(parentPane.id)?.drawer?.paneIds ?? [])

        #expect(tabPaneIdsAfter == tabPaneIdsBefore.union([createdPaneId]))
        #expect(drawerPaneIdsAfter == drawerPaneIdsBefore)
        expectWebviewContent(createdPane, issuePrefix: "collapsed drawer browser creation")
        #expect(harness.controller.managementNavigationScopeDescriptionForTesting == "mainRow")
    }
}
