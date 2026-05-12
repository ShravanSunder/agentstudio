import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("MainSplitViewController pane inbox clear", .serialized)
struct MainSplitViewControllerPaneInboxClearTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("production pane inbox clear wiring marks parent and drawer rows read")
    func productionPaneInboxClearWiringMarksScopedRowsRead() async throws {
        let inboxAtom = InboxNotificationAtom()
        try await withMainSplitViewControllerHarness(withRepos: true, inboxAtom: inboxAtom) { harness in
            let parentPane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
            let parentTab = Tab(paneId: parentPane.id)
            harness.store.appendTab(parentTab)
            harness.store.setActiveTab(parentTab.id)
            let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
            let unrelatedPane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Other"))

            inboxAtom.append(Self.makePaneInboxNotification(paneId: parentPane.id))
            inboxAtom.append(Self.makePaneInboxNotification(paneId: drawerPane.id))
            inboxAtom.append(Self.makePaneInboxNotification(paneId: unrelatedPane.id))

            let presentation = harness.controller.makePaneInboxPresentation()
            presentation.clearNotifications(parentPane.id, [parentPane.id, drawerPane.id])

            #expect(inboxAtom.visiblePaneInboxUnreadCount(forPaneIds: [parentPane.id, drawerPane.id]) == 0)
            #expect(inboxAtom.unreadCount(forPaneId: unrelatedPane.id) == 1)
            #expect(inboxAtom.globalUnreadCount == 1)
        }
    }

    private static func makePaneInboxNotification(paneId: UUID) -> InboxNotification {
        InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 1),
            kind: .agentDesktopNotification,
            title: "Pane inbox",
            body: nil,
            source: .pane(.init(paneId: paneId, runtimeDisplayLabel: "Terminal")),
            isRead: false,
            isDismissedFromPaneInbox: false
        )
    }
}
