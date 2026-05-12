import SwiftUI

struct InboxSidebarActions {
    let onEscape: @MainActor @Sendable () -> Void
    let onToggleSort: () -> Void
    let onClearAll: @MainActor @Sendable () -> Void
    let onClearFilter: () -> Void
    let onSelectGrouping: (InboxNotificationGrouping) -> Void
    let onToggleGroupCollapse: (String) -> Void
    let onMoveGroupBoundary: (InboxNotificationListNavigationDirection) -> Bool
    let onMoveEnd: (InboxNotificationListEndpoint) -> Bool
    let onActivate: (InboxNotification) -> Void
    let onToggleRead: (UUID) -> Void
}

struct InboxSidebarRootContainer: View {
    let uiState: UIStateAtom
    @Binding var searchText: String
    let activeFilterLabel: String?
    let sort: InboxNotificationSort
    @Binding var groupingMenuOpen: Bool
    let grouping: InboxNotificationGrouping
    let focusedField: FocusState<InboxFocus?>.Binding
    let sections: [InboxNotificationListSection]
    let flashingRowIds: Set<UUID>
    let actions: InboxSidebarActions

    var body: some View {
        baseChrome
            .onChange(of: focusedField.wrappedValue) { _, newValue in
                if newValue == nil {
                    uiState.setSidebarHasFocus(false)
                }
            }
            .onKeyPress(phases: [.down]) { event in
                handleKeyPress(event)
            }
    }

    private func handleKeyPress(_ event: KeyPress) -> KeyPress.Result {
        switch InboxSidebarKeyboardRouter.rootAction(
            characters: event.characters,
            key: event.key,
            modifiers: event.modifiers
        ) {
        case .focusSearch:
            focusedField.wrappedValue = .search
            return .handled
        case .toggleGroupingMenu:
            groupingMenuOpen.toggle()
            return .handled
        case .toggleSort:
            actions.onToggleSort()
            return .handled
        case .moveGroupBoundary(let direction):
            return actions.onMoveGroupBoundary(direction) ? .handled : .ignored
        case .moveEnd(let endpoint):
            return actions.onMoveEnd(endpoint) ? .handled : .ignored
        case .ignored:
            return .ignored
        }
    }

    private var baseChrome: some View {
        VStack(spacing: 0) {
            InboxNotificationSidebarFocusBridge(
                uiState: uiState,
                onEscape: actions.onEscape
            )
            .frame(width: 1, height: 1)
            .opacity(0.001)

            InboxSidebarHeader(
                searchText: $searchText,
                activeFilterLabel: activeFilterLabel,
                sort: sort,
                groupingMenuOpen: $groupingMenuOpen,
                grouping: grouping,
                focusedField: focusedField,
                actions: actions
            )

            Divider()

            InboxSidebarContent(
                sections: sections,
                focusedField: focusedField,
                flashingRowIds: flashingRowIds,
                actions: actions
            )
        }
        .frame(minWidth: 200)
        .background(Color(nsColor: .windowBackgroundColor))
        .shadow(color: .black.opacity(0.2), radius: 4, x: 2, y: 0)
    }
}

struct InboxSidebarHeader: View {
    private let sortIconName = "arrow.up.arrow.down.circle"
    private let groupIconName = "square.stack.3d.up"
    private let filterIconName = "line.3.horizontal.decrease.circle"

    @Binding var searchText: String
    let activeFilterLabel: String?
    let sort: InboxNotificationSort
    @Binding var groupingMenuOpen: Bool
    let grouping: InboxNotificationGrouping
    let focusedField: FocusState<InboxFocus?>.Binding
    let actions: InboxSidebarActions

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                SidebarSearchField(
                    placeholder: "Search inbox...",
                    text: $searchText,
                    focusedField: focusedField,
                    focusValue: .search,
                    clearHelp: "Clear inbox search",
                    onSubmit: {
                        focusedField.wrappedValue = .list
                    },
                    onExit: actions.onEscape,
                    onDownArrow: {
                        focusedField.wrappedValue = .list
                        return .handled
                    }
                )

                Button(action: actions.onToggleSort) {
                    Image(systemName: sortIconName)
                }
                .buttonStyle(.borderless)
                .help("Sort notifications")

                Button(action: actions.onClearAll) {
                    AppCommand.clearInboxNotifications.definition.icon.swiftUIImage(
                        size: AppStyles.General.Icon.compact
                    )
                    .frame(
                        width: AppStyles.General.Button.compact,
                        height: AppStyles.General.Button.compact
                    )
                }
                .buttonStyle(.borderless)
                .help(AppCommand.clearInboxNotifications.definition.controlToolTip)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(AppCommand.clearInboxNotifications.definition.label)
                .accessibilityIdentifier("inboxSidebarClearButton")
                .accessibilityHidden(true)
                .background(
                    AccessibilityPressBridge(
                        identifier: "inboxSidebarClearButton",
                        label: AppCommand.clearInboxNotifications.definition.label,
                        action: actions.onClearAll
                    )
                )

                Button {
                    groupingMenuOpen.toggle()
                } label: {
                    Image(systemName: groupIconName)
                }
                .buttonStyle(.borderless)
                .help("Group notifications")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Group notifications")
                .popover(isPresented: $groupingMenuOpen) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(InboxNotificationGrouping.allCases, id: \.self) { candidate in
                            Button {
                                actions.onSelectGrouping(candidate)
                                groupingMenuOpen = false
                            } label: {
                                HStack {
                                    Image(systemName: grouping == candidate ? "checkmark" : "")
                                        .frame(width: 12)
                                    Text(groupingLabel(candidate))
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(8)
                }
            }

            if let activeFilterLabel {
                HStack(spacing: 6) {
                    Image(systemName: filterIconName)
                    Text(activeFilterLabel)
                        .lineLimit(1)
                    Button(action: actions.onClearFilter) {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            }
        }
        .padding(8)
    }

    private func groupingLabel(_ grouping: InboxNotificationGrouping) -> String {
        switch grouping {
        case .none:
            return "None"
        case .byRepo:
            return "By Repo"
        case .byPane:
            return "By Pane"
        case .byTab:
            return "By Tab"
        }
    }

}

struct InboxSidebarContent: View {
    let sections: [InboxNotificationListSection]
    let focusedField: FocusState<InboxFocus?>.Binding
    let flashingRowIds: Set<UUID>
    let actions: InboxSidebarActions

    var body: some View {
        if sections.allSatisfy(\.notifications.isEmpty) {
            InboxNotificationEmptyState()
        } else {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(sections) { section in
                            if let header = section.header {
                                InboxNotificationGroupHeader(
                                    header: header,
                                    unreadCount: section.unreadCount,
                                    isCollapsed: section.isCollapsed,
                                    onToggle: { actions.onToggleGroupCollapse(section.id) }
                                )
                            }
                            ForEach(section.visibleNotifications) { notification in
                                if section.label == nil {
                                    InboxSidebarNotificationRow(
                                        notification: notification,
                                        now: context.date,
                                        focusedField: focusedField,
                                        isFlashing: flashingRowIds.contains(notification.id),
                                        actions: actions
                                    )
                                } else {
                                    InboxSidebarNotificationRow(
                                        notification: notification,
                                        now: context.date,
                                        focusedField: focusedField,
                                        isFlashing: flashingRowIds.contains(notification.id),
                                        actions: actions
                                    )
                                    .padding(.leading, AppStyles.Shell.Sidebar.groupChildRowLeadingInset)
                                }
                            }
                        }
                    }
                }
                .focused(focusedField, equals: .list)
            }
        }
    }
}

struct InboxSidebarNotificationRow: View {
    let notification: InboxNotification
    let now: Date
    let focusedField: FocusState<InboxFocus?>.Binding
    let isFlashing: Bool
    let actions: InboxSidebarActions

    @State private var isHovered = false

    var body: some View {
        SidebarRowShell(
            isSelected: focusedField.wrappedValue == .row(notification.id),
            isFlashing: isFlashing,
            isHovered: isHovered
        ) {
            InboxRow(notification: notification, now: now)
        }
        .focused(focusedField, equals: .row(notification.id))
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            actions.onActivate(notification)
        }
        .onKeyPress(.return) {
            guard focusedField.wrappedValue == .row(notification.id) else { return .ignored }
            return handleRowKey(.return)
        }
        .onKeyPress(.space) {
            guard focusedField.wrappedValue == .row(notification.id) else { return .ignored }
            return handleRowKey(.space)
        }
    }

    private func handleRowKey(_ key: KeyEquivalent) -> KeyPress.Result {
        switch InboxSidebarKeyboardRouter.rowAction(key: key) {
        case .activate:
            actions.onActivate(notification)
            return .handled
        case .toggleRead:
            actions.onToggleRead(notification.id)
            return .handled
        case .ignored:
            return .ignored
        }
    }
}
