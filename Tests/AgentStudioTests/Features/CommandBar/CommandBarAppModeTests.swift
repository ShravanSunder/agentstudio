import Testing

@testable import AgentStudio

@MainActor
@Suite("CommandBarAppMode")
struct CommandBarAppModeTests {
    @Test
    func normalModeProperties() {
        let mode = CommandBarAppMode.normal

        #expect(mode.label == "Normal")
        #expect(mode.icon == "rectangle.split.2x2")
        #expect(mode.isAccented == false)
    }

    @Test
    func managementModeProperties() {
        let mode = CommandBarAppMode.management

        #expect(mode.label == "Manage")
        #expect(mode.icon == "rectangle.split.2x2.fill")
        #expect(mode.isAccented == true)
    }
}

@MainActor
@Suite("WorkspaceFocus")
struct WorkspaceFocusTests {
    @Test
    func terminalContextMetadata() {
        let focus = WorkspaceFocus(
            paneContentType: .terminal,
            satisfiedRequirements: [.hasActivePane, .paneIsTerminal]
        )

        #expect(focus.label == "Terminal")
        #expect(focus.icon == "terminal")
    }

    @Test
    func webviewContextMetadata() {
        let focus = WorkspaceFocus(paneContentType: .webview, satisfiedRequirements: [.hasActivePane, .paneIsWebview])

        #expect(focus.label == "Webview")
        #expect(focus.icon == "globe")
    }

    @Test
    func bridgeContextMetadata() {
        let focus = WorkspaceFocus(paneContentType: .bridge, satisfiedRequirements: [.hasActivePane, .paneIsBridge])

        #expect(focus.label == "Bridge")
        #expect(focus.icon == "rectangle.split.2x1")
    }

    @Test
    func codeViewerContextMetadata() {
        let focus = WorkspaceFocus(
            paneContentType: .codeViewer,
            satisfiedRequirements: [.hasActivePane, .paneIsCodeViewer]
        )

        #expect(focus.label == "Code Viewer")
        #expect(focus.icon == "doc.text")
    }

    @Test
    func unsupportedContextMetadata() {
        let focus = WorkspaceFocus(paneContentType: .unsupported, satisfiedRequirements: [.hasActivePane])

        #expect(focus.label == "Unsupported")
        #expect(focus.icon == "questionmark.square")
    }

    @Test
    func noActivePaneHidesContextMetadata() {
        let focus = WorkspaceFocus(paneContentType: .noActivePane, satisfiedRequirements: [])

        #expect(focus.label == nil)
        #expect(focus.icon == nil)
    }
}

@MainActor
@Suite("WorkspaceFocusComputer")
struct WorkspaceFocusComputerTests {
    @Test
    func emptyWorkspaceHasNoActiveContext() {
        let focus = WorkspaceFocusComputer.compute(store: WorkspaceStore())

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

        let focus = WorkspaceFocusComputer.compute(store: store)

        #expect(focus.paneContentType == .terminal)
        #expect(focus.satisfiedRequirements.contains(.hasActiveTab))
        #expect(focus.satisfiedRequirements.contains(.hasActivePane))
        #expect(focus.satisfiedRequirements.contains(.paneIsTerminal))
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

        let focus = WorkspaceFocusComputer.compute(store: store)

        #expect(focus.satisfiedRequirements.contains(.hasMultiplePanes))
        #expect(focus.satisfiedRequirements.contains(.hasArrangements))
        #expect(focus.satisfiedRequirements.contains(.hasDrawer))
        #expect(focus.satisfiedRequirements.contains(.hasDrawerPanes))
    }
}
