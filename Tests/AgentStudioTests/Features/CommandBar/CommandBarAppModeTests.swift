import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("CommandBarAppMode")
struct CommandBarAppModeTests {
    @Test
    func normalModeProperties() {
        let mode = CommandBarAppMode.normal

        #expect(mode.statusStripLabel == nil)
        #expect(mode.statusStripIcon == nil)
    }

    @Test
    func managementLayerProperties() {
        let mode = CommandBarAppMode.management

        #expect(mode.statusStripLabel == "Management")
        #expect(mode.statusStripIcon == "rectangle.split.2x2.fill")
    }
}

@MainActor
@Suite("WorkspacePaneFocus")
struct WorkspacePaneFocusTests {
    @Test
    func visibilityIgnoresMissingRequirementsOnlyWhenDefinitionHasNoRequirements() {
        let alwaysVisible = CommandSpec(command: .newTab, label: "New Tab", helpText: "Create a new tab")
        let tabOnly = CommandSpec(
            command: .closeTab,
            label: "Close Tab",
            helpText: "Close the active tab",
            visibleWhen: [.hasActiveTab]
        )
        let focus = WorkspacePaneFocus(paneContentType: .noActivePane, satisfiedRequirements: [])

        #expect(alwaysVisible.isVisible(in: focus))
        #expect(!tabOnly.isVisible(in: focus))
    }

    @Test
    func visibilityRequiresAllRequestedFocusFlags() {
        let definition = CommandSpec(
            command: .navigateDrawerPane,
            label: "Switch Drawer Pane",
            helpText: "Switch to a pane inside the active drawer",
            visibleWhen: [.hasActivePane, .hasDrawerPanes]
        )
        let missingDrawer = WorkspacePaneFocus(
            paneContentType: .terminal,
            satisfiedRequirements: [.hasActivePane]
        )
        let ready = WorkspacePaneFocus(
            paneContentType: .terminal,
            satisfiedRequirements: [.hasActivePane, .hasDrawerPanes]
        )

        #expect(!definition.isVisible(in: missingDrawer))
        #expect(definition.isVisible(in: ready))
    }

    @Test
    func detachDrawerPaneVisibility_requiresFocusedDrawerPane() {
        let definition = CommandDispatcher.shared.definition(for: .detachDrawerPane)
        let emptyDrawerFocus = WorkspacePaneFocus(
            paneContentType: .terminal,
            drawerFocusState: .emptyDrawer(parentPaneId: UUID()),
            satisfiedRequirements: [.hasActiveTab, .hasActivePane, .hasDrawer, .hasEmptyDrawerFocus]
        )
        let drawerPaneFocus = WorkspacePaneFocus(
            paneContentType: .terminal,
            drawerFocusState: .drawerPane(parentPaneId: UUID(), paneId: UUID()),
            satisfiedRequirements: [.hasActiveTab, .hasActivePane, .hasDrawer, .hasDrawerPanes, .hasFocusedDrawerPane]
        )

        #expect(!definition.isVisible(in: emptyDrawerFocus))
        #expect(definition.isVisible(in: drawerPaneFocus))
    }

    @Test
    func terminalContextMetadata() {
        let focus = WorkspacePaneFocus(
            paneContentType: .terminal,
            satisfiedRequirements: [.hasActivePane, .paneIsTerminal]
        )

        #expect(focus.label == "Terminal")
        #expect(focus.icon == "terminal")
    }

    @Test
    func webviewContextMetadata() {
        let focus = WorkspacePaneFocus(
            paneContentType: .webview,
            satisfiedRequirements: [.hasActivePane, .paneIsWebview]
        )

        #expect(focus.label == "Webview")
        #expect(focus.icon == "globe")
    }

    @Test
    func bridgeContextMetadata() {
        let focus = WorkspacePaneFocus(
            paneContentType: .bridge,
            satisfiedRequirements: [.hasActivePane, .paneIsBridge]
        )

        #expect(focus.label == "Bridge")
        #expect(focus.icon == "rectangle.split.2x1")
    }

    @Test
    func codeViewerContextMetadata() {
        let focus = WorkspacePaneFocus(
            paneContentType: .codeViewer,
            satisfiedRequirements: [.hasActivePane, .paneIsCodeViewer]
        )

        #expect(focus.label == "Code Viewer")
        #expect(focus.icon == "doc.text")
    }

    @Test
    func unsupportedContextMetadata() {
        let focus = WorkspacePaneFocus(paneContentType: .unsupported, satisfiedRequirements: [.hasActivePane])

        #expect(focus.label == "Unsupported")
        #expect(focus.icon == "questionmark.square")
    }

    @Test
    func noActivePaneHidesContextMetadata() {
        let focus = WorkspacePaneFocus(paneContentType: .noActivePane, satisfiedRequirements: [])

        #expect(focus.label == nil)
        #expect(focus.icon == nil)
    }

    @Test
    func contentRequirementNormalizationReplacesMismatchedPaneKindFlag() {
        let focus = WorkspacePaneFocus(
            paneContentType: .terminal,
            satisfiedRequirements: [.hasActivePane, .paneIsWebview]
        )

        #expect(focus.satisfiedRequirements.contains(.paneIsTerminal))
        #expect(!focus.satisfiedRequirements.contains(.paneIsWebview))
    }
}

@MainActor
@Suite("WorkspacePaneFocusDerivedProjection")
struct WorkspacePaneFocusDerivedProjectionTests {
    private func workspaceTab(for store: WorkspaceStore) -> WorkspaceTabDerived {
        WorkspaceTabDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )
    }

    @Test
    func emptyWorkspaceHasNoActiveContext() {
        let store = WorkspaceStore()
        let focus = WorkspacePaneFocusDerived().currentFocus(
            workspaceTab: workspaceTab(for: store),
            workspacePane: store.paneAtom,
            workspaceNavigationScope: WorkspaceNavigationScopeAtom()
        )

        #expect(focus.paneContentType == .noActivePane)
        #expect(focus.satisfiedRequirements.isEmpty)
    }

    @Test
    func activeTerminalTabReportsFocusRequirements() {
        let store = WorkspaceStore()
        let pane = store.createPane(source: .floating(launchDirectory: nil, title: "Pane A"))
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let focus = WorkspacePaneFocusDerived().currentFocus(
            workspaceTab: workspaceTab(for: store),
            workspacePane: store.paneAtom,
            workspaceNavigationScope: WorkspaceNavigationScopeAtom()
        )

        #expect(focus.paneContentType == .terminal)
        #expect(focus.satisfiedRequirements.contains(.hasActiveTab))
        #expect(focus.satisfiedRequirements.contains(.hasActivePane))
        #expect(focus.satisfiedRequirements.contains(.paneIsTerminal))
        #expect(!focus.satisfiedRequirements.contains(.hasDrawerPanes))
        #expect(!focus.satisfiedRequirements.contains(.hasMultiplePanes))
        #expect(!focus.satisfiedRequirements.contains(.hasArrangements))
    }

    @Test
    func activeTabWithoutActivePaneKeepsTabFocusButNoPaneFocus() {
        let pane = UUID()
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: pane)
        )
        let tab = Tab(
            name: "Detached",
            allPaneIds: [pane],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: nil
        )
        let store = WorkspaceStore()
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let focus = WorkspacePaneFocusDerived().currentFocus(
            workspaceTab: workspaceTab(for: store),
            workspacePane: store.paneAtom,
            workspaceNavigationScope: WorkspaceNavigationScopeAtom()
        )

        #expect(focus.paneContentType == .noActivePane)
        #expect(focus.satisfiedRequirements.contains(.hasActiveTab))
        #expect(!focus.satisfiedRequirements.contains(.hasActivePane))
    }

    @Test
    func staleActivePaneIdDoesNotReportPaneFocus() {
        let pane = UUID()
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: pane)
        )
        let tab = Tab(
            name: "Stale",
            allPaneIds: [],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: pane
        )
        let store = WorkspaceStore()
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let focus = WorkspacePaneFocusDerived().currentFocus(
            workspaceTab: workspaceTab(for: store),
            workspacePane: store.paneAtom,
            workspaceNavigationScope: WorkspaceNavigationScopeAtom()
        )

        #expect(focus.paneContentType == .noActivePane)
        #expect(focus.satisfiedRequirements.contains(.hasActiveTab))
        #expect(!focus.satisfiedRequirements.contains(.hasActivePane))
    }

    @Test
    func drawerAndArrangementRequirementsAreReported() {
        let store = WorkspaceStore()
        let paneA = store.createPane(source: .floating(launchDirectory: nil, title: "Pane A"))
        let paneB = store.createPane(source: .floating(launchDirectory: nil, title: "Pane B"))
        var tab = Tab(paneId: paneA.id)
        let namedArrangement = PaneArrangement(
            name: "Review",
            isDefault: false,
            layout: tab.layout,
            visiblePaneIds: Set(tab.activePaneIds)
        )
        tab.arrangements.append(namedArrangement)
        store.appendTab(tab)
        store.setActiveTab(tab.id)
        store.insertPane(paneB.id, inTab: tab.id, at: paneA.id, direction: .horizontal, position: .after)
        _ = store.addDrawerPane(to: paneA.id)

        let focus = WorkspacePaneFocusDerived().currentFocus(
            workspaceTab: workspaceTab(for: store),
            workspacePane: store.paneAtom,
            workspaceNavigationScope: WorkspaceNavigationScopeAtom()
        )

        #expect(focus.satisfiedRequirements.contains(.hasMultiplePanes))
        #expect(focus.satisfiedRequirements.contains(.hasArrangements))
        #expect(focus.satisfiedRequirements.contains(.hasDrawer))
        #expect(focus.satisfiedRequirements.contains(.hasDrawerPanes))
    }

    @Test
    func multipleTabsRequirementIsReported() {
        let store = WorkspaceStore()
        let paneA = store.createPane(source: .floating(launchDirectory: nil, title: "Pane A"))
        let paneB = store.createPane(source: .floating(launchDirectory: nil, title: "Pane B"))
        let firstTab = Tab(paneId: paneA.id)
        let secondTab = Tab(paneId: paneB.id)
        store.appendTab(firstTab)
        store.appendTab(secondTab)
        store.setActiveTab(firstTab.id)

        let focus = WorkspacePaneFocusDerived().currentFocus(
            workspaceTab: workspaceTab(for: store),
            workspacePane: store.paneAtom,
            workspaceNavigationScope: WorkspaceNavigationScopeAtom()
        )

        #expect(focus.satisfiedRequirements.contains(.hasMultipleTabs))
    }
}
