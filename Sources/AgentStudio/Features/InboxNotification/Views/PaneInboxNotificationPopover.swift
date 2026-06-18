import SwiftUI
import os.log

private let paneInboxNotificationPopoverLogger = Logger(
    subsystem: "com.agentstudio",
    category: "PaneInboxNotificationPopover"
)

@MainActor
struct PaneInboxNotificationPopover: View {
    let parentPaneId: UUID
    let workspaceWindowId: UUID?
    let paneIds: [UUID]
    let inboxAtom: InboxNotificationAtom
    let prefsAtom: InboxNotificationPrefsAtom
    let presentationAtom: PaneInboxPresentationAtom
    let onActivate: @MainActor (InboxNotification) -> Void
    let onFocusPane: @MainActor (UUID) -> Void
    let onClear: @MainActor @Sendable () -> Void
    let onClose: @MainActor @Sendable () -> Void
    static let rowChromePolicy = PaneInboxNotificationRow.rowChromePolicy
    static let surfaceBackground = SidebarSurfaceBackground.windowBackgroundColor

    private var transientSurfaceKind: TransientKeyboardSurfaceKind {
        .paneInbox(parentPaneId: parentPaneId)
    }

    @State private var selectedNotificationId: UUID?
    @State private var displayOverride: InboxNotificationDisplayOverride?

    init(
        parentPaneId: UUID,
        workspaceWindowId: UUID?,
        paneIds: [UUID],
        inboxAtom: InboxNotificationAtom,
        prefsAtom: InboxNotificationPrefsAtom,
        presentationAtom: PaneInboxPresentationAtom,
        onActivate: @escaping @MainActor (InboxNotification) -> Void,
        onFocusPane: @escaping @MainActor (UUID) -> Void,
        onClear: @escaping @MainActor @Sendable () -> Void,
        onClose: @escaping @MainActor @Sendable () -> Void
    ) {
        self.parentPaneId = parentPaneId
        self.workspaceWindowId = workspaceWindowId
        self.paneIds = paneIds
        self.inboxAtom = inboxAtom
        self.prefsAtom = prefsAtom
        self.presentationAtom = presentationAtom
        self.onActivate = onActivate
        self.onFocusPane = onFocusPane
        self.onClear = onClear
        self.onClose = onClose
        _displayOverride = State(initialValue: presentationAtom.consumeTemporaryOverride())
    }

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
        .transientKeyboardSurface(
            transientSurfaceKind,
            workspaceWindowId: workspaceWindowId
        )
        .background(Self.surfaceBackground.color)
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
                    return TransientKeyboardSurfaceDismissRouter.shouldDismiss(
                        trigger: trigger,
                        policy: transientSurfaceKind.defaultPolicy
                    )
                }
            )
            .frame(width: 0, height: 0)
        )
        .onAppear(perform: repairSelection)
        .onChange(of: presentationAtom.temporaryOverrideGeneration) { _, _ in
            applyTemporaryOverride()
        }
        .onChange(of: relevantNotificationIds) { _, _ in repairSelection() }
        .onExitCommand(perform: onClose)
    }

    static func relevantNotifications(
        paneIds: [UUID],
        notifications: [InboxNotification],
        filterMode: PaneInboxNotificationFilterMode = .unread,
        contentMode: InboxNotificationContentMode = .rollUpAlerts,
        rowStateFilter: InboxNotificationRowStateFilter? = nil
    ) -> [InboxNotification] {
        let paneIdSet = Set(paneIds)
        let effectiveRowStateFilter =
            rowStateFilter
            ?? {
                switch filterMode {
                case .unread:
                    return .unreadOnly
                case .all:
                    return .all
                }
            }()
        return
            notifications
            .filter { notification in
                guard let paneId = notification.paneId else { return false }
                guard paneIdSet.contains(paneId) else { return false }
                guard !notification.isDismissedFromPaneInbox else { return false }
                guard contentMode.includes(notification) else { return false }
                guard effectiveRowStateFilter.includes(notification) else { return false }
                return true
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
            Button(action: markPaneRead) {
                Image(systemName: "envelope.open")
            }
            .buttonStyle(.borderless)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Mark Pane Read")
            .accessibilityIdentifier("paneInboxMarkReadButton")
            .help("Mark pane notifications read")

            Button(action: clearPaneInbox) {
                clearPaneInboxSpec.icon.swiftUIImage()
            }
            .buttonStyle(.borderless)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(clearPaneInboxSpec.label)
            .accessibilityIdentifier("paneInboxClearButton")
            .accessibilityHidden(true)
            .help(clearPaneInboxSpec.controlToolTip)
            .background(
                AccessibilityPressBridge(
                    identifier: "paneInboxClearButton",
                    label: clearPaneInboxSpec.label,
                    action: clearPaneInbox
                )
            )

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

            Button(action: cycleContentMode) {
                Image(systemName: "dot.circle.viewfinder")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(contentMode == .rollUpAlerts ? Color.accentColor : Color.secondary)
            .help(contentModeHelpText)

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
            filterMode: filterMode,
            contentMode: contentMode,
            rowStateFilter: rowStateFilter
        )
    }

    private var filterMode: PaneInboxNotificationFilterMode {
        switch rowStateFilter {
        case .unreadOnly:
            .unread
        case .all:
            .all
        }
    }

    private var contentMode: InboxNotificationContentMode {
        displayOverride?.contentMode ?? prefsAtom.paneInboxContentMode
    }

    private var rowStateFilter: InboxNotificationRowStateFilter {
        displayOverride?.rowStateFilter ?? prefsAtom.paneInboxRowStateFilter
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
                                now: Date(),
                                parentPaneId: parentPaneId,
                                isSelected: selectedNotificationId == notification.id,
                                onActivate: {
                                    activate(notification)
                                },
                                accessibilityLabel: rowAccessibilityLabel(for: notification)
                            )
                        }
                    }
                }
                .background(Self.surfaceBackground.color)
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
        displayOverride = nil
        prefsAtom.setPaneInboxRowStateFilter(rowStateFilter == .unreadOnly ? .all : .unreadOnly)
        repairSelection()
    }

    private func cycleContentMode() {
        displayOverride = nil
        switch contentMode {
        case .rollUpAlerts:
            prefsAtom.setPaneInboxContentMode(.activity)
        case .activity:
            prefsAtom.setPaneInboxContentMode(.all)
        case .all:
            prefsAtom.setPaneInboxContentMode(.rollUpAlerts)
        }
        repairSelection()
    }

    private func applyTemporaryOverride() {
        guard let override = presentationAtom.consumeTemporaryOverride() else { return }
        displayOverride = override
        repairSelection()
    }

    private var contentModeHelpText: String {
        switch contentMode {
        case .rollUpAlerts:
            "Showing attention notifications"
        case .activity:
            "Showing activity notifications"
        case .all:
            "Showing all notification types"
        }
    }

    private func clearPaneInbox() {
        onClear()
        repairSelection()
    }

    private func markPaneRead() {
        inboxAtom.markRead(scope: .paneIds(paneIds))
        repairSelection()
    }

    private func rowAccessibilityLabel(for notification: InboxNotification) -> String {
        let displayText = InboxNotificationSourceDisplay(
            notification: notification,
            rowContext: .paneInbox(parentPaneId: parentPaneId)
        )
        .primaryText
        return "\(notification.accessibilityStateLabel), \(displayText)"
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
            onFocusPane(paneId)
        }
        onClose()
    }
}

extension InboxNotification {
    fileprivate var accessibilityStateLabel: String {
        if isRead {
            return "Read \(displayLane.accessibilityLabel)"
        }
        return "Unread \(displayLane.accessibilityLabel)"
    }
}

extension InboxNotificationClaimLane {
    fileprivate var accessibilityLabel: String {
        switch self {
        case .actionNeeded:
            "action needed"
        case .safety:
            "safety"
        case .settledAgent:
            "agent settled"
        case .activity:
            "activity"
        }
    }
}

private struct PaneInboxNotificationRow: View {
    let notification: InboxNotification
    let now: Date
    let parentPaneId: UUID
    let isSelected: Bool
    let onActivate: @MainActor () -> Void
    let accessibilityLabel: String
    static let rowChromePolicy = SidebarRowShell<InboxRow>.chromePolicy

    @State private var isHovering = false

    var body: some View {
        SidebarRowShell(
            isSelected: isSelected,
            isHovering: isHovering
        ) {
            InboxRow(
                notification: notification,
                now: now,
                rowContext: .paneInbox(parentPaneId: parentPaneId)
            )
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            onActivate()
        }
        .background(
            AccessibilityPressBridge(
                identifier: "paneInboxNotificationRow.\(notification.id.uuidString)",
                label: accessibilityLabel,
                action: onActivate
            )
        )
    }
}
