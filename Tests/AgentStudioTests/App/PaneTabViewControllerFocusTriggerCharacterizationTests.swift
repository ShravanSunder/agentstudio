import AppKit
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneFocusTriggerCharacterizationTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("content click on inactive pane selects pane and focuses host")
    func contentClickInactivePane_selectsPaneAndFocusesHost() throws {
        try withIsolatedFocusHarness { harness in

            let fixture = try makeTwoPaneFixture(in: harness)
            let targetHost = try #require(harness.viewRegistry.view(for: fixture.secondPane.id))

            harness.controller.handlePaneFocusTrigger(
                .contentClick(
                    PaneContentClickFocusTrigger(
                        targetPaneId: fixture.secondPane.id,
                        location: .content,
                        clickPhase: .completed
                    )
                )
            )

            #expect(harness.store.activeTabId == fixture.tab.id)
            #expect(harness.store.tab(fixture.tab.id)?.activePaneId == fixture.secondPane.id)
            #expect(atom(\.workspaceFocusOwner).owner == .mainPane(paneId: fixture.secondPane.id))
            #expect(harness.windowFirstResponder === targetHost)
            #expect(harness.controller.managementNavigationScopeDescriptionForTesting == "mainRow")
        }
    }

    @Test("tab click selects tab and restores that tab's main pane focus owner")
    func tabClick_selectsTabAndRestoresMainPaneFocusOwner() throws {
        try withIsolatedFocusHarness { harness in

            let firstPane = harness.store.createPane(launchDirectory: nil, title: "First")
            let secondPane = harness.store.createPane(launchDirectory: nil, title: "Second")
            let firstTab = Tab(paneId: firstPane.id, name: "First")
            let secondTab = Tab(paneId: secondPane.id, name: "Second")
            harness.store.appendTab(firstTab)
            harness.store.appendTab(secondTab)
            harness.store.setActiveTab(firstTab.id)
            harness.store.setActivePane(firstPane.id, inTab: firstTab.id)
            atom(\.workspaceFocusOwner).focusMainPane(firstPane.id)

            let window = makePaneTabViewControllerCommandWindow(for: harness.controller)
            try attachPaneHost(paneId: firstPane.id, in: harness, to: window)
            try attachPaneHost(paneId: secondPane.id, in: harness, to: window)
            harness.controller.view.layoutSubtreeIfNeeded()

            harness.controller.handlePaneFocusTrigger(.tabClick(PaneTabClickFocusTrigger(targetTabId: secondTab.id)))

            #expect(harness.store.activeTabId == secondTab.id)
            #expect(atom(\.workspaceFocusOwner).owner == .mainPane(paneId: secondPane.id))
        }
    }

    @Test("drawer select pane updates drawer cursor, owner, responder, and navigation scope")
    func drawerSelectPane_updatesDrawerCursorOwnerResponderAndScope() throws {
        try withIsolatedFocusHarness { harness in

            let parentPane = harness.store.createPane(launchDirectory: nil, title: "Parent")
            let tab = Tab(paneId: parentPane.id)
            harness.store.appendTab(tab)
            harness.store.setActiveTab(tab.id)
            harness.store.setActivePane(parentPane.id, inTab: tab.id)
            let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
            let window = makePaneTabViewControllerCommandWindow(for: harness.controller)
            try attachPaneHost(paneId: parentPane.id, in: harness, to: window)
            let drawerHost = try attachPaneHost(paneId: drawerPane.id, in: harness, to: window)
            harness.controller.view.layoutSubtreeIfNeeded()

            harness.controller.handlePaneFocusTrigger(
                .drawer(.selectPane(parentPaneId: parentPane.id, drawerPaneId: drawerPane.id))
            )

            #expect(harness.store.drawerView(forParent: parentPane.id)?.activeChildId == drawerPane.id)
            #expect(
                atom(\.workspaceFocusOwner).owner == .drawerPane(parentPaneId: parentPane.id, paneId: drawerPane.id))
            #expect(window.firstResponder === drawerHost)
            #expect(
                harness.controller.managementNavigationScopeDescriptionForTesting
                    == "drawer:\(parentPane.id.uuidString)"
            )
        }
    }

    @Test("keyboard move to pane selects target pane and focuses host")
    func keyboardMoveToPane_selectsTargetPaneAndFocusesHost() throws {
        try withIsolatedFocusHarness { harness in

            let fixture = try makeTwoPaneFixture(in: harness)
            let targetHost = try #require(harness.viewRegistry.view(for: fixture.secondPane.id))

            harness.controller.handlePaneFocusTrigger(
                .keyboard(.moveToPane(tabId: fixture.tab.id, paneId: fixture.secondPane.id, paneKind: .terminal))
            )

            #expect(harness.store.tab(fixture.tab.id)?.activePaneId == fixture.secondPane.id)
            #expect(atom(\.workspaceFocusOwner).owner == .mainPane(paneId: fixture.secondPane.id))
            #expect(harness.windowFirstResponder === targetHost)
            #expect(harness.controller.managementNavigationScopeDescriptionForTesting == "mainRow")
        }
    }

    @Test("entering management layer over terminal clears responder to window content")
    func modeEnteredManagementLayer_terminalClearsResponderToWindowContent() throws {
        try withIsolatedFocusHarness { harness in

            let pane = harness.store.createPane(launchDirectory: nil, title: "Terminal")
            let tab = Tab(paneId: pane.id)
            harness.store.appendTab(tab)
            harness.store.setActiveTab(tab.id)
            harness.store.setActivePane(pane.id, inTab: tab.id)
            atom(\.workspaceFocusOwner).focusMainPane(pane.id)
            let window = makePaneTabViewControllerCommandWindow(for: harness.controller)
            let mountedContent = FocusablePaneTabCommandMountedContentView()
            try attachPaneHost(paneId: pane.id, in: harness, to: window, mountedContent: mountedContent)
            window.makeFirstResponder(mountedContent)

            harness.controller.handlePaneFocusTrigger(
                .mode(
                    PaneModeFocusTrigger(
                        transition: .enteredManagementLayer,
                        source: .keyboardShortcut
                    )
                )
            )

            #expect(window.firstResponder === window.contentView)
            #expect(atom(\.workspaceFocusOwner).owner == .mainPane(paneId: pane.id))
        }
    }

    @Test("refocus request focuses the active pane host")
    func refocusRequest_focusesActivePaneHost() throws {
        try withIsolatedFocusHarness { harness in

            let pane = harness.store.createPane(launchDirectory: nil, title: "Terminal")
            let tab = Tab(paneId: pane.id)
            harness.store.appendTab(tab)
            harness.store.setActiveTab(tab.id)
            harness.store.setActivePane(pane.id, inTab: tab.id)
            atom(\.workspaceFocusOwner).focusMainPane(pane.id)
            let window = makePaneTabViewControllerCommandWindow(for: harness.controller)
            let host = try attachPaneHost(paneId: pane.id, in: harness, to: window)
            window.makeFirstResponder(window.contentView)

            harness.controller.handlePaneFocusTrigger(
                .refocusRequest(PaneRefocusRequestTrigger(reason: .explicit))
            )

            #expect(window.firstResponder === host)
        }
    }

    @Test("command focusPane selects target pane and focuses host")
    func commandFocusPane_selectsTargetPaneAndFocusesHost() throws {
        try withIsolatedFocusHarness { harness in

            let fixture = try makeTwoPaneFixture(in: harness)
            let targetHost = try #require(harness.viewRegistry.view(for: fixture.secondPane.id))

            harness.controller.handlePaneFocusTrigger(
                .command(.focusPane(tabId: fixture.tab.id, paneId: fixture.secondPane.id))
            )

            #expect(harness.store.tab(fixture.tab.id)?.activePaneId == fixture.secondPane.id)
            #expect(atom(\.workspaceFocusOwner).owner == .mainPane(paneId: fixture.secondPane.id))
            #expect(harness.windowFirstResponder === targetHost)
        }
    }

    @Test("command selectTab restores the selected tab focus owner")
    func commandSelectTab_restoresSelectedTabFocusOwner() throws {
        try withIsolatedFocusHarness { harness in

            let firstPane = harness.store.createPane(launchDirectory: nil, title: "First")
            let secondPane = harness.store.createPane(launchDirectory: nil, title: "Second")
            let firstTab = Tab(paneId: firstPane.id, name: "First")
            let secondTab = Tab(paneId: secondPane.id, name: "Second")
            harness.store.appendTab(firstTab)
            harness.store.appendTab(secondTab)
            harness.store.setActiveTab(firstTab.id)
            harness.store.setActivePane(firstPane.id, inTab: firstTab.id)

            let window = makePaneTabViewControllerCommandWindow(for: harness.controller)
            try attachPaneHost(paneId: firstPane.id, in: harness, to: window)
            try attachPaneHost(paneId: secondPane.id, in: harness, to: window)
            harness.controller.view.layoutSubtreeIfNeeded()

            harness.controller.handlePaneFocusTrigger(.command(.selectTab(secondTab.id)))

            #expect(harness.store.activeTabId == secondTab.id)
            #expect(atom(\.workspaceFocusOwner).owner == .mainPane(paneId: secondPane.id))
        }
    }

    @Test("command paneCreated focuses created pane host without changing selection")
    func commandPaneCreated_focusesCreatedPaneHostWithoutChangingSelection() throws {
        try withIsolatedFocusHarness { harness in

            let fixture = try makeTwoPaneFixture(in: harness)
            let targetHost = try #require(harness.viewRegistry.view(for: fixture.secondPane.id))

            harness.controller.handlePaneFocusTrigger(
                .command(.paneCreated(paneId: fixture.secondPane.id, paneKind: .terminal))
            )

            #expect(harness.store.tab(fixture.tab.id)?.activePaneId == fixture.firstPane.id)
            #expect(atom(\.workspaceFocusOwner).owner == .mainPane(paneId: fixture.firstPane.id))
            #expect(harness.windowFirstResponder === targetHost)
        }
    }
}

@MainActor
private struct PaneTabFocusTriggerFixture {
    let tab: Tab
    let firstPane: Pane
    let secondPane: Pane
    let window: NSWindow
}

@MainActor
extension PaneTabViewControllerCommandHarness {
    fileprivate var windowFirstResponder: NSResponder? {
        controller.view.window?.firstResponder
    }
}

@MainActor
private func makeTwoPaneFixture(
    in harness: PaneTabViewControllerCommandHarness
) throws -> PaneTabFocusTriggerFixture {
    let firstPane = harness.store.createPane(launchDirectory: nil, title: "First")
    let secondPane = harness.store.createPane(launchDirectory: nil, title: "Second")
    let tab = Tab(paneId: firstPane.id)
    harness.store.appendTab(tab)
    harness.store.insertPane(
        secondPane.id,
        inTab: tab.id,
        at: firstPane.id,
        direction: .horizontal,
        position: .after,
        sizingMode: .halveTarget
    )
    harness.store.setActiveTab(tab.id)
    harness.store.setActivePane(firstPane.id, inTab: tab.id)
    atom(\.workspaceFocusOwner).focusMainPane(firstPane.id)

    let window = makePaneTabViewControllerCommandWindow(for: harness.controller)
    try attachPaneHost(paneId: firstPane.id, in: harness, to: window)
    try attachPaneHost(paneId: secondPane.id, in: harness, to: window)
    harness.controller.view.layoutSubtreeIfNeeded()

    return PaneTabFocusTriggerFixture(tab: tab, firstPane: firstPane, secondPane: secondPane, window: window)
}

@MainActor
private func withIsolatedFocusHarness<T>(
    _ body: (PaneTabViewControllerCommandHarness) throws -> T
) rethrows -> T {
    try withTestAtomRegistry { _ in
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        return try body(harness)
    }
}
