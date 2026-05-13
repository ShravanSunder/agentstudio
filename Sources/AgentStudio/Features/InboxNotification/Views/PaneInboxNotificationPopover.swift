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
    let presentationAtom: PaneInboxPresentationAtom
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
        notifications: [InboxNotification],
        filterMode: PaneInboxNotificationFilterMode = .unread
    ) -> [InboxNotification] {
        let paneIdSet = Set(paneIds)
        return
            notifications
            .filter { notification in
                guard let paneId = notification.paneId else { return false }
                guard paneIdSet.contains(paneId) else { return false }
                switch filterMode {
                case .unread:
                    return !notification.isRead && !notification.isDismissedFromPaneInbox
                case .all:
                    return true
                }
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
        let clearPaneInboxSpec = AppCommand.clearPaneInboxNotifications.definition
        return HStack(spacing: AppStyles.Components.PaneInbox.headerControlSpacing) {
            Text("Pane inbox")
                .font(.headline)
            Spacer()
            Button(action: clearPaneInbox) {
                clearPaneInboxSpec.icon.swiftUIImage()
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(clearPaneInboxSpec.label)
            .help(clearPaneInboxSpec.controlToolTip)

            Button(action: toggleFilterMode) {
                HStack(spacing: AppStyles.General.Spacing.tight) {
                    Image(systemName: filterMode.systemImageName)
                    Text(filterMode.label)
                }
                .font(
                    .system(
                        size: AppStyles.Components.PaneInbox.filterButtonFontSize,
                        weight: .medium
                    )
                )
                .padding(.horizontal, AppStyles.Components.PaneInbox.filterButtonHorizontalPadding)
                .padding(.vertical, AppStyles.Components.PaneInbox.filterButtonVerticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: AppStyles.Components.PaneInbox.filterButtonCornerRadius)
                        .fill(Color.white.opacity(AppStyles.General.Fill.hover))
                )
            }
            .buttonStyle(.borderless)
            .help(filterMode.helpText)

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
            notifications: inboxAtom.notifications,
            filterMode: filterMode
        )
    }

    private var filterMode: PaneInboxNotificationFilterMode {
        presentationAtom.filterMode(for: parentPaneId)
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
                            SidebarRowShell(
                                isSelected: selectedNotificationId == notification.id
                            ) {
                                InboxRow(
                                    notification: notification,
                                    now: Date(),
                                    rowContext: .paneInbox(parentPaneId: parentPaneId)
                                )
                            }
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

    private func repairSelection() {
        if let selectedNotificationId, relevantNotificationIds.contains(selectedNotificationId) {
            return
        }

        selectedNotificationId = SelectablePopoverKeyboardRouter.defaultSelection(
            items: Self.keyboardItems(for: relevantNotifications),
            preferredItemId: nil
        )
    }

    private func toggleFilterMode() {
        presentationAtom.toggleFilterMode(for: parentPaneId)
        repairSelection()
    }

    private func clearPaneInbox() {
        inboxAtom.clearPaneInbox(paneIds: paneIds)
        repairSelection()
    }

    private func activate(notificationId: UUID) {
        guard let notification = relevantNotifications.first(where: { $0.id == notificationId }) else {
            paneInboxNotificationPopoverLogger.warning(
                "Pane inbox activation dropped unknown notification id \(notificationId.uuidString, privacy: .public)"
            )
            repairSelection()
            return
        }

        activate(notification)
    }

    private func activate(_ notification: InboxNotification) {
        onActivate(notification)
        let didMarkRead = inboxAtom.markRead(id: notification.id)
        let didDismiss = inboxAtom.dismissFromPaneInbox(id: notification.id)
        if !didMarkRead || !didDismiss {
            paneInboxNotificationPopoverLogger.warning(
                "Pane inbox activation used stale notification id \(notification.id.uuidString, privacy: .public)"
            )
        }
        if let paneId = notification.paneId {
            dispatcher.dispatch(.focusPane, target: paneId, targetType: .pane)
        }
        onClose()
    }
}
