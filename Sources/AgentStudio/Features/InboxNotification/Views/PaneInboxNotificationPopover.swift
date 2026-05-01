import SwiftUI

@MainActor
struct PaneInboxNotificationPopover: View {
    let paneIds: [UUID]
    let inboxAtom: InboxNotificationAtom
    let dispatcher: CommandDispatcher
    let onClose: @MainActor @Sendable () -> Void

    @State private var selectedNotificationId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
        }
        .frame(
            width: AppStyles.Components.PaneInbox.popoverWidth,
            height: AppStyles.Components.PaneInbox.popoverHeight
        )
        .background(
            SelectablePopoverKeyboardBridge(
                items: Self.keyboardItems(for: relevantNotifications),
                selectedItemId: selectedNotificationId,
                auxiliaryAction: nil,
                onSelect: { notificationId in
                    selectedNotificationId = notificationId
                    activate(notificationId: notificationId)
                },
                onHighlight: { notificationId in
                    selectedNotificationId = notificationId
                },
                onDismiss: onClose,
                matchesAdditionalDismissShortcut: { event in
                    guard let trigger = ShortcutDecoder.decode(event: event) else { return false }
                    return trigger == AppShortcut.showPaneInboxNotifications.trigger
                }
            )
            .frame(width: 0, height: 0)
        )
        .onAppear(perform: repairSelection)
        .onChange(of: relevantNotificationIds) { _, _ in repairSelection() }
        .onExitCommand(perform: onClose)
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

    static func keyboardItems(
        for notifications: [InboxNotification]
    ) -> [SelectablePopoverKeyboardItem<UUID>] {
        let keyboardNotifications = notifications.prefix(AppPolicies.SelectablePopover.maxNumberedShortcuts)
        return keyboardNotifications.enumerated().map { index, notification in
            SelectablePopoverKeyboardItem(
                id: notification.id,
                shortcutNumber: index + 1,
                supportsAuxiliaryAction: false
            )
        }
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
        .padding(AppStyles.Components.PaneInbox.headerPadding)
    }

    private var relevantNotifications: [InboxNotification] {
        Self.relevantNotifications(
            paneIds: paneIds,
            notifications: inboxAtom.notifications
        )
    }

    private var relevantNotificationIds: [UUID] {
        relevantNotifications.map(\.id)
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
                                .background(
                                    RoundedRectangle(cornerRadius: AppStyles.Components.PaneInbox.rowCornerRadius)
                                        .fill(
                                            selectedNotificationId == notification.id
                                                ? Color.accentColor.opacity(AppStyles.General.Fill.selected)
                                                : Color.clear
                                        )
                                )
                                .onTapGesture {
                                    activate(notification)
                                }
                        }
                    }
                }
            }
        }
    }

    private func repairSelection() {
        if let selectedNotificationId, relevantNotificationIds.contains(selectedNotificationId) {
            return
        }

        selectedNotificationId = SelectablePopoverKeyboardRouter.defaultSelection(
            items: Self.keyboardItems(for: relevantNotifications),
            preferredItemId: nil
        )
    }

    private func activate(notificationId: UUID) {
        guard let notification = relevantNotifications.first(where: { $0.id == notificationId }) else {
            return
        }

        activate(notification)
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
