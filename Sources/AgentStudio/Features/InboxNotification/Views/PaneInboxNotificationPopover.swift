import SwiftUI
import os.log

private let paneInboxNotificationPopoverLogger = Logger(
    subsystem: "com.agentstudio",
    category: "PaneInboxNotificationPopover"
)

@MainActor
struct PaneInboxNotificationPopover: View {
    let parentPaneId: UUID
    let paneIds: [UUID]
    let inboxAtom: InboxNotificationAtom
    let dispatcher: CommandDispatcher
    let onActivate: @MainActor (InboxNotification) -> Void
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
                guard paneIdSet.contains(paneId) else { return false }
                return !notification.isRead && !notification.isDismissedFromPaneInbox
            }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(AppPolicies.PaneInbox.maxVisibleNotifications)
            .map { $0 }
    }

    static func keyboardItems(
        for notifications: [InboxNotification]
    ) -> [SelectablePopoverKeyboardItem<UUID>] {
        notifications.enumerated().map { index, notification in
            SelectablePopoverKeyboardItem(
                id: notification.id,
                shortcutNumber: index < AppPolicies.SelectablePopover.maxNumberedShortcuts ? index + 1 : nil,
                supportsAuxiliaryAction: false
            )
        }
    }

    private var header: some View {
        HStack(spacing: AppStyles.Components.PaneInbox.headerControlSpacing) {
            Text("Pane inbox")
                .font(.headline)
            Spacer()
            Button(action: clearNotifications) {
                AppCommand.clearPaneInboxNotifications.definition.icon.swiftUIImage(
                    size: AppStyles.Components.PaneInbox.filterButtonFontSize
                )
                .frame(
                    width: AppStyles.General.Button.compact,
                    height: AppStyles.General.Button.compact
                )
            }
            .buttonStyle(.borderless)
            .help(AppCommand.clearPaneInboxNotifications.definition.controlToolTip)

            Divider()
                .frame(height: AppStyles.Components.PaneInbox.headerSeparatorHeight)

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
                            PaneInboxNotificationRow(
                                notification: notification,
                                parentPaneId: parentPaneId,
                                isSelected: selectedNotificationId == notification.id
                            ) {
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

    func clearNotifications() {
        dispatcher.dispatch(.clearPaneInboxNotifications, target: parentPaneId, targetType: .pane)
        repairSelection()
    }

    private func activate(notificationId: UUID) {
        guard let notification = relevantNotifications.first(where: { $0.id == notificationId }) else {
            paneInboxNotificationPopoverLogger.warning(
                "Pane inbox activation dropped unknown notification id \(notificationId.uuidString, privacy: .public)"
            )
            return
        }

        activate(notification)
    }

    private func activate(_ notification: InboxNotification) {
        onActivate(notification)
        inboxAtom.markRead(id: notification.id)
        inboxAtom.dismissFromPaneInbox(id: notification.id)
        if let paneId = notification.paneId {
            dispatcher.dispatch(.focusPane, target: paneId, targetType: .pane)
        }
        onClose()
    }
}

private struct PaneInboxNotificationRow: View {
    let notification: InboxNotification
    let parentPaneId: UUID
    let isSelected: Bool
    let onActivate: () -> Void

    @State private var isHovered = false

    var body: some View {
        SidebarRowShell(
            isSelected: isSelected,
            isFlashing: false,
            isHovered: isHovered
        ) {
            InboxRow(
                notification: notification,
                now: Date(),
                rowContext: .paneInbox(parentPaneId: parentPaneId)
            )
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture(perform: onActivate)
    }
}
