import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

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

        atom(\.workspaceFocusOwner).focusMainPane(firstPane.id)

        let result = try harness.controller.presentArrangementPanel(contextPaneId: secondPane.id).get()

        #expect(result.workspaceWindowId == windowId)
        #expect(result.tabId == secondTab.id)
        #expect(result.contextPaneId == secondPane.id)
        #expect(harness.store.tabLayoutAtom.activeTabId == secondTab.id)
        #expect(atom(\.workspaceFocusOwner).owner == .mainPane(paneId: secondPane.id))
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

        let result = try harness.controller.presentArrangementPanel(contextPaneId: drawerPane.id).get()

        #expect(result.workspaceWindowId == windowId)
        #expect(result.tabId == tab.id)
        #expect(result.contextPaneId == drawerPane.id)
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

        let result = try harness.controller.presentArrangementPanel(contextPaneId: nil).get()

        #expect(result.workspaceWindowId == windowId)
        #expect(result.tabId == tab.id)
        #expect(result.contextPaneId == nil)
        #expect(presentation.pendingRequest?.tabId == tab.id)
        #expect(presentation.pendingRequest?.workspaceWindowId == windowId)
    }

    @Test("programmatic Arrangements presentation reports the presenter-owned workspace window")
    func presentArrangementPanel_reportsPresenterOwnedWorkspaceWindow() throws {
        let presenterWindowId = UUID()
        let differentPreferredWindowId = UUID()
        let windowLifecycleStore = WindowLifecycleAtom()
        windowLifecycleStore.recordWindowRegistered(differentPreferredWindowId)
        windowLifecycleStore.recordWindowBecameKey(differentPreferredWindowId)
        let harness = makeHarness(
            windowLifecycleStore: windowLifecycleStore,
            workspaceWindowId: presenterWindowId
        )
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let pane = harness.store.createPane()
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)

        let result = try harness.controller.presentArrangementPanel(contextPaneId: nil).get()

        #expect(result.workspaceWindowId == presenterWindowId)
        #expect(harness.arrangementPanelPresentation.pendingRequest?.workspaceWindowId == presenterWindowId)
    }

    @Test("programmatic Arrangements presentation distinguishes a missing workspace window")
    func presentArrangementPanel_reportsNoActiveWindow() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let pane = harness.store.createPane()
        harness.store.appendTab(Tab(paneId: pane.id))

        let result = harness.controller.presentArrangementPanel(contextPaneId: nil)

        #expect(result == .failure(.noActiveWindow))
    }

    @Test("programmatic Arrangements presentation distinguishes a stale explicit pane target")
    func presentArrangementPanel_reportsTargetNotFound() {
        let harness = makeHarness(workspaceWindowId: UUID())
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let result = harness.controller.presentArrangementPanel(contextPaneId: UUID())

        #expect(result == .failure(.targetNotFound))
    }

    @Test("programmatic Arrangements presentation distinguishes an empty workspace")
    func presentArrangementPanel_reportsValidationRejectedWithoutPresentableTab() {
        let harness = makeHarness(workspaceWindowId: UUID())
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let result = harness.controller.presentArrangementPanel(contextPaneId: nil)

        #expect(result == .failure(.validationRejected))
    }
}
