import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("InboxNotificationAtom")
struct InboxNotificationAtomTests {
    private func makeInboxNotification(
        id: UUID = UUID(),
        paneId: UUID? = nil,
        worktreeId: UUID? = nil,
        tabId: UUID? = nil,
        isRead: Bool = false,
        isDismissedFromDrawer: Bool = false,
        timestamp: Date = Date()
    ) -> InboxNotification {
        InboxNotification(
            id: id,
            timestamp: timestamp,
            kind: .agentDesktopNotification,
            title: "Test",
            body: nil,
            source: makeSource(
                paneId: paneId,
                tabId: tabId,
                worktreeId: worktreeId
            ),
            isRead: isRead,
            isDismissedFromDrawer: isDismissedFromDrawer
        )
    }

    private func makeSource(
        paneId: UUID?,
        tabId: UUID?,
        worktreeId: UUID?
    ) -> InboxNotification.Source {
        guard paneId != nil || tabId != nil || worktreeId != nil else { return .global }
        return .pane(
            .init(
                paneId: paneId ?? UUID(),
                tabId: tabId,
                worktreeId: worktreeId,
                worktreeName: worktreeId == nil ? nil : "main"
            )
        )
    }

    @Test("append adds to notifications")
    func appendAdds() {
        let atom = InboxNotificationAtom()
        #expect(atom.notifications.isEmpty)
        atom.append(makeInboxNotification())
        #expect(atom.notifications.count == 1)
    }

    @Test("append replaces existing notification with same id")
    func appendReplacesDuplicateId() {
        let atom = InboxNotificationAtom()
        let id = UUID()
        let original = makeInboxNotification(
            id: id,
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let retry = makeInboxNotification(
            id: id,
            timestamp: Date(timeIntervalSince1970: 2)
        )

        atom.append(original)
        atom.append(retry)

        #expect(atom.notifications == [retry])
    }

    @Test("markRead(id:) sets isRead true")
    func markReadById() {
        let atom = InboxNotificationAtom()
        let notification = makeInboxNotification()
        atom.append(notification)
        #expect(atom.notifications[0].isRead == false)
        atom.markRead(id: notification.id)
        #expect(atom.notifications[0].isRead == true)
    }

    @Test("markRead(paneId:) marks all notifications for that pane")
    func markReadByPane() {
        let paneA = UUID()
        let paneB = UUID()
        let atom = InboxNotificationAtom()
        atom.append(makeInboxNotification(paneId: paneA))
        atom.append(makeInboxNotification(paneId: paneA))
        atom.append(makeInboxNotification(paneId: paneB))

        atom.markRead(paneId: paneA)

        #expect(atom.notifications[0].isRead == true)
        #expect(atom.notifications[1].isRead == true)
        #expect(atom.notifications[2].isRead == false)
    }

    @Test("markAllRead sets isRead true on every entry")
    func markAllRead() {
        let atom = InboxNotificationAtom()
        for _ in 0..<5 {
            atom.append(makeInboxNotification())
        }
        atom.markAllRead()
        #expect(atom.notifications.allSatisfy { $0.isRead })
    }

    @Test("dismissFromDrawer(id:) sets flag true")
    func dismissFromDrawerById() {
        let atom = InboxNotificationAtom()
        let notification = makeInboxNotification()
        atom.append(notification)
        atom.dismissFromDrawer(id: notification.id)
        #expect(atom.notifications[0].isDismissedFromDrawer == true)
    }

    @Test("dismissFromDrawer(paneId:) sets flag true for every pane entry")
    func dismissFromDrawerByPane() {
        let paneA = UUID()
        let atom = InboxNotificationAtom()
        atom.append(makeInboxNotification(paneId: paneA))
        atom.append(makeInboxNotification(paneId: paneA))
        atom.dismissFromDrawer(paneId: paneA)
        #expect(atom.notifications.allSatisfy { $0.isDismissedFromDrawer })
    }

    @Test("toggleReadState flips the value")
    func toggleReadState() {
        let atom = InboxNotificationAtom()
        let notification = makeInboxNotification()
        atom.append(notification)
        atom.toggleReadState(id: notification.id)
        #expect(atom.notifications[0].isRead == true)
        atom.toggleReadState(id: notification.id)
        #expect(atom.notifications[0].isRead == false)
    }

    @Test("unreadCount(forPaneId:) counts matches")
    func unreadCountForPane() {
        let paneA = UUID()
        let paneB = UUID()
        let atom = InboxNotificationAtom()
        atom.append(makeInboxNotification(paneId: paneA, isRead: false))
        atom.append(makeInboxNotification(paneId: paneA, isRead: true))
        atom.append(makeInboxNotification(paneId: paneB, isRead: false))
        #expect(atom.unreadCount(forPaneId: paneA) == 1)
        #expect(atom.unreadCount(forPaneId: paneB) == 1)
    }

    @Test("unreadCount(forWorktreeId:) counts matches")
    func unreadCountForWorktree() {
        let worktree = UUID()
        let atom = InboxNotificationAtom()
        atom.append(makeInboxNotification(worktreeId: worktree, isRead: false))
        atom.append(makeInboxNotification(worktreeId: worktree, isRead: true))
        atom.append(makeInboxNotification(worktreeId: nil, isRead: false))
        #expect(atom.unreadCount(forWorktreeId: worktree) == 1)
    }

    @Test("unreadCount(forTabId:) counts matches")
    func unreadCountForTab() {
        let tab = UUID()
        let atom = InboxNotificationAtom()
        atom.append(makeInboxNotification(tabId: tab, isRead: false))
        atom.append(makeInboxNotification(tabId: tab, isRead: false))
        #expect(atom.unreadCount(forTabId: tab) == 2)
    }

    @Test("unreadCount(forDrawerPaneIds:) sums across ids")
    func unreadCountForDrawer() {
        let pane1 = UUID()
        let pane2 = UUID()
        let pane3 = UUID()
        let atom = InboxNotificationAtom()
        atom.append(makeInboxNotification(paneId: pane1, isRead: false))
        atom.append(makeInboxNotification(paneId: pane2, isRead: false))
        atom.append(makeInboxNotification(paneId: pane3, isRead: false))
        #expect(atom.unreadCount(forDrawerPaneIds: [pane1, pane2]) == 2)
    }

    @Test("globalUnreadCount counts all unread")
    func globalUnread() {
        let atom = InboxNotificationAtom()
        atom.append(makeInboxNotification(isRead: false))
        atom.append(makeInboxNotification(isRead: true))
        atom.append(makeInboxNotification(isRead: false))
        #expect(atom.globalUnreadCount == 2)
    }

    @Test("retention cap: inserting beyond cap evicts oldest")
    func retentionCap() {
        let atom = InboxNotificationAtom()
        let cap = AppPolicies.InboxNotification.maxRetained
        let base = Date(timeIntervalSince1970: 1_000_000)

        for index in 0..<cap {
            atom.append(
                makeInboxNotification(
                    timestamp: base.addingTimeInterval(TimeInterval(index))
                )
            )
        }

        #expect(atom.notifications.count == cap)
        let oldestId = atom.notifications.first?.id

        atom.append(
            makeInboxNotification(
                timestamp: base.addingTimeInterval(TimeInterval(cap + 1))
            )
        )

        #expect(atom.notifications.count == cap)
        #expect(atom.notifications.contains(where: { $0.id == oldestId }) == false)
    }

    @Test("clearReadHistory removes read entries, keeps unread")
    func clearReadHistory() {
        let atom = InboxNotificationAtom()
        atom.append(makeInboxNotification(isRead: true))
        atom.append(makeInboxNotification(isRead: false))
        atom.append(makeInboxNotification(isRead: true))
        atom.clearReadHistory()
        #expect(atom.notifications.count == 1)
        #expect(atom.notifications[0].isRead == false)
    }

    @Test("clearAll removes everything")
    func clearAll() {
        let atom = InboxNotificationAtom()
        for _ in 0..<3 {
            atom.append(makeInboxNotification())
        }
        atom.clearAll()
        #expect(atom.notifications.isEmpty)
    }
}
