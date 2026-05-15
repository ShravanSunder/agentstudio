import SwiftUI

struct InboxSidebarActions {
    let onEscape: @MainActor @Sendable () -> Void
    let onToggleSort: () -> Void
    let onToggleUnreadOnly: () -> Void
    let onClearFilter: @MainActor @Sendable () -> Void
    let onClearReadHistory: @MainActor @Sendable () -> Void
    let onClearAllHistory: @MainActor @Sendable () -> Void
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
    let activeFilter: InboxFilter?
    let activeFilterLabel: String?
    let unreadOnly: Bool
    let sort: InboxNotificationSort
    @Binding var groupingMenuOpen: Bool
    let grouping: InboxNotificationGrouping
    let focusedField: FocusState<InboxFocus?>.Binding
    let sections: [InboxNotificationListSection]
    let flashingRowIds: Set<UUID>
    let actions: InboxSidebarActions
    static let surfaceBackground = SidebarSurfaceBackground.windowBackgroundColor

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
                activeFilter: activeFilter,
                activeFilterLabel: activeFilterLabel,
                unreadOnly: unreadOnly,
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
                grouping: grouping,
                actions: actions
            )
        }
        .background(Self.surfaceBackground.color)
    }
}

struct InboxSidebarHeader: View {
    @Binding var searchText: String
    let activeFilter: InboxFilter?
    let activeFilterLabel: String?
    let unreadOnly: Bool
    let sort: InboxNotificationSort
    @Binding var groupingMenuOpen: Bool
    let grouping: InboxNotificationGrouping
    let focusedField: FocusState<InboxFocus?>.Binding
    let actions: InboxSidebarActions
    static let groupIconName = "square.stack.3d.up"
    static let unreadOnlyIconName = "envelope.badge"
    static let filterIconName = "line.3.horizontal.decrease.circle"
    private let toggleSortSpec = AppCommand.toggleInboxNotificationSort.definition
    private let clearReadInboxSpec = AppCommand.clearReadInboxNotifications.definition
    private let clearAllInboxSpec = AppCommand.clearAllInboxNotifications.definition

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
                    toggleSortSpec.icon.swiftUIImage()
                }
                .buttonStyle(.borderless)
                .help(toggleSortSpec.controlToolTip)

                Button(action: actions.onToggleUnreadOnly) {
                    Image(systemName: Self.unreadOnlyIconName)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(unreadOnly ? Color.accentColor : Color.secondary)
                .help(unreadOnly ? "Show all inbox notifications" : "Show unread only")

                Button {
                    groupingMenuOpen.toggle()
                } label: {
                    Image(systemName: Self.groupIconName)
                }
                .buttonStyle(.borderless)
                .help("Group inbox notifications")
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

                Menu {
                    Button("Delete Read", action: actions.onClearReadHistory)
                    Divider()
                    Button("Delete All", role: .destructive, action: actions.onClearAllHistory)
                } label: {
                    clearReadInboxSpec.icon.swiftUIImage()
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Delete inbox notifications")
                .accessibilityIdentifier("inboxSidebarDeleteMenu")
                .help("\(clearReadInboxSpec.helpText). \(clearAllInboxSpec.helpText).")
            }

            if let activeFilter {
                let filterLabel = activeFilterLabel ?? fallbackFilterLabel(activeFilter)
                HStack(spacing: 6) {
                    Image(systemName: Self.filterIconName)
                    Text(filterLabel)
                        .lineLimit(1)
                    Button(action: actions.onClearFilter) {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Clear inbox filter")
                    .accessibilityIdentifier("inboxSidebarClearFilterButton")
                    .accessibilityHidden(true)
                    .background(
                        AccessibilityPressBridge(
                            identifier: "inboxSidebarClearFilterButton",
                            label: "Clear inbox filter",
                            action: actions.onClearFilter
                        )
                    )
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .background(
                    AccessibilityLabelBridge(
                        identifier: "inboxSidebarActiveFilterChip",
                        label: filterLabel
                    )
                )
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

    private func fallbackFilterLabel(_ filter: InboxFilter) -> String {
        switch filter {
        case .worktree:
            return "Filtered worktree"
        case .repo:
            return "Filtered repo"
        }
    }
}

struct InboxSidebarContent: View {
    let sections: [InboxNotificationListSection]
    let focusedField: FocusState<InboxFocus?>.Binding
    let flashingRowIds: Set<UUID>
    let grouping: InboxNotificationGrouping
    let actions: InboxSidebarActions
    static let surfaceListPolicy = SidebarSurfaceListPolicy.nativeSidebarList
    static let surfaceBackground = SidebarSurfaceBackground.windowBackgroundColor

    var body: some View {
        if sections.allSatisfy(\.notifications.isEmpty) {
            InboxNotificationEmptyState()
        } else {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                List {
                    ForEach(sections) { section in
                        if let header = section.header {
                            InboxNotificationGroupHeader(
                                header: header,
                                unreadCount: section.unreadCount,
                                isCollapsed: section.isCollapsed,
                                showsUnreadCount: Self.showsUnreadCount(for: grouping),
                                onToggle: { actions.onToggleGroupCollapse(section.id) }
                            )
                            .listRowInsets(
                                EdgeInsets(
                                    top: 0,
                                    leading: 0,
                                    bottom: 0,
                                    trailing: 0
                                )
                            )
                        }
                        ForEach(section.visibleNotifications) { notification in
                            InboxSidebarNotificationRow(
                                notification: notification,
                                now: context.date,
                                focusedField: focusedField,
                                isFlashing: flashingRowIds.contains(notification.id),
                                grouping: grouping,
                                actions: actions
                            )
                            .listRowInsets(
                                EdgeInsets(
                                    top: 0,
                                    leading: Self.rowLeadingInset(isGrouped: section.label != nil),
                                    bottom: 0,
                                    trailing: 0
                                )
                            )
                        }
                    }
                }
                .sidebarSurfaceListStyle(Self.surfaceListPolicy)
                .scrollContentBackground(.hidden)
                .background(Self.surfaceBackground.color)
                .focused(focusedField, equals: .list)
            }
        }
    }

    static func rowLeadingInset(isGrouped: Bool) -> CGFloat {
        isGrouped ? AppStyles.Shell.Sidebar.groupChildRowLeadingInset : 0
    }

    static func showsUnreadCount(for grouping: InboxNotificationGrouping) -> Bool {
        grouping != .byPane
    }
}

struct InboxSidebarNotificationRow: View {
    let notification: InboxNotification
    let now: Date
    let focusedField: FocusState<InboxFocus?>.Binding
    let isFlashing: Bool
    let grouping: InboxNotificationGrouping
    let actions: InboxSidebarActions
    static let rowChromePolicy = SidebarRowShell<InboxRow>.chromePolicy
    @State private var isHovering = false

    var body: some View {
        SidebarRowShell(
            isFlashing: isFlashing,
            isHovering: isHovering
        ) {
            InboxRow(
                notification: notification,
                now: now,
                rowContext: .globalInbox,
                grouping: grouping
            )
        }
        .focused(focusedField, equals: .row(notification.id))
        .animation(.easeOut(duration: 0.25), value: isFlashing)
        .onHover { isHovering = $0 }
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
