import SwiftUI

@MainActor
struct PaneInboxNotificationPopover: View {
    let paneIds: [UUID]
    let inboxAtom: InboxNotificationAtom
    let dispatcher: CommandDispatcher
    let onClose: @MainActor @Sendable () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
        }
        .frame(width: 320, height: 400)
    }

    static func relevantNotifications(
        paneIds: [UUID],
        notifications: [InboxNotification]
    ) -> [InboxNotification] {
        let paneIdSet = Set(paneIds)
        return
            notifications
            .filter { notification in
                guard let paneId = notification.paneId else { return false }
                return paneIdSet.contains(paneId) && !notification.isDismissedFromPaneInbox
            }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private var header: some View {
        HStack {
            Text("Pane inbox")
                .font(.headline)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
    }

    private var relevantNotifications: [InboxNotification] {
        Self.relevantNotifications(
            paneIds: paneIds,
            notifications: inboxAtom.notifications
        )
    }

    private var list: some View {
        Group {
            if relevantNotifications.isEmpty {
                InboxNotificationEmptyState()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(relevantNotifications) { notification in
                            InboxRow(notification: notification, now: Date())
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    activate(notification)
                                }
                        }
                    }
                }
            }
        }
    }

    private func activate(_ notification: InboxNotification) {
        inboxAtom.markRead(id: notification.id)
        inboxAtom.dismissFromPaneInbox(id: notification.id)
        if let paneId = notification.paneId {
            dispatcher.dispatch(.focusPane, target: paneId, targetType: .pane)
        }
        onClose()
    }
}
