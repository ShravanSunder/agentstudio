import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("InboxNotificationDrawerPresenter")
struct InboxNotificationDrawerPresenterTests {
    @Test("open request stores drawer pane ids")
    func openRequestStoresDrawerPaneIds() {
        let presenter = InboxNotificationDrawerPresenter()
        let paneIds = [UUID(), UUID()]

        presenter.open(forDrawerPaneIds: paneIds)

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
    }
}
