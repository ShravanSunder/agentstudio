import SwiftUI

struct InboxSidebarActions {
    let onEscape: @MainActor @Sendable () -> Void
    let onToggleSort: () -> Void
    let onToggleRowStateFilter: () -> Void
    let onCycleContentMode: () -> Void
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
    let uiState: WorkspaceSidebarState
    @Binding var searchText: String
    let activeFilter: InboxFilter?
    let activeFilterLabel: String?
    let contentMode: InboxNotificationContentMode
    let rowStateFilter: InboxNotificationRowStateFilter
    let sort: InboxNotificationSort
    @Binding var groupingMenuOpen: Bool
    let grouping: InboxNotificationGrouping
    let focusedField: FocusState<InboxFocus?>.Binding
    let sections: [InboxNotificationListSection]
    let flashingRowIds: Set<UUID>
    let actions: InboxSidebarActions
    static let surfaceBackground = SidebarSurfaceBackground.shellChrome

    var body: some View {
        baseChrome
            .onChange(of: focusedField.wrappedValue) { _, newValue in
                InboxSidebarFocusPublisher.publish(focusedField: newValue, into: uiState)
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
                contentMode: contentMode,
                rowStateFilter: rowStateFilter,
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

enum InboxSidebarToolbarTooltipTarget: Hashable, CaseIterable {
    case delete
    case sort
    case rowState
    case contentMode
    case grouping
}

struct InboxSidebarHeader: View {
    @Binding var searchText: String
    let activeFilter: InboxFilter?
    let activeFilterLabel: String?
    let contentMode: InboxNotificationContentMode
    let rowStateFilter: InboxNotificationRowStateFilter
    let sort: InboxNotificationSort
    @Binding var groupingMenuOpen: Bool
    let grouping: InboxNotificationGrouping
    let focusedField: FocusState<InboxFocus?>.Binding
    let actions: InboxSidebarActions
    static let groupIconName = "square.stack.3d.up"
    static let rowStateIconName = "envelope.badge"
    static let contentModeIconName = "dot.circle.viewfinder"
    static let filterIconName = "line.3.horizontal.decrease.circle"
    static let tooltipCoordinateSpaceName = "inboxSidebarHeaderTooltips"
    static let headerLayoutPolicy = SidebarHeaderLayout<EmptyView, EmptyView, EmptyView, EmptyView>.policy
    @State private var hoveredTooltipTarget: InboxSidebarToolbarTooltipTarget?
    @State private var tooltipFrames: [InboxSidebarToolbarTooltipTarget: CGRect] = [:]
    @State private var suppressDeleteTooltipUntilHoverExit = false
    private let toggleSortSpec = AppCommand.toggleInboxNotificationSort.definition
    private var isAttentionOnly: Bool { contentMode == .rollUpAlerts }
    private var isUnreadOnly: Bool { rowStateFilter == .unreadOnly }
    private var rowStateAction: ActionSpec {
        LocalActionSpec.toggleInboxRowStateFilter(showingUnreadOnly: isUnreadOnly).actionSpec
    }
    private var contentModeAction: ActionSpec {
        LocalActionSpec.toggleInboxAttentionFilter(isAttentionOnly: isAttentionOnly).actionSpec
    }
    private var groupingAction: ActionSpec {
        LocalActionSpec.groupInboxNotifications.actionSpec
    }
    private var deleteInboxAction: ActionSpec {
        LocalActionSpec.deleteInboxNotifications.actionSpec
    }

    var body: some View {
        headerContent
            .coordinateSpace(name: Self.tooltipCoordinateSpaceName)
            .onPreferenceChange(HoverTooltipAnchorPreferenceKey<InboxSidebarToolbarTooltipTarget>.self) {
                tooltipFrames = $0
            }
            .overlay(alignment: .topLeading) {
                GeometryReader { geometryProxy in
                    FloatingHoverTooltipPresenter(
                        activeTarget: activeTooltipTarget,
                        anchorFrames: tooltipFrames,
                        availableWidth: geometryProxy.size.width,
                        verticalAnchor: .aboveAnchor,
                        verticalOffset: HoverTooltipPlacement.aboveAnchorVerticalOffset,
                        tooltipValue: tooltipValue(for:)
                    )
                    .allowsHitTesting(false)
                }
            }
    }

    private var headerContent: some View {
        SidebarHeaderLayout {
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
            .controlHelp(Self.searchTooltipValue)
        } primaryAction: {
            Menu {
                Button("Delete Read", action: actions.onClearReadHistory)
                Divider()
                Button("Delete All", role: .destructive, action: actions.onClearAllHistory)
            } label: {
                SidebarToolbarIcon(icon: deleteInboxAction.icon)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(deleteInboxAction.label)
            .accessibilityIdentifier("inboxSidebarDeleteMenu")
            .controlHelp(
                Self.toolbarTooltipValue(
                    for: .delete,
                    rowStateFilter: rowStateFilter,
                    contentMode: contentMode
                )
            )
            .simultaneousGesture(
                TapGesture().onEnded {
                    suppressDeleteTooltipUntilHoverExit = true
                    hoveredTooltipTarget = nil
                }
            )
            .onHover { updateDeleteTooltipTarget(isHovered: $0) }
            .hoverTooltipAnchor(InboxSidebarToolbarTooltipTarget.delete, in: Self.tooltipCoordinateSpaceName)
            .fixedSize()
            .background(
                AccessibilityLabelBridge(
                    identifier: "inboxSidebarDeleteMenu",
                    label: deleteInboxAction.label
                )
            )
        } toolbarRow: {
            HStack(spacing: AppStyles.General.Spacing.standard) {
                Spacer(minLength: 0)

                SidebarToolbarSortButton(
                    sortValue: sort,
                    isReversed: sort == .oldestFirst,
                    label: toggleSortSpec.label,
                    accessibilityIdentifier: "inboxSidebarSortButton",
                    tooltipValue: Self.toolbarTooltipValue(
                        for: .sort,
                        rowStateFilter: rowStateFilter,
                        contentMode: contentMode
                    ),
                    icon: toggleSortSpec.icon,
                    tooltipTarget: InboxSidebarToolbarTooltipTarget.sort,
                    tooltipCoordinateSpaceName: Self.tooltipCoordinateSpaceName,
                    frameAccessibilityIdentifier: "inboxSidebarSortButtonFrame",
                    onHover: { updateTooltipTarget(.sort, isHovered: $0) },
                    onToggle: actions.onToggleSort
                )

                SidebarToolbarActionButton(
                    label: rowStateAction.label,
                    accessibilityIdentifier: "inboxSidebarRowStateFilterButton",
                    tooltipValue: Self.toolbarTooltipValue(
                        for: .rowState,
                        rowStateFilter: rowStateFilter,
                        contentMode: contentMode
                    ),
                    icon: rowStateAction.icon,
                    isActive: isUnreadOnly,
                    tooltipTarget: InboxSidebarToolbarTooltipTarget.rowState,
                    tooltipCoordinateSpaceName: Self.tooltipCoordinateSpaceName,
                    onHover: { updateTooltipTarget(.rowState, isHovered: $0) },
                    action: actions.onToggleRowStateFilter
                )

                SidebarToolbarActionButton(
                    label: contentModeAction.label,
                    accessibilityIdentifier: "inboxSidebarContentModeButton",
                    tooltipValue: Self.toolbarTooltipValue(
                        for: .contentMode,
                        rowStateFilter: rowStateFilter,
                        contentMode: contentMode
                    ),
                    icon: contentModeAction.icon,
                    isActive: isAttentionOnly,
                    tooltipTarget: InboxSidebarToolbarTooltipTarget.contentMode,
                    tooltipCoordinateSpaceName: Self.tooltipCoordinateSpaceName,
                    onHover: { updateTooltipTarget(.contentMode, isHovered: $0) },
                    action: actions.onCycleContentMode
                )

                SidebarToolbarActionButton(
                    label: groupingAction.label,
                    accessibilityIdentifier: "inboxSidebarGroupingButton",
                    tooltipValue: Self.toolbarTooltipValue(
                        for: .grouping,
                        rowStateFilter: rowStateFilter,
                        contentMode: contentMode
                    ),
                    icon: grouping.icon,
                    tooltipTarget: InboxSidebarToolbarTooltipTarget.grouping,
                    tooltipCoordinateSpaceName: Self.tooltipCoordinateSpaceName,
                    onHover: { updateTooltipTarget(.grouping, isHovered: $0) },
                    action: {
                        groupingMenuOpen.toggle()
                    }
                )
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
                                    candidate.icon.swiftUIImage(size: AppStyles.General.Icon.compact)
                                        .frame(width: AppStyles.General.Icon.compact)
                                    Text(groupingLabel(candidate))
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(8)
                }
            }
            .background(
                AccessibilityLabelBridge(
                    identifier: "inboxSidebarToolbarRow",
                    label: "Inbox toolbar row"
                )
            )
        } statusRow: {
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
        .background(
            AccessibilityLabelBridge(
                identifier: "inboxSidebarSearchRow",
                label: "Inbox search row"
            )
        )
    }

    private var activeTooltipTarget: InboxSidebarToolbarTooltipTarget? {
        groupingMenuOpen ? nil : hoveredTooltipTarget
    }

    private func updateTooltipTarget(_ target: InboxSidebarToolbarTooltipTarget, isHovered: Bool) {
        withAnimation(.easeInOut(duration: AppStyles.General.Animation.fast)) {
            hoveredTooltipTarget = isHovered ? target : nil
        }
    }

    private func updateDeleteTooltipTarget(isHovered: Bool) {
        if !isHovered {
            suppressDeleteTooltipUntilHoverExit = false
            updateTooltipTarget(.delete, isHovered: false)
            return
        }

        if !suppressDeleteTooltipUntilHoverExit {
            updateTooltipTarget(.delete, isHovered: true)
        }
    }

    private func tooltipValue(for target: InboxSidebarToolbarTooltipTarget) -> ControlTooltipRenderValue? {
        Self.toolbarTooltipValue(for: target, rowStateFilter: rowStateFilter, contentMode: contentMode)
    }

    static func toolbarTooltipText(
        for target: InboxSidebarToolbarTooltipTarget,
        rowStateFilter: InboxNotificationRowStateFilter,
        contentMode: InboxNotificationContentMode
    ) -> String {
        toolbarTooltipValue(for: target, rowStateFilter: rowStateFilter, contentMode: contentMode).text
    }

    static var searchTooltipValue: ControlTooltipRenderValue {
        let shortcutDisplayText = InboxSidebarShortcutCatalog.focusSearch.displayText
        return ControlTooltipRenderValue(
            text: "Search inbox notifications (\(shortcutDisplayText.value))",
            shortcutDisplayText: shortcutDisplayText
        )
    }

    static func toolbarTooltipValue(
        for target: InboxSidebarToolbarTooltipTarget,
        rowStateFilter: InboxNotificationRowStateFilter,
        contentMode: InboxNotificationContentMode
    ) -> ControlTooltipRenderValue {
        switch target {
        case .delete:
            return LocalActionSpec.deleteInboxNotifications.actionSpec.controlTooltipRenderValue(
                provenance: .localAction(rawValue: "deleteInboxNotifications"),
                textOverride: "Clear notifications"
            )
        case .sort:
            let sortSpec = AppCommand.toggleInboxNotificationSort.definition
            return sortSpec.controlTooltipRenderValue(
                textOverride: "Sort inbox",
                shortcutTextOverride: InboxSidebarShortcutCatalog.toggleSort.displayText
            )
        case .rowState:
            let rowStateAction = LocalActionSpec.toggleInboxRowStateFilter(
                showingUnreadOnly: rowStateFilter == .unreadOnly
            )
            .actionSpec
            return rowStateAction.controlTooltipRenderValue(
                provenance: .localAction(rawValue: "toggleInboxRowStateFilter"),
                textOverride: rowStateFilter == .unreadOnly ? "Show all" : "Unread only"
            )
        case .contentMode:
            let contentModeAction = LocalActionSpec.toggleInboxAttentionFilter(
                isAttentionOnly: contentMode == .rollUpAlerts
            )
            .actionSpec
            return contentModeAction.controlTooltipRenderValue(
                provenance: .localAction(rawValue: "toggleInboxAttentionFilter"),
                textOverride: contentMode == .rollUpAlerts ? "Show all notifications" : "Attention only"
            )
        case .grouping:
            let groupingAction = LocalActionSpec.groupInboxNotifications.actionSpec
            return groupingAction.controlTooltipRenderValue(
                provenance: .localAction(rawValue: "groupInboxNotifications"),
                textOverride: "Group",
                shortcutText: InboxSidebarShortcutCatalog.toggleGroupingMenu.displayText
            )
        }
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
    static let surfaceBackground = SidebarSurfaceBackground.shellChrome

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
