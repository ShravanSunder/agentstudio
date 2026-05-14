import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("PaneInboxNotificationPopover")
struct PaneInboxNotificationPopoverTests {
    @Test("popover filters to pane-scope notifications not dismissed from pane inbox")
    func popoverFiltersRelevantNotifications() {
        let parentPaneId = UUID()
        let drawerChildPaneId = UUID()
        let parentVisible = makeNotification(paneId: parentPaneId, title: "Parent")
        let childVisible = makeNotification(paneId: drawerChildPaneId, title: "Child")
        let dismissed = makeNotification(
            paneId: drawerChildPaneId,
            title: "Dismissed",
            isDismissedFromPaneInbox: true
        )
        let unrelated = makeNotification(paneId: UUID(), title: "Other")

        let relevant = PaneInboxNotificationPopover.relevantNotifications(
            paneIds: [parentPaneId, drawerChildPaneId],
            notifications: [dismissed, unrelated, parentVisible, childVisible]
        )

        #expect(relevant.map(\.title) == ["Parent", "Child"])
    }

    @Test("unread mode hides read and pane-dismissed notifications before capping")
    func unreadModeFiltersUnreadActivePaneNotificationsBeforeCapping() {
        let paneId = UUID()
        let newestRead = makeNotification(
            paneId: paneId,
            title: "Read",
            timestamp: Date(timeIntervalSince1970: 200),
            isRead: true
        )
        let newestDismissed = makeNotification(
            paneId: paneId,
            title: "Dismissed",
            timestamp: Date(timeIntervalSince1970: 190),
            isDismissedFromPaneInbox: true
        )
        let unreadNotifications = (0..<30).map { index in
            makeNotification(
                paneId: paneId,
                title: "Unread \(index)",
                timestamp: Date(timeIntervalSince1970: TimeInterval(100 - index))
            )
        }

        let relevant = PaneInboxNotificationPopover.relevantNotifications(
            paneIds: [paneId],
            notifications: [newestRead, newestDismissed] + unreadNotifications,
            filterMode: .unread
        )

        #expect(relevant.count == AppPolicies.PaneInbox.maxVisibleNotifications)
        #expect(relevant.allSatisfy { !$0.isRead && !$0.isDismissedFromPaneInbox })
        #expect(relevant.first?.title == "Unread 0")
        #expect(relevant.last?.title == "Unread 24")
    }

    @Test("all mode includes read and pane-dismissed notifications before capping")
    func allModeIncludesReadAndPaneDismissedNotificationsBeforeCapping() {
        let paneId = UUID()
        let read = makeNotification(
            paneId: paneId,
            title: "Read",
            timestamp: Date(timeIntervalSince1970: 300),
            isRead: true
        )
        let dismissed = makeNotification(
            paneId: paneId,
            title: "Dismissed",
            timestamp: Date(timeIntervalSince1970: 290),
            isDismissedFromPaneInbox: true
        )
        let scopedNotifications = (0..<30).map { index in
            makeNotification(
                paneId: paneId,
                title: "Scoped \(index)",
                timestamp: Date(timeIntervalSince1970: TimeInterval(100 - index))
            )
        }
        let unrelated = makeNotification(
            paneId: UUID(),
            title: "Other",
            timestamp: Date(timeIntervalSince1970: 400)
        )

        let relevant = PaneInboxNotificationPopover.relevantNotifications(
            paneIds: [paneId],
            notifications: [unrelated, read, dismissed] + scopedNotifications,
            filterMode: .all
        )

        #expect(relevant.count == AppPolicies.PaneInbox.maxVisibleNotifications)
        #expect(relevant.map(\.title).prefix(2) == ["Read", "Dismissed"])
        #expect(relevant.contains { $0.title == "Other" } == false)
        #expect(relevant.last?.title == "Scoped 22")
    }

    @Test("popover includes drawer child notification from resolved parent pane scope")
    func popoverIncludesDrawerChildNotificationFromParentScope() {
        let parentPaneId = UUIDv7.generate()
        let drawerChildPaneId = UUIDv7.generate()
        let panes = makePaneLookup(parentPaneId: parentPaneId, drawerPaneId: drawerChildPaneId)
        let scope = PaneInboxScopeResolver.resolve(
            anchorPaneId: parentPaneId,
            pane: { panes[$0] }
        )
        let childNotification = makeNotification(paneId: drawerChildPaneId, title: "Drawer child")
        let unrelated = makeNotification(paneId: UUID(), title: "Other")

        let relevant = PaneInboxNotificationPopover.relevantNotifications(
            paneIds: scope.paneIds,
            notifications: [unrelated, childNotification]
        )

        #expect(scope.parentPaneId == parentPaneId)
        #expect(scope.paneIds == [parentPaneId, drawerChildPaneId])
        #expect(relevant.map(\.id) == [childNotification.id])
    }

    @Test("popover includes parent notification from resolved drawer child scope")
    func popoverIncludesParentNotificationFromDrawerChildScope() {
        let parentPaneId = UUIDv7.generate()
        let drawerChildPaneId = UUIDv7.generate()
        let panes = makePaneLookup(parentPaneId: parentPaneId, drawerPaneId: drawerChildPaneId)
        let scope = PaneInboxScopeResolver.resolve(
            anchorPaneId: drawerChildPaneId,
            pane: { panes[$0] }
        )
        let parentNotification = makeNotification(paneId: parentPaneId, title: "Parent")
        let childNotification = makeNotification(paneId: drawerChildPaneId, title: "Drawer child")

        let relevant = PaneInboxNotificationPopover.relevantNotifications(
            paneIds: scope.paneIds,
            notifications: [parentNotification, childNotification]
        )

        #expect(scope.parentPaneId == parentPaneId)
        #expect(scope.paneIds == [parentPaneId, drawerChildPaneId])
        #expect(relevant.map(\.id) == [parentNotification.id, childNotification.id])
    }

    @Test("keyboardItems maps relevant notifications to selectable popover items")
    func keyboardItemsForRelevantNotifications() {
        let paneId = UUID()
        let first = makeNotification(id: UUID(), paneId: paneId, title: "First")
        let second = makeNotification(id: UUID(), paneId: paneId, title: "Second")

        let keyboardItems = PaneInboxNotificationPopover.keyboardItems(
            for: [first, second]
        )

        #expect(keyboardItems.map(\.id) == [first.id, second.id])
        #expect(keyboardItems.map(\.shortcutNumber) == [1, 2])
        #expect(keyboardItems.allSatisfy { !$0.supportsAuxiliaryAction })
    }

    @Test("keyboardItems keeps every notification navigable while capping numbered shortcuts")
    func keyboardItemsKeepsEveryNotificationNavigableWhileCappingNumberedShortcuts() {
        let paneId = UUID()
        let notifications = (0..<(AppPolicies.SelectablePopover.maxNumberedShortcuts + 3)).map { index in
            makeNotification(id: UUID(), paneId: paneId, title: "Notification \(index)")
        }

        let keyboardItems = PaneInboxNotificationPopover.keyboardItems(for: notifications)

        #expect(keyboardItems.count == notifications.count)
        #expect(keyboardItems.map(\.id) == notifications.map(\.id))
        #expect(
            keyboardItems.map(\.shortcutNumber)
                == Array(1...AppPolicies.SelectablePopover.maxNumberedShortcuts).map(Optional.some)
                + Array(repeating: nil, count: 3)
        )
    }

    @Test("presenting and closing popover does not mark notifications read or dismissed")
    func presentingAndClosingPopoverDoesNotMarkNotificationsReadOrDismissed() {
        let parentPaneId = UUID()
        let notification = makeNotification(paneId: parentPaneId, title: "Passive")
        let inboxAtom = InboxNotificationAtom()
        let presentationAtom = PaneInboxPresentationAtom()
        var didClose = false
        inboxAtom.append(notification)

        let popover = PaneInboxNotificationPopover(
            parentPaneId: parentPaneId,
            paneIds: [parentPaneId],
            inboxAtom: inboxAtom,
            presentationAtom: presentationAtom,
            dispatcher: CommandDispatcher.shared,
            onActivate: { _ in },
            onClose: { didClose = true }
        )

        _ = popover.body
        popover.onClose()

        #expect(didClose)
        #expect(inboxAtom.notifications.first?.isRead == false)
        #expect(inboxAtom.notifications.first?.isDismissedFromPaneInbox == false)
    }

    private func makeNotification(
        id: UUID = UUID(),
        paneId: UUID?,
        title: String = "Notification",
        timestamp: Date? = nil,
        isRead: Bool = false,
        isDismissedFromPaneInbox: Bool = false
    ) -> InboxNotification {
        InboxNotification(
            id: id,
            timestamp: timestamp ?? Date(timeIntervalSince1970: isDismissedFromPaneInbox ? 50 : 100),
            kind: .agentRpc,
            title: title,
            body: nil,
            source: paneId.map { .pane(.init(paneId: $0)) } ?? .global,
            isRead: isRead,
            isDismissedFromPaneInbox: isDismissedFromPaneInbox
        )
    }

    private func makePaneLookup(parentPaneId: UUID, drawerPaneId: UUID) -> [UUID: Pane] {
        let parentPane = Pane(
            id: parentPaneId,
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(
                paneId: PaneId(uuid: parentPaneId),
                contentType: .terminal,
                source: .floating(launchDirectory: nil, title: nil),
                title: "Parent"
            ),
            kind: .layout(drawer: Drawer(paneIds: [drawerPaneId], activeChildId: drawerPaneId))
        )
        let drawerPane = Pane(
            id: drawerPaneId,
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(
                paneId: PaneId(uuid: drawerPaneId),
                contentType: .terminal,
                source: .floating(launchDirectory: nil, title: nil),
                title: "Drawer"
            ),
            kind: .drawerChild(parentPaneId: parentPaneId)
        )

        return [
            parentPane.id: parentPane,
            drawerPane.id: drawerPane,
        ]
    }
}
