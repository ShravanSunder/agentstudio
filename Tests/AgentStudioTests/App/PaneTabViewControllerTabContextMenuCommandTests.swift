import Foundation
import Observation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct PaneTabViewControllerTabContextMenuCommandTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    private final class ObservationInvalidationFlag: @unchecked Sendable {
        var didFire = false
    }

    @Test("tab command capability ignores unrelated repository topology changes")
    func canExecuteTabCommand_doesNotObserveRepositoryTopology() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let pane = harness.store.createPane()
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)
        let invalidation = ObservationInvalidationFlag()

        withObservationTracking {
            _ = harness.controller.canExecute(
                .closeTab,
                target: tab.id,
                targetType: .tab
            )
        } onChange: {
            invalidation.didFire = true
        }

        let repositoryPath = harness.tempDir.appending(path: "unrelated-repository")
        _ = harness.store.addRepo(at: repositoryPath)

        #expect(!invalidation.didFire)
    }

    @Test("targeted split capability rejects a zoomed tab")
    func canExecuteSplit_zoomedTab() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let pane = harness.store.createPane()
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)
        harness.store.panePresentationAtom.enterZoom(
            inTab: tab.id,
            sourcePaneId: pane.id,
            viewerPresentation: .unavailable
        )

        #expect(
            !harness.controller.canExecute(
                .splitRight,
                target: tab.id,
                targetType: .tab
            )
        )
        #expect(
            !harness.controller.canExecute(
                .splitLeft,
                target: tab.id,
                targetType: .tab
            )
        )
    }

    @Test("targeted Equalize Panes uses the clicked inactive tab")
    func canExecuteEqualizePanes_clickedInactiveSplitTab() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let activePane = harness.store.createPane()
        let inactiveFirstPane = harness.store.createPane()
        let inactiveSecondPane = harness.store.createPane()
        let activeTab = Tab(paneId: activePane.id, name: "Active")
        let inactiveTab = Tab(paneId: inactiveFirstPane.id, name: "Inactive")
        harness.store.appendTab(activeTab)
        harness.store.appendTab(inactiveTab)
        harness.store.insertPane(
            inactiveSecondPane.id,
            inTab: inactiveTab.id,
            at: inactiveFirstPane.id,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )
        harness.store.setActiveTab(activeTab.id)

        #expect(
            harness.controller.canExecute(
                .equalizePanes,
                target: inactiveTab.id,
                targetType: .tab
            )
        )
        #expect(harness.store.activeTabId == activeTab.id)
    }

    @Test("tab context-menu catalog declares every command row as a real tab target")
    func catalogDeclaresRealTabTargets() {
        #expect(
            AppCommand.splitRight.definition.targeting
                == .contextualAndTargeted(
                    [.pane, .tab],
                    preferredInvocation: .contextual
                )
        )
        #expect(
            AppCommand.splitLeft.definition.targeting
                == .contextualAndTargeted(
                    [.tab],
                    preferredInvocation: .contextual
                )
        )
        #expect(
            AppCommand.equalizePanes.definition.targeting
                == .contextualAndTargeted(
                    [.tab],
                    preferredInvocation: .contextual
                )
        )
        #expect(
            AppCommand.saveArrangement.definition.targeting
                == .contextualAndTargeted(
                    [.tab],
                    preferredInvocation: .contextual
                )
        )
        #expect(
            AppCommand.newFloatingTerminal.definition.targeting
                == .contextualAndTargeted(
                    [.tab],
                    preferredInvocation: .contextual
                )
        )
    }

    @Test("clicked split tab owns split-only rows when the active tab is unsplit")
    func presentation_clickedSplitTabIgnoresActiveUnsplitTab() {
        let activeTabIsSplit = false
        let clickedTabIsSplit = true

        let commands = TabPillView.presentedCommands(
            clickedTabIsSplit: clickedTabIsSplit
        )

        #expect(!activeTabIsSplit)
        #expect(
            commands.filter { [.renameTab, .closeTab, .breakUpTab].contains($0) }
                == [.renameTab, .closeTab, .breakUpTab]
        )
        #expect(commands.contains(.equalizePanes))
    }

    @Test("clicked unsplit tab omits split-only rows when the active tab is split")
    func presentation_clickedUnsplitTabIgnoresActiveSplitTab() {
        let activeTabIsSplit = true
        let clickedTabIsSplit = false

        let commands = TabPillView.presentedCommands(
            clickedTabIsSplit: clickedTabIsSplit
        )

        #expect(activeTabIsSplit)
        #expect(
            commands.filter { [.renameTab, .closeTab, .breakUpTab].contains($0) }
                == [.renameTab, .closeTab]
        )
        #expect(!commands.contains(.equalizePanes))
    }

    @Test("tab context menu filters undeclared rows and has no dead arrangement commands")
    func presentation_filtersCommandsAndOmitsDeadArrangementRows() {
        let commands = TabPillView.presentedCommands(
            clickedTabIsSplit: true
        )

        #expect(commands.contains(.splitRight))
        #expect(commands.contains(.splitLeft))
        #expect(commands.contains(.newFloatingTerminal))
        #expect(commands.contains(.saveArrangement))
        #expect(LocalActionSpec.showArrangements.actionSpec.label == "Show Arrangements")
        #expect(!commands.contains(.switchArrangement))
        #expect(!commands.contains(.deleteArrangement))
        #expect(!commands.contains(.renameArrangement))
    }

    @Test("tab-pill close uses targeted inline presentation and rechecks capability")
    func tabPillCloseUsesTargetedInlineAction() throws {
        var isEnabled = true
        var capabilityQueries: [AppCommand] = []
        var dispatchedCommands: [AppCommand] = []
        let closeAction = try #require(
            TabPillView.inlineCommandAction(
                command: .closeTab,
                canDispatchCommand: { command in
                    capabilityQueries.append(command)
                    return isEnabled
                },
                onCommand: { dispatchedCommands.append($0) }
            )
        )

        #expect(closeAction.commandSpec.command == .closeTab)
        #expect(closeAction.isEnabled)
        #expect(capabilityQueries == [.closeTab])

        isEnabled = false
        closeAction.perform()

        #expect(capabilityQueries == [.closeTab, .closeTab])
        #expect(dispatchedCommands.isEmpty)

        #expect(
            TabPillView.inlineCommandAction(
                command: .renameTab,
                canDispatchCommand: { _ in true },
                onCommand: { _ in }
            ) == nil
        )
    }

    @Test("tab context-menu targeted capability rejects a stale tab")
    func canExecuteTabCommands_rejectsStaleTab() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let staleTabId = UUID()

        for command in [
            AppCommand.renameTab,
            .closeTab,
            .breakUpTab,
            .splitRight,
            .splitLeft,
            .equalizePanes,
            .saveArrangement,
            .newFloatingTerminal,
        ] {
            #expect(
                !harness.controller.canExecute(
                    command,
                    target: staleTabId,
                    targetType: .tab
                )
            )
        }
    }

    @Test("Split Right preserves its existing pane-targeted inline capability")
    func canExecuteSplitRight_targetedPane() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = harness.store.createPane()
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)

        #expect(
            harness.controller.canExecute(
                .splitRight,
                target: pane.id,
                targetType: .pane
            )
        )
    }

    @Test("targeted split uses the clicked inactive tab active pane and cwd")
    func executeSplitRight_clickedInactiveTabUsesItsPaneAndCWD() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let activeDirectory = harness.tempDir.appending(path: "active", directoryHint: .isDirectory)
        let clickedDirectory = harness.tempDir.appending(path: "clicked", directoryHint: .isDirectory)
        let activePane = harness.store.createPane(
            launchDirectory: activeDirectory,
            facets: PaneContextFacets(cwd: activeDirectory)
        )
        let clickedPane = harness.store.createPane(
            launchDirectory: clickedDirectory,
            facets: PaneContextFacets(cwd: clickedDirectory)
        )
        let activeTab = Tab(paneId: activePane.id, name: "Active")
        let clickedTab = Tab(paneId: clickedPane.id, name: "Clicked")
        harness.store.appendTab(activeTab)
        harness.store.appendTab(clickedTab)
        harness.store.setActiveTab(activeTab.id)
        harness.windowLifecycleStore.recordTerminalContainerBounds(
            CGRect(x: 0, y: 0, width: 1000, height: 600)
        )

        harness.controller.execute(
            .splitRight,
            target: clickedTab.id,
            targetType: .tab
        )

        #expect(harness.surfaceManager.createSurfaceCallCount == 1)
        #expect(harness.surfaceManager.lastCreatedSurfaceMetadata?.cwd == clickedDirectory)
        #expect(harness.store.activeTabId == activeTab.id)
    }

    @Test("targeted floating terminal uses the clicked inactive tab active pane cwd")
    func executeNewFloatingTerminal_clickedInactiveTabUsesItsCWD() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let activeDirectory = harness.tempDir.appending(path: "active", directoryHint: .isDirectory)
        let clickedDirectory = harness.tempDir.appending(path: "clicked", directoryHint: .isDirectory)
        let activePane = harness.store.createPane(
            launchDirectory: activeDirectory,
            facets: PaneContextFacets(cwd: activeDirectory)
        )
        let clickedPane = harness.store.createPane(
            launchDirectory: clickedDirectory,
            facets: PaneContextFacets(cwd: clickedDirectory)
        )
        let activeTab = Tab(paneId: activePane.id, name: "Active")
        let clickedTab = Tab(paneId: clickedPane.id, name: "Clicked")
        harness.store.appendTab(activeTab)
        harness.store.appendTab(clickedTab)
        harness.store.setActiveTab(activeTab.id)
        harness.windowLifecycleStore.recordTerminalContainerBounds(
            CGRect(x: 0, y: 0, width: 1000, height: 600)
        )
        let initialTabCount = harness.store.tabLayoutAtom.tabs.count

        harness.controller.execute(
            .newFloatingTerminal,
            target: clickedTab.id,
            targetType: .tab
        )

        #expect(harness.surfaceManager.createSurfaceCallCount == 1)
        #expect(harness.surfaceManager.lastCreatedSurfaceMetadata?.cwd == clickedDirectory)
        #expect(harness.store.tabLayoutAtom.tabs.count == initialTabCount + 1)
        #expect(harness.store.activeTabId == harness.store.tabLayoutAtom.tabs.last?.id)
    }

    @Test("targeted Save Arrangement mutates the clicked inactive tab")
    func executeSaveArrangement_clickedInactiveTab() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let activePane = harness.store.createPane()
        let clickedPane = harness.store.createPane()
        let activeTab = Tab(paneId: activePane.id, name: "Active")
        let clickedTab = Tab(paneId: clickedPane.id, name: "Clicked")
        harness.store.appendTab(activeTab)
        harness.store.appendTab(clickedTab)
        harness.store.setActiveTab(activeTab.id)
        let initialArrangementCount = clickedTab.arrangements.count

        harness.controller.execute(
            .saveArrangement,
            target: clickedTab.id,
            targetType: .tab
        )

        #expect(
            harness.store.tab(clickedTab.id)?.arrangements.count
                == initialArrangementCount + 1
        )
        #expect(harness.store.activeTabId == activeTab.id)
    }

    @Test("targeted context-free terminal uses home CWD while splits require an active pane")
    func canExecuteTabCommands_allMinimizedClickedTab() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let activePane = harness.store.createPane()
        let minimizedPane = harness.store.createPane()
        let activeTab = Tab(paneId: activePane.id, name: "Active")
        let minimizedTab = Tab(paneId: minimizedPane.id, name: "Minimized")
        harness.store.appendTab(activeTab)
        harness.store.appendTab(minimizedTab)
        #expect(harness.store.minimizePane(minimizedPane.id, inTab: minimizedTab.id))
        harness.store.setActiveTab(activeTab.id)
        harness.windowLifecycleStore.recordTerminalContainerBounds(
            CGRect(x: 0, y: 0, width: 1000, height: 600)
        )
        let initialTabCount = harness.store.tabLayoutAtom.tabs.count

        #expect(
            !harness.controller.canExecute(
                .splitRight,
                target: minimizedTab.id,
                targetType: .tab
            )
        )
        #expect(
            !harness.controller.canExecute(
                .splitLeft,
                target: minimizedTab.id,
                targetType: .tab
            )
        )
        #expect(
            harness.controller.canExecute(
                .newFloatingTerminal,
                target: minimizedTab.id,
                targetType: .tab
            )
        )

        harness.controller.execute(
            .newFloatingTerminal,
            target: minimizedTab.id,
            targetType: .tab
        )

        #expect(harness.surfaceManager.createSurfaceCallCount == 1)
        #expect(harness.store.tabLayoutAtom.tabs.count == initialTabCount + 1)
        let createdTab = try #require(harness.store.tabLayoutAtom.tabs.last)
        let createdPaneId = try #require(createdTab.activePaneId)
        let createdPane = try #require(harness.store.paneAtom.pane(createdPaneId))
        #expect(createdPane.metadata.launchDirectory == FileManager.default.homeDirectoryForCurrentUser)
        #expect(createdPane.metadata.facets.cwd == FileManager.default.homeDirectoryForCurrentUser)
        #expect(harness.store.activeTabId == createdTab.id)
    }

    @Test("Show Arrangements local action activates and opens the clicked tab panel")
    func showArrangements_clickedInactiveTab() throws {
        let workspaceWindowId = UUID()
        let presentation = ArrangementPanelPresentationAtom()
        let harness = makeHarness(
            arrangementPanelPresentation: presentation,
            workspaceWindowId: workspaceWindowId
        )
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let activePane = harness.store.createPane()
        let clickedPane = harness.store.createPane()
        let activeTab = Tab(paneId: activePane.id, name: "Active")
        let clickedTab = Tab(paneId: clickedPane.id, name: "Clicked")
        harness.store.appendTab(activeTab)
        harness.store.appendTab(clickedTab)
        harness.store.setActiveTab(activeTab.id)

        harness.controller.showTabContextMenuArrangements(tabId: clickedTab.id)

        let request = try #require(presentation.pendingRequest)
        #expect(harness.store.activeTabId == clickedTab.id)
        #expect(request.tabId == clickedTab.id)
        #expect(request.workspaceWindowId == workspaceWindowId)
    }
}
