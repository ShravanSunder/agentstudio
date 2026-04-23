import SwiftUI

@MainActor
struct InboxNotificationDrawerPopover: View {
    let drawerPaneIds: [UUID]
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
        drawerPaneIds: [UUID],
        notifications: [InboxNotification]
    ) -> [InboxNotification] {
        let paneIdSet = Set(drawerPaneIds)
        return
            notifications
            .filter { notification in
                guard let paneId = notification.paneId else { return false }
                return paneIdSet.contains(paneId) && !notification.isDismissedFromDrawer
            }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private var header: some View {
        HStack {
            Text("Drawer inbox")
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
            drawerPaneIds: drawerPaneIds,
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
        inboxAtom.dismissFromDrawer(id: notification.id)
        if let paneId = notification.paneId {
            dispatcher.dispatch(.focusPane, target: paneId, targetType: .pane)
        }
        onClose()
    }
}
