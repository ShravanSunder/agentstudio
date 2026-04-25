import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("InboxNotificationDrawerPresenter")
struct InboxNotificationDrawerPresenterTests {
    @Test("open request stores drawer pane ids")
    func openRequestStoresDrawerPaneIds() {
        let presenter = InboxNotificationDrawerPresenter()
        let parentPaneId = UUID()
        let paneIds = [UUID(), UUID()]

        presenter.open(parentPaneId: parentPaneId, drawerPaneIds: paneIds)

        #expect(presenter.request?.parentPaneId == parentPaneId)
        #expect(presenter.request?.drawerPaneIds == paneIds)
    }

    @Test("active expanded drawer resolves to visible drawer pane ids")
    func activeExpandedDrawerResolvesPaneIds() throws {
        let store = WorkspaceStore()
        store.restore()
        let parentPane = store.createPane(source: .floating(launchDirectory: nil, title: nil))
        let firstDrawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        let secondDrawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        let tab = makeTab(paneIds: [parentPane.id], activePaneId: parentPane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let paneIds = store.visiblePaneIdsForActiveExpandedDrawer()

        #expect(paneIds == [firstDrawerPane.id, secondDrawerPane.id])
        #expect(
            store.activeDrawerInboxSelection()
                == .available(
                    ActiveDrawerInboxTarget(
                        parentPaneId: parentPane.id,
                        drawerPaneIds: [firstDrawerPane.id, secondDrawerPane.id]
                    )
                )
        )
    }

    @Test("active drawer child resolves to parent drawer target")
    func activeDrawerChildResolvesParentDrawerTarget() throws {
        let store = WorkspaceStore()
        store.restore()
        let parentPane = store.createPane(source: .floating(launchDirectory: nil, title: nil))
        let drawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        let tab = makeTab(paneIds: [parentPane.id], activePaneId: drawerPane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let paneIds = store.visiblePaneIdsForActiveExpandedDrawer()

        #expect(paneIds == [drawerPane.id])
        #expect(
            store.activeDrawerInboxSelection()
                == .available(ActiveDrawerInboxTarget(parentPaneId: parentPane.id, drawerPaneIds: [drawerPane.id]))
        )
    }

    @Test("active pane without drawer pane ids resolves nil")
    func activePaneWithoutDrawerPaneIdsResolvesNil() {
        let store = WorkspaceStore()
        store.restore()
        let pane = store.createPane(source: .floating(launchDirectory: nil, title: nil))
        let tab = makeTab(paneIds: [pane.id], activePaneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let paneIds = store.visiblePaneIdsForActiveExpandedDrawer()

        #expect(paneIds == nil)
        #expect(store.activeDrawerInboxSelection() == .drawerCollapsed)
    }

    @Test("drawer inbox command opens presenter for active drawer through command execution")
    func drawerInboxCommandOpensPresenter() throws {
        let store = WorkspaceStore()
        store.restore()
        let parentPane = store.createPane(source: .floating(launchDirectory: nil, title: nil))
        let drawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        let tab = makeTab(paneIds: [parentPane.id], activePaneId: parentPane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)
        let presenter = InboxNotificationDrawerPresenter()
        let delegate = AppDelegate()
        delegate.store = store
        delegate.inboxNotificationDrawerPresenter = presenter

        let didExecute = delegate.execute(.showDrawerInboxNotifications)

        #expect(didExecute)
        #expect(presenter.request?.parentPaneId == parentPane.id)
        #expect(presenter.request?.drawerPaneIds == [drawerPane.id])
    }

    @Test("drawer inbox command is a no-op outside a drawer")
    func drawerInboxCommandNoOpsOutsideDrawer() {
        let store = WorkspaceStore()
        store.restore()
        let pane = store.createPane(source: .floating(launchDirectory: nil, title: nil))
        let tab = makeTab(paneIds: [pane.id], activePaneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)
        let presenter = InboxNotificationDrawerPresenter()
        let delegate = AppDelegate()
        delegate.store = store
        delegate.inboxNotificationDrawerPresenter = presenter

        delegate.openDrawerInboxForActiveDrawer()

        #expect(presenter.request == nil)
    }
}
