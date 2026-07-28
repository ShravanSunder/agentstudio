import Foundation
import Testing

@testable import AgentStudio

extension PaneTabViewControllerCommandTests {
    @Test("programmatic Arrangements presentation activates the durable pane target tab")
    func presentArrangementPanel_activatesTargetTab() throws {
        let presentation = ArrangementPanelPresentationAtom()
        let windowId = UUID()
        let harness = makeHarness(
            arrangementPanelPresentation: presentation,
            workspaceWindowId: windowId
        )
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let firstPane = harness.store.createPane()
        let secondPane = harness.store.createPane()
        let firstTab = Tab(paneId: firstPane.id)
        let secondTab = Tab(paneId: secondPane.id)
        harness.store.appendTab(firstTab)
        harness.store.appendTab(secondTab)
        harness.store.setActiveTab(firstTab.id)

        let result = harness.controller.presentArrangementPanel(contextPaneId: secondPane.id)

        #expect(result?.tabId == secondTab.id)
        #expect(result?.contextPaneId == secondPane.id)
        #expect(harness.store.tabLayoutAtom.activeTabId == secondTab.id)
        #expect(presentation.pendingRequest?.tabId == secondTab.id)
        #expect(presentation.pendingRequest?.workspaceWindowId == windowId)
    }

    @Test("programmatic Arrangements presentation accepts a durable drawer-pane target")
    func presentArrangementPanel_acceptsDurableDrawerPaneTarget() throws {
        let presentation = ArrangementPanelPresentationAtom()
        let windowId = UUID()
        let harness = makeHarness(
            arrangementPanelPresentation: presentation,
            workspaceWindowId: windowId
        )
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let mainPane = harness.store.createPane()
        let tab = Tab(paneId: mainPane.id)
        harness.store.appendTab(tab)
        let drawerPane = try #require(harness.store.addDrawerPane(to: mainPane.id))

        let result = harness.controller.presentArrangementPanel(contextPaneId: drawerPane.id)

        #expect(result?.tabId == tab.id)
        #expect(result?.contextPaneId == drawerPane.id)
        #expect(harness.store.tabLayoutAtom.activeTabId == tab.id)
        #expect(presentation.pendingRequest?.tabId == tab.id)
        #expect(presentation.pendingRequest?.workspaceWindowId == windowId)
    }

    @Test("programmatic Arrangements presentation remains available when all panes are minimized")
    func presentArrangementPanel_allMinimizedLayout() throws {
        let presentation = ArrangementPanelPresentationAtom()
        let windowId = UUID()
        let harness = makeHarness(
            arrangementPanelPresentation: presentation,
            workspaceWindowId: windowId
        )
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let pane = harness.store.createPane()
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let layoutId = try #require(harness.store.createArrangement(name: "Layout 1", inTab: tab.id))
        harness.store.switchArrangement(to: layoutId, inTab: tab.id)
        #expect(harness.store.minimizePane(pane.id, inTab: tab.id))
        #expect(harness.store.tab(tab.id)?.activePaneId == nil)

        let result = harness.controller.presentArrangementPanel(contextPaneId: nil)

        #expect(result?.tabId == tab.id)
        #expect(result?.contextPaneId == nil)
        #expect(presentation.pendingRequest?.tabId == tab.id)
        #expect(presentation.pendingRequest?.workspaceWindowId == windowId)
    }
}
