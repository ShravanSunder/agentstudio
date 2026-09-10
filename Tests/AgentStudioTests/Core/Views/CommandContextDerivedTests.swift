import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite(.serialized)
struct CommandContextDerivedTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test
    func emptyWorkspaceHasNoSatisfiedRequirements() {
        withTestCoreAtoms { _ in
            let context = CommandContextDerived().currentContext(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane),
                focusedPane: nil,
                workspacePanePresentation: atom(\.workspacePanePresentation)
            )

            #expect(context == .empty)
        }
    }

    @Test
    func activePaneAndTabCountsProduceCountRequirements() throws {
        try withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let activePane = store.createPane()
            let secondPane = store.createPane()
            let otherTabPane = store.createPane()
            let activeTab = Tab(paneId: activePane.id)
            let otherTab = Tab(paneId: otherTabPane.id)
            store.appendTab(activeTab)
            #expect(
                store.insertPane(
                    secondPane.id,
                    inTab: activeTab.id,
                    at: activePane.id,
                    direction: .horizontal,
                    position: .after,
                    sizingMode: .halveTarget
                )
            )
            store.appendTab(otherTab)
            store.setActiveTab(activeTab.id)
            store.setActivePane(activePane.id, inTab: activeTab.id)
            atoms.workspaceFocusOwner.focusMainPane(activePane.id)

            let focusedPane = WorkspaceFocusedPaneResolver().resolve(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane),
                requestedOwner: atoms.workspaceFocusOwner.owner
            )
            let context = CommandContextDerived().currentContext(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane),
                focusedPane: focusedPane,
                workspacePanePresentation: atoms.workspacePanePresentation
            )

            #expect(context.activeTabId == activeTab.id)
            #expect(context.focusedPaneId == activePane.id)
            #expect(context.satisfiedRequirements.contains(.hasActiveTab))
            #expect(context.satisfiedRequirements.contains(.hasActivePane))
            #expect(context.satisfiedRequirements.contains(.hasMultiplePanes))
            #expect(context.satisfiedRequirements.contains(.hasMultipleTabs))
        }
    }

    @Test
    func backgroundedCanonicalActivePaneUsesActiveFallbackForCommandContext() throws {
        try withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let backgroundedCanonicalPane = store.createPane()
            let activeFallbackPane = store.createPane()
            let tab = Tab(paneId: backgroundedCanonicalPane.id)
            store.appendTab(tab)
            #expect(
                store.insertPane(
                    activeFallbackPane.id,
                    inTab: tab.id,
                    at: backgroundedCanonicalPane.id,
                    direction: .horizontal,
                    position: .after,
                    sizingMode: .halveTarget
                )
            )
            store.setActiveTab(tab.id)
            store.setActivePane(backgroundedCanonicalPane.id, inTab: tab.id)
            #expect(store.mutationCoordinator.backgroundPane(backgroundedCanonicalPane.id))
            atoms.workspaceFocusOwner.focusMainPane(backgroundedCanonicalPane.id)

            let focusedPane = WorkspaceFocusedPaneResolver().resolve(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane),
                requestedOwner: atoms.workspaceFocusOwner.owner
            )
            let context = CommandContextDerived().currentContext(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane),
                focusedPane: focusedPane,
                workspacePanePresentation: atoms.workspacePanePresentation
            )

            #expect(context.focusedPaneId == activeFallbackPane.id)
            #expect(context.satisfiedRequirements.contains(.hasActivePane))
            #expect(!context.satisfiedRequirements.contains(.hasMultiplePanes))
        }
    }

    @Test
    func emptyDrawerFocusProducesEmptyDrawerRequirements() throws {
        try withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let parentPane = store.createPane()
            let tab = Tab(paneId: parentPane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            store.toggleDrawer(for: parentPane.id)
            atoms.workspaceFocusOwner.focusEmptyDrawer(parentPaneId: parentPane.id)

            let focusedPane = WorkspaceFocusedPaneResolver().resolve(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane),
                requestedOwner: atoms.workspaceFocusOwner.owner
            )
            let context = CommandContextDerived().currentContext(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane),
                focusedPane: focusedPane,
                workspacePanePresentation: atoms.workspacePanePresentation
            )

            #expect(context.satisfiedRequirements.contains(.hasDrawer))
            #expect(!context.satisfiedRequirements.contains(.hasDrawerPanes))
            #expect(context.satisfiedRequirements.contains(.hasEmptyDrawerFocus))
            #expect(!context.satisfiedRequirements.contains(.hasFocusedDrawerPane))
        }
    }

    @Test
    func focusedDrawerChildProducesPopulatedDrawerRequirements() throws {
        try withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let parentPane = store.createPane()
            let tab = Tab(paneId: parentPane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            let drawerPane = try #require(store.addDrawerPane(to: parentPane.id))
            atoms.workspaceFocusOwner.focusDrawerPane(
                parentPaneId: parentPane.id,
                paneId: drawerPane.id
            )

            let focusedPane = WorkspaceFocusedPaneResolver().resolve(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane),
                requestedOwner: atoms.workspaceFocusOwner.owner
            )
            let context = CommandContextDerived().currentContext(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane),
                focusedPane: focusedPane,
                workspacePanePresentation: atoms.workspacePanePresentation
            )

            #expect(context.satisfiedRequirements.contains(.hasDrawer))
            #expect(context.satisfiedRequirements.contains(.hasDrawerPanes))
            #expect(!context.satisfiedRequirements.contains(.hasEmptyDrawerFocus))
            #expect(context.satisfiedRequirements.contains(.hasFocusedDrawerPane))
        }
    }

    @Test
    func multipleArrangementsProduceArrangementRequirement() throws {
        try withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let pane = store.createPane()
            let tab = Tab(paneId: pane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            atoms.workspaceFocusOwner.focusMainPane(pane.id)

            @MainActor
            func currentContext() -> CommandContext {
                let focusedPane = WorkspaceFocusedPaneResolver().resolve(
                    workspaceTab: atom(\.workspaceTab),
                    workspacePane: atom(\.workspacePane),
                    requestedOwner: atoms.workspaceFocusOwner.owner
                )
                return CommandContextDerived().currentContext(
                    workspaceTab: atom(\.workspaceTab),
                    workspacePane: atom(\.workspacePane),
                    focusedPane: focusedPane,
                    workspacePanePresentation: atoms.workspacePanePresentation
                )
            }

            #expect(!currentContext().satisfiedRequirements.contains(.hasArrangements))
            _ = try #require(store.createArrangement(name: "Focus", inTab: tab.id))
            #expect(currentContext().satisfiedRequirements.contains(.hasArrangements))
        }
    }

    @Test
    func focusedContentNormalizesCallerSuppliedRequirementsToItsSingleClassification() {
        let contentRequirements: Set<CommandRequirement> = [
            .paneIsTerminal,
            .paneIsWebview,
            .paneIsBridge,
            .paneIsCodeViewer,
        ]
        let cases: [(WorkspaceFocusedPane.ContentType?, CommandRequirement?)] = [
            (.terminal, .paneIsTerminal),
            (.webview, .paneIsWebview),
            (.bridge, .paneIsBridge),
            (.codeViewer, .paneIsCodeViewer),
            (.unsupported, nil),
            (nil, nil),
        ]

        for (focusedContentType, expectedContentRequirement) in cases {
            let context = CommandContext(
                activeTabId: UUID(),
                focusedPaneId: UUID(),
                focusedRepoId: nil,
                focusedWorktreeId: nil,
                focusedContentType: focusedContentType,
                satisfiedRequirements: Set(CommandRequirement.allCases)
            )
            let expectedRequirements = Set(expectedContentRequirement.map { [$0] } ?? [])

            #expect(
                context.satisfiedRequirements.intersection(contentRequirements)
                    == expectedRequirements
            )
        }
    }

    @Test
    func terminalZoomSourceProducesActiveTerminalZoomRequirements() {
        withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let sourcePane = store.createPane()
            let tab = Tab(paneId: sourcePane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            store.setActivePane(sourcePane.id, inTab: tab.id)
            atoms.workspaceFocusOwner.focusMainPane(sourcePane.id)
            atoms.workspacePanePresentation.enterZoom(
                inTab: tab.id,
                sourcePaneId: sourcePane.id,
                viewerPresentation: .unavailable
            )

            let focusedPane = WorkspaceFocusedPaneResolver().resolve(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane),
                requestedOwner: atoms.workspaceFocusOwner.owner
            )
            let context = CommandContextDerived().currentContext(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane),
                focusedPane: focusedPane,
                workspacePanePresentation: atoms.workspacePanePresentation
            )

            #expect(context.focusedContentType == .terminal)
            #expect(context.satisfiedRequirements.contains(.supportsTerminalZoom))
            #expect(context.satisfiedRequirements.contains(.hasActiveTerminalZoom))
        }
    }

    @Test
    func staleZoomSourceDoesNotProduceActiveTerminalZoomRequirement() {
        withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let activePane = store.createPane()
            let tab = Tab(paneId: activePane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            store.setActivePane(activePane.id, inTab: tab.id)
            atoms.workspaceFocusOwner.focusMainPane(activePane.id)
            atoms.workspacePanePresentation.enterZoom(
                inTab: tab.id,
                sourcePaneId: UUID(),
                viewerPresentation: .unavailable
            )

            let focusedPane = WorkspaceFocusedPaneResolver().resolve(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane),
                requestedOwner: atoms.workspaceFocusOwner.owner
            )
            let context = CommandContextDerived().currentContext(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane),
                focusedPane: focusedPane,
                workspacePanePresentation: atoms.workspacePanePresentation
            )

            #expect(context.satisfiedRequirements.contains(.supportsTerminalZoom))
            #expect(!context.satisfiedRequirements.contains(.hasActiveTerminalZoom))
        }
    }

    @Test
    func nonterminalZoomSourceDoesNotProduceTerminalZoomRequirements() {
        withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let sourcePane = store.createPane(
                content: .webview(WebviewState(url: URL(string: "https://source.example")!)),
                metadata: PaneMetadata(contentType: .browser, title: "Webview")
            )
            let tab = Tab(paneId: sourcePane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            store.setActivePane(sourcePane.id, inTab: tab.id)
            atoms.workspaceFocusOwner.focusMainPane(sourcePane.id)
            atoms.workspacePanePresentation.enterZoom(
                inTab: tab.id,
                sourcePaneId: sourcePane.id,
                viewerPresentation: .unavailable
            )

            let focusedPane = WorkspaceFocusedPaneResolver().resolve(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane),
                requestedOwner: atoms.workspaceFocusOwner.owner
            )
            let context = CommandContextDerived().currentContext(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane),
                focusedPane: focusedPane,
                workspacePanePresentation: atoms.workspacePanePresentation
            )

            #expect(context.focusedContentType == .webview)
            #expect(!context.satisfiedRequirements.contains(.supportsTerminalZoom))
            #expect(!context.satisfiedRequirements.contains(.hasActiveTerminalZoom))
        }
    }

    @Test
    func terminalZoomDoesNotDependOnFocusedDrawerContent() throws {
        try withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let sourcePane = store.createPane()
            let tab = Tab(paneId: sourcePane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            let drawerPane = try #require(
                atoms.workspacePane.addDrawerPane(
                    to: sourcePane.id,
                    content: .webview(WebviewState(url: URL(string: "https://drawer.example")!)),
                    metadata: PaneMetadata(contentType: .browser, title: "Drawer")
                )
            )
            atoms.workspaceFocusOwner.focusDrawerPane(
                parentPaneId: sourcePane.id,
                paneId: drawerPane.id
            )
            atoms.workspacePanePresentation.enterZoom(
                inTab: tab.id,
                sourcePaneId: sourcePane.id,
                viewerPresentation: .unavailable
            )

            let focusedPane = WorkspaceFocusedPaneResolver().resolve(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane),
                requestedOwner: atoms.workspaceFocusOwner.owner
            )
            let context = CommandContextDerived().currentContext(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane),
                focusedPane: focusedPane,
                workspacePanePresentation: atoms.workspacePanePresentation
            )

            #expect(context.focusedContentType == .webview)
            #expect(context.satisfiedRequirements.contains(.supportsTerminalZoom))
            #expect(context.satisfiedRequirements.contains(.hasActiveTerminalZoom))
        }
    }

    @Test
    func terminalMainPaneSupportsZoomWhileWebviewDrawerOwnsFocus() throws {
        try withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let terminalPane = store.createPane()
            let tab = Tab(paneId: terminalPane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            let webviewDrawerPane = try #require(
                atoms.workspacePane.addDrawerPane(
                    to: terminalPane.id,
                    content: .webview(WebviewState(url: URL(string: "https://drawer.example")!)),
                    metadata: PaneMetadata(contentType: .browser, title: "Drawer")
                )
            )
            atoms.workspaceFocusOwner.focusDrawerPane(
                parentPaneId: terminalPane.id,
                paneId: webviewDrawerPane.id
            )

            let focusedPane = WorkspaceFocusedPaneResolver().resolve(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane),
                requestedOwner: atoms.workspaceFocusOwner.owner
            )
            let context = CommandContextDerived().currentContext(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane),
                focusedPane: focusedPane,
                workspacePanePresentation: atoms.workspacePanePresentation
            )

            #expect(context.focusedContentType == .webview)
            #expect(context.satisfiedRequirements.contains(.supportsTerminalZoom))
            #expect(!context.satisfiedRequirements.contains(.hasActiveTerminalZoom))
        }
    }

    @Test
    func terminalDrawerDoesNotEnableZoomForWebviewMainPane() throws {
        try withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let webviewPane = store.createPane(
                content: .webview(WebviewState(url: URL(string: "https://main.example")!)),
                metadata: PaneMetadata(contentType: .browser, title: "Webview")
            )
            let tab = Tab(paneId: webviewPane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)
            let terminalDrawerPane = try #require(
                store.addDrawerPane(
                    to: webviewPane.id,
                    parentFallbackCWD: FileManager.default.homeDirectoryForCurrentUser
                )
            )
            atoms.workspaceFocusOwner.focusDrawerPane(
                parentPaneId: webviewPane.id,
                paneId: terminalDrawerPane.id
            )

            let focusedPane = WorkspaceFocusedPaneResolver().resolve(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane),
                requestedOwner: atoms.workspaceFocusOwner.owner
            )
            let context = CommandContextDerived().currentContext(
                workspaceTab: atom(\.workspaceTab),
                workspacePane: atom(\.workspacePane),
                focusedPane: focusedPane,
                workspacePanePresentation: atoms.workspacePanePresentation
            )

            #expect(context.focusedContentType == .terminal)
            #expect(!context.satisfiedRequirements.contains(.supportsTerminalZoom))
            #expect(!context.satisfiedRequirements.contains(.hasActiveTerminalZoom))
        }
    }
}
