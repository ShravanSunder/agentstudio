import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct PaneTabViewControllerTargetedPaneCommandTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("targeted Expand Pane restores a minimized main pane")
    func expandPane_minimizedMainPane_restoresPane() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = harness.store.createPane()
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        #expect(harness.store.minimizePane(pane.id, inTab: tab.id))

        #expect(
            harness.controller.canExecute(
                .expandPane,
                target: pane.id,
                targetType: .pane
            )
        )

        harness.controller.execute(
            .expandPane,
            target: pane.id,
            targetType: .pane
        )

        #expect(harness.store.tab(tab.id)?.activeMinimizedPaneIds.contains(pane.id) == false)
    }

    @Test("targeted Expand Pane restores a minimized drawer child")
    func expandPane_minimizedDrawerChild_restoresPane() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane()
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        #expect(harness.store.minimizeDrawerPane(drawerPane.id, in: parentPane.id))

        #expect(
            harness.controller.canExecute(
                .expandPane,
                target: drawerPane.id,
                targetType: .pane
            )
        )

        harness.controller.execute(
            .expandPane,
            target: drawerPane.id,
            targetType: .pane
        )

        #expect(harness.store.drawerView(forParent: parentPane.id)?.minimizedPaneIds.contains(drawerPane.id) == false)
    }

    @Test("targeted Minimize Pane minimizes a visible main pane")
    func minimizePane_visibleMainPane_minimizesPane() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = harness.store.createPane()
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)

        #expect(
            harness.controller.canExecute(
                .minimizePane,
                target: pane.id,
                targetType: .pane
            )
        )

        harness.controller.execute(
            .minimizePane,
            target: pane.id,
            targetType: .pane
        )

        #expect(harness.store.tab(tab.id)?.activeMinimizedPaneIds.contains(pane.id) == true)
    }

    @Test("targeted Minimize Pane minimizes a visible drawer child")
    func minimizePane_visibleDrawerChild_minimizesPane() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane()
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))

        #expect(
            harness.controller.canExecute(
                .minimizePane,
                target: drawerPane.id,
                targetType: .pane
            )
        )

        harness.controller.execute(
            .minimizePane,
            target: drawerPane.id,
            targetType: .pane
        )

        #expect(harness.store.drawerView(forParent: parentPane.id)?.minimizedPaneIds.contains(drawerPane.id) == true)
    }

    @Test("targeted Toggle Drawer accepts the owned main pane and rejects its drawer child")
    func toggleDrawer_ownedMainPane_togglesOnlyParent() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane()
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        let drawer = try #require(harness.store.pane(parentPane.id)?.drawer)
        let wasExpanded = drawer.isExpanded

        #expect(
            harness.controller.canExecute(
                .toggleDrawer,
                target: parentPane.id,
                targetType: .pane
            )
        )
        #expect(
            !harness.controller.canExecute(
                .toggleDrawer,
                target: drawerPane.id,
                targetType: .pane
            )
        )

        harness.controller.execute(
            .toggleDrawer,
            target: parentPane.id,
            targetType: .pane
        )

        #expect(harness.store.pane(parentPane.id)?.drawer?.isExpanded == !wasExpanded)
    }

    @Test("targeted pane location commands use the exact drawer child path")
    func paneLocationCommands_drawerChild_useTargetPath() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentDirectory = harness.tempDir.appending(path: "parent")
        let drawerDirectory = harness.tempDir.appending(path: "drawer")
        let parentPane = harness.store.createPane(
            launchDirectory: parentDirectory,
            facets: PaneContextFacets(cwd: parentDirectory)
        )
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        harness.store.paneAtom.updatePaneCWD(drawerPane.id, cwd: drawerDirectory)

        for command in [
            AppCommand.openPaneLocationInFinder,
            .copyCurrentPanePath,
            .openPaneLocationInEditorMenu,
        ] {
            #expect(
                harness.controller.canExecute(
                    command,
                    target: drawerPane.id,
                    targetType: .pane
                )
            )
        }

        harness.controller.execute(
            .openPaneLocationInFinder,
            target: drawerPane.id,
            targetType: .pane
        )
        harness.controller.execute(
            .copyCurrentPanePath,
            target: drawerPane.id,
            targetType: .pane
        )
        harness.controller.execute(
            .openPaneLocationInEditorMenu,
            target: drawerPane.id,
            targetType: .pane
        )

        #expect(harness.launchRecorder.revealedPaths == [drawerDirectory])
        #expect(harness.launchRecorder.copiedPaths == [drawerDirectory])
        #expect(harness.atomRegistry.editorChooser.openForPaneId == drawerPane.id)
        #expect(harness.atomRegistry.editorChooser.availableTargets.map(\.id) == ["cursor", "vscode"])
    }

    @Test("targeted pane commands reject stale pane identities")
    func targetedPaneCommands_stalePane_rejectWithoutSideEffects() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let stalePaneId = UUID()

        for command in [
            AppCommand.expandPane,
            .minimizePane,
            .toggleDrawer,
            .openPaneLocationInFinder,
            .copyCurrentPanePath,
            .openPaneLocationInEditorMenu,
        ] {
            #expect(
                !harness.controller.canExecute(
                    command,
                    target: stalePaneId,
                    targetType: .pane
                )
            )
            harness.controller.execute(
                command,
                target: stalePaneId,
                targetType: .pane
            )
        }

        #expect(harness.launchRecorder.revealedPaths.isEmpty)
        #expect(harness.launchRecorder.copiedPaths.isEmpty)
        #expect(harness.atomRegistry.editorChooser.openForPaneId == nil)
    }

    @Test("targeted Move Pane capability requires an owned source and nonempty alternate tab")
    func movePaneToTabCapability_requiresOwnedSourceAndNonemptyAlternateTab() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let sourcePane = harness.store.createPane()
        let sourceTab = Tab(paneId: sourcePane.id)
        harness.store.appendTab(sourceTab)
        harness.store.setActiveTab(sourceTab.id)

        #expect(
            !harness.controller.canExecute(
                .movePaneToTab,
                target: sourcePane.id,
                targetType: .pane
            )
        )

        let destinationPane = harness.store.createPane()
        let destinationTab = Tab(paneId: destinationPane.id)
        harness.store.appendTab(destinationTab)

        #expect(
            harness.controller.canExecute(
                .movePaneToTab,
                target: sourcePane.id,
                targetType: .pane
            )
        )
        #expect(
            !harness.controller.canExecute(
                .movePaneToTab,
                target: UUID(),
                targetType: .pane
            )
        )
    }

    @Test("Move Pane routes the source pane to the selected nonempty destination")
    func movePaneToTab_selectedDestination_receivesSourcePane() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let sourcePane = harness.store.createPane()
        let sourceTab = Tab(paneId: sourcePane.id)
        let otherDestinationPane = harness.store.createPane()
        let otherDestinationTab = Tab(paneId: otherDestinationPane.id)
        let selectedDestinationPane = harness.store.createPane()
        let selectedDestinationTab = Tab(paneId: selectedDestinationPane.id)
        harness.store.appendTab(sourceTab)
        harness.store.appendTab(otherDestinationTab)
        harness.store.appendTab(selectedDestinationTab)
        harness.store.setActiveTab(sourceTab.id)

        harness.controller.executeMovePaneToTab(
            sourcePaneId: sourcePane.id,
            sourceTabId: sourceTab.id,
            targetTabId: selectedDestinationTab.id
        )

        #expect(harness.store.tab(selectedDestinationTab.id)?.activePaneIds.contains(sourcePane.id) == true)
        #expect(harness.store.tab(otherDestinationTab.id)?.activePaneIds.contains(sourcePane.id) == false)
    }

    @Test("Move Pane presentation enables with a destination and rechecks before activation")
    func movePaneToTabPresentation_destinationRemovedBeforeActivation_doesNotMove() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let sourcePane = harness.store.createPane()
        let sourceTab = Tab(paneId: sourcePane.id)
        let destinationPane = harness.store.createPane()
        let destinationTab = Tab(paneId: destinationPane.id)
        harness.store.appendTab(sourceTab)
        harness.store.appendTab(destinationTab)
        harness.store.setActiveTab(sourceTab.id)

        try await withIsolatedCommandDispatcher(
            configure: {
                AppCommandDispatcher.shared.handler = harness.controller
                AppCommandDispatcher.shared.appCommandRouter = nil
            },
            body: {
                atom(\.managementLayer).activate()
                defer { atom(\.managementLayer).deactivate() }
                let presentation = try #require(
                    PaneLeafCommandPresentation.resolve(
                        command: .movePaneToTab,
                        surface: .inlineControl,
                        targetPaneId: sourcePane.id,
                        dispatcher: AppCommandDispatcher.shared
                    )
                )
                #expect(presentation.isEnabled)

                harness.store.removeTab(destinationTab.id)
                presentation.movePane(
                    sourceTabId: sourceTab.id,
                    targetTabId: destinationTab.id
                )

                #expect(harness.store.tab(sourceTab.id)?.activePaneIds.contains(sourcePane.id) == true)
            }
        )
    }
}
