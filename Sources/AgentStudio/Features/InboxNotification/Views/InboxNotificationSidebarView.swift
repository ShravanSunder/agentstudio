import AppKit
import SwiftUI

private final class InboxNotificationSidebarFocusableView: NSView {
    var onFocusChange: @MainActor (Bool) -> Void = { _ in }
    var onEscape: @MainActor @Sendable () -> Void = {}

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            onFocusChange(true)
        }
        return didBecomeFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let didResignFirstResponder = super.resignFirstResponder()
        if didResignFirstResponder {
            onFocusChange(false)
        }
        return didResignFirstResponder
    }

    override func cancelOperation(_ sender: Any?) {
        _ = sender
        onEscape()
    }
}

private struct InboxNotificationSidebarFocusBridge: NSViewRepresentable {
    let uiState: UIStateAtom
    let onEscape: @MainActor @Sendable () -> Void

    func makeNSView(context: Context) -> InboxNotificationSidebarFocusableView {
        let view = InboxNotificationSidebarFocusableView()
        view.identifier = InboxNotificationSidebarView.focusTargetIdentifier
        view.onFocusChange = { hasFocus in
            uiState.setSidebarHasFocus(hasFocus)
        }
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: InboxNotificationSidebarFocusableView, context: Context) {
        nsView.onFocusChange = { hasFocus in
            uiState.setSidebarHasFocus(hasFocus)
        }
        nsView.onEscape = onEscape
    }

    static func dismantleNSView(_ nsView: InboxNotificationSidebarFocusableView, coordinator: ()) {
        MainActor.assumeIsolated {
            nsView.onFocusChange(false)
        }
    }
}

enum InboxFocus: Hashable {
    case search
    case list
    case row(UUID)
    case groupingMenu
}

private struct InboxNotificationListModelKey: Equatable {
    let notifications: [InboxNotification]
    let grouping: InboxNotificationGrouping
    let sort: InboxNotificationSort
    let searchText: String
    let filter: InboxFilter?
    let collapsedGroups: Set<InboxNotificationGroupKey>
}

enum InboxSidebarRootKeyAction: Equatable {
    case focusSearch
    case toggleGroupingMenu
    case toggleSort
    case moveGroupBoundary(InboxNotificationListNavigationDirection)
    case moveEnd(InboxNotificationListEndpoint)
    case ignored
}

enum InboxSidebarRowKeyAction: Equatable {
    case activate
    case toggleRead
    case ignored
}

enum InboxSidebarActivationOutcome: Equatable {
    case focusPane(UUID)
    case flashRow(UUID)
}

enum InboxSidebarKeyboardRouter {
    static func rootAction(
        characters: String,
        key: KeyEquivalent,
        modifiers: EventModifiers
    ) -> InboxSidebarRootKeyAction {
        if modifiers == .option {
            if characters == "f" { return .focusSearch }
            if characters == "g" { return .toggleGroupingMenu }
            if characters == "s" { return .toggleSort }
            if key == .downArrow { return .moveGroupBoundary(.next) }
            if key == .upArrow { return .moveGroupBoundary(.previous) }
        }

        if modifiers == .command {
            if key == .downArrow { return .moveEnd(.last) }
            if key == .upArrow { return .moveEnd(.first) }
        }

        return .ignored
    }

    static func rowAction(key: KeyEquivalent) -> InboxSidebarRowKeyAction {
        if key == .return { return .activate }
        if key == .space { return .toggleRead }
        return .ignored
    }
}

enum InboxSidebarActivationResolver {
    @MainActor
    static func resolve(
        notification: InboxNotification,
        workspacePaneAtom: WorkspacePaneAtom
    ) -> InboxSidebarActivationOutcome {
        guard
            let paneId = notification.paneId,
            workspacePaneAtom.pane(paneId) != nil
        else {
            return .flashRow(notification.id)
        }

        return .focusPane(paneId)
    }
}

@MainActor
struct InboxNotificationSidebarView: View {
    static let focusTargetIdentifier = NSUserInterfaceItemIdentifier(
        "InboxNotificationSidebarView.focusTarget"
    )

    let inboxAtom: InboxNotificationAtom
    let prefsAtom: InboxNotificationPrefsAtom
    let uiState: UIStateAtom
    let sidebarCache: SidebarCacheAtom
    let inboxFilterDraft: InboxFilterDraftAtom
    let workspacePaneAtom: WorkspacePaneAtom
    let dispatcher: CommandDispatcher
    let onRefocusActivePane: @MainActor @Sendable () -> Void

    @State private var searchText = ""
    @State private var cachedListModel: InboxNotificationListModel
    @State private var cachedListModelKey: InboxNotificationListModelKey
    @State private var groupingMenuOpen = false
    @State private var flashingRowIds: Set<UUID> = []
    @State private var activeFilter: InboxFilter?
    @FocusState private var focusedField: InboxFocus?

    private let flashClock = ContinuousClock()

    init(
        inboxAtom: InboxNotificationAtom,
        prefsAtom: InboxNotificationPrefsAtom,
        uiState: UIStateAtom,
        sidebarCache: SidebarCacheAtom,
        inboxFilterDraft: InboxFilterDraftAtom,
        workspacePaneAtom: WorkspacePaneAtom,
        dispatcher: CommandDispatcher,
        onRefocusActivePane: @escaping @MainActor @Sendable () -> Void
    ) {
        self.inboxAtom = inboxAtom
        self.prefsAtom = prefsAtom
        self.uiState = uiState
        self.sidebarCache = sidebarCache
        self.inboxFilterDraft = inboxFilterDraft
        self.workspacePaneAtom = workspacePaneAtom
        self.dispatcher = dispatcher
        self.onRefocusActivePane = onRefocusActivePane
        let initialKey = InboxNotificationListModelKey(
            notifications: inboxAtom.notifications,
            grouping: prefsAtom.grouping,
            sort: prefsAtom.sort,
            searchText: "",
            filter: nil,
            collapsedGroups: sidebarCache.collapsedInboxGroups
        )
        self._cachedListModelKey = State(initialValue: initialKey)
        self._cachedListModel = State(
            initialValue: InboxNotificationListModel(
                notifications: inboxAtom.notifications,
                grouping: prefsAtom.grouping,
                sort: prefsAtom.sort,
                searchText: "",
                filter: nil,
                collapsedGroups: sidebarCache.collapsedInboxGroups
            )
        )
    }

    var body: some View {
        InboxSidebarRootContainer(
            uiState: uiState,
            searchText: $searchText,
            activeFilter: activeFilter,
            sort: prefsAtom.sort,
            groupingMenuOpen: $groupingMenuOpen,
            grouping: prefsAtom.grouping,
            focusedField: $focusedField,
            sections: listModel.sections,
            flashingRowIds: flashingRowIds,
            onEscape: handleEscape,
            onToggleSort: toggleSort,
            onClearFilter: clearFilter,
            onSelectGrouping: { prefsAtom.setGrouping($0) },
            onToggleGroupCollapse: toggleGroupCollapse,
            onMoveGroupBoundary: moveFocusToGroupBoundary,
            onMoveEnd: moveFocusToEnd,
            onActivate: activate,
            onToggleRead: { inboxAtom.toggleReadState(id: $0) }
        )
        .onChange(of: inboxAtom.notifications) { _, _ in refreshListModel() }
        .onChange(of: prefsAtom.grouping) { _, _ in refreshListModel() }
        .onChange(of: prefsAtom.sort) { _, _ in refreshListModel() }
        .onChange(of: searchText) { _, _ in refreshListModel() }
        .onChange(of: activeFilter) { _, _ in refreshListModel() }
        .onChange(of: sidebarCache.collapsedInboxGroups) { _, _ in refreshListModel() }
        .task {
            guard let filter = inboxFilterDraft.consume() else { return }
            activeFilter = filter
        }
    }

    private var listModel: InboxNotificationListModel {
        cachedListModel
    }

    private func refreshListModel() {
        let key = InboxNotificationListModelKey(
            notifications: inboxAtom.notifications,
            grouping: prefsAtom.grouping,
            sort: prefsAtom.sort,
            searchText: searchText,
            filter: activeFilter,
            collapsedGroups: sidebarCache.collapsedInboxGroups
        )
        guard key != cachedListModelKey else { return }
        cachedListModelKey = key
        cachedListModel = InboxNotificationListModel(
            notifications: key.notifications,
            grouping: key.grouping,
            sort: key.sort,
            searchText: key.searchText,
            filter: key.filter,
            collapsedGroups: key.collapsedGroups
        )
    }

    @discardableResult
    private func moveFocusToGroupBoundary(_ direction: InboxNotificationListNavigationDirection) -> Bool {
        guard
            let rowId = listModel.groupBoundaryTarget(
                from: focusedNotificationId,
                direction: direction
            )
        else {
            return false
        }
        focusedField = .row(rowId)
        return true
    }

    @discardableResult
    private func moveFocusToEnd(_ endpoint: InboxNotificationListEndpoint) -> Bool {
        guard let rowId = listModel.endpointTarget(endpoint) else {
            return false
        }
        focusedField = .row(rowId)
        return true
    }

    private var focusedNotificationId: UUID? {
        guard case .row(let rowId) = focusedField else { return nil }
        return rowId
    }

    private func toggleSort() {
        let nextSort: InboxNotificationSort =
            prefsAtom.sort == .newestFirst ? .oldestFirst : .newestFirst
        prefsAtom.setSort(nextSort)
    }

    private func clearFilter() {
        activeFilter = nil
    }

    private func toggleGroupCollapse(_ sectionId: String) {
        sidebarCache.toggleInboxGroupCollapse(InboxNotificationGroupKey(sectionId))
    }

    private func handleEscape() {
        if focusedField == .search {
            if searchText.isEmpty {
                focusedField = .list
            } else {
                searchText = ""
                focusedField = .list
            }
            return
        }

        focusedField = nil
        onRefocusActivePane()
    }

    private func activate(_ notification: InboxNotification) {
        inboxAtom.markRead(id: notification.id)
        inboxAtom.dismissFromDrawer(id: notification.id)

        switch InboxSidebarActivationResolver.resolve(
            notification: notification,
            workspacePaneAtom: workspacePaneAtom
        ) {
        case .flashRow(let rowId):
            // History is denormalized, so stale rows can outlive their pane; flash instead of dispatching a dead target.
            flashingRowIds.insert(rowId)
            Task { @MainActor [flashClock] in
                try? await flashClock.sleep(for: .milliseconds(600))
                flashingRowIds.remove(rowId)
            }
        case .focusPane(let paneId):
            dispatcher.dispatch(.focusPane, target: paneId, targetType: .pane)
        }
    }
}

private struct InboxSidebarRootContainer: View {
    let uiState: UIStateAtom
    @Binding var searchText: String
    let activeFilter: InboxFilter?
    let sort: InboxNotificationSort
    @Binding var groupingMenuOpen: Bool
    let grouping: InboxNotificationGrouping
    let focusedField: FocusState<InboxFocus?>.Binding
    let sections: [InboxNotificationListSection]
    let flashingRowIds: Set<UUID>
    let onEscape: @MainActor @Sendable () -> Void
    let onToggleSort: () -> Void
    let onClearFilter: () -> Void
    let onSelectGrouping: (InboxNotificationGrouping) -> Void
    let onToggleGroupCollapse: (String) -> Void
    let onMoveGroupBoundary: (InboxNotificationListNavigationDirection) -> Bool
    let onMoveEnd: (InboxNotificationListEndpoint) -> Bool
    let onActivate: (InboxNotification) -> Void
    let onToggleRead: (UUID) -> Void

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
            onToggleSort()
            return .handled
        case .moveGroupBoundary(let direction):
            return onMoveGroupBoundary(direction) ? .handled : .ignored
        case .moveEnd(let endpoint):
            return onMoveEnd(endpoint) ? .handled : .ignored
        case .ignored:
            return .ignored
        }
    }

    private var baseChrome: some View {
        VStack(spacing: 0) {
            InboxNotificationSidebarFocusBridge(
                uiState: uiState,
                onEscape: onEscape
            )
            .frame(width: 1, height: 1)
            .opacity(0.001)

            InboxSidebarHeader(
                searchText: $searchText,
                activeFilter: activeFilter,
                sort: sort,
                groupingMenuOpen: $groupingMenuOpen,
                grouping: grouping,
                focusedField: focusedField,
                onEscape: onEscape,
                onToggleSort: onToggleSort,
                onClearFilter: onClearFilter,
                onSelectGrouping: onSelectGrouping
            )

            Divider()

            InboxSidebarContent(
                sections: sections,
                focusedField: focusedField,
                flashingRowIds: flashingRowIds,
                onToggleGroupCollapse: onToggleGroupCollapse,
                onActivate: onActivate,
                onToggleRead: onToggleRead
            )
        }
    }
}

private struct InboxSidebarHeader: View {
    @Binding var searchText: String
    let activeFilter: InboxFilter?
    let sort: InboxNotificationSort
    @Binding var groupingMenuOpen: Bool
    let grouping: InboxNotificationGrouping
    let focusedField: FocusState<InboxFocus?>.Binding
    let onEscape: () -> Void
    let onToggleSort: () -> Void
    let onClearFilter: () -> Void
    let onSelectGrouping: (InboxNotificationGrouping) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Search inbox...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .focused(focusedField, equals: .search)
                    .onSubmit {
                        focusedField.wrappedValue = .list
                    }
                    .onExitCommand {
                        onEscape()
                    }

                Button(action: onToggleSort) {
                    Image(systemName: sort == .newestFirst ? "arrow.down.to.line" : "arrow.up.to.line")
                }
                .buttonStyle(.borderless)

                Button {
                    groupingMenuOpen.toggle()
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(.borderless)
                .popover(isPresented: $groupingMenuOpen) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(InboxNotificationGrouping.allCases, id: \.self) { candidate in
                            Button {
                                onSelectGrouping(candidate)
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

            if let activeFilter {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text(filterLabel(activeFilter))
                        .lineLimit(1)
                    Button(action: onClearFilter) {
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

    private func filterLabel(_ filter: InboxFilter) -> String {
        switch filter {
        case .worktree(let id):
            return "Worktree \(id.uuidString.prefix(8))"
        case .repo(let id):
            return "Repo \(id.uuidString.prefix(8))"
        }
    }
}

private struct InboxSidebarContent: View {
    let sections: [InboxNotificationListSection]
    let focusedField: FocusState<InboxFocus?>.Binding
    let flashingRowIds: Set<UUID>
    let onToggleGroupCollapse: (String) -> Void
    let onActivate: (InboxNotification) -> Void
    let onToggleRead: (UUID) -> Void

    var body: some View {
        if sections.allSatisfy(\.notifications.isEmpty) {
            InboxNotificationEmptyState()
        } else {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(sections) { section in
                            if let label = section.label {
                                InboxNotificationGroupHeader(
                                    label: label,
                                    unreadCount: section.unreadCount,
                                    isCollapsed: section.isCollapsed,
                                    onToggle: { onToggleGroupCollapse(section.id) }
                                )
                            }
                            ForEach(section.visibleNotifications) { notification in
                                InboxSidebarNotificationRow(
                                    notification: notification,
                                    now: context.date,
                                    focusedField: focusedField,
                                    isFlashing: flashingRowIds.contains(notification.id),
                                    onActivate: onActivate,
                                    onToggleRead: onToggleRead
                                )
                            }
                        }
                    }
                }
                .focused(focusedField, equals: .list)
            }
        }
    }
}

private struct InboxSidebarNotificationRow: View {
    let notification: InboxNotification
    let now: Date
    let focusedField: FocusState<InboxFocus?>.Binding
    let isFlashing: Bool
    let onActivate: (InboxNotification) -> Void
    let onToggleRead: (UUID) -> Void

    var body: some View {
        InboxRow(notification: notification, now: now)
            .focused(focusedField, equals: .row(notification.id))
            .contentShape(Rectangle())
            .background(isFlashing ? Color.accentColor.opacity(0.18) : Color.clear)
            .animation(.easeOut(duration: 0.25), value: isFlashing)
            .onTapGesture {
                onActivate(notification)
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
            onActivate(notification)
            return .handled
        case .toggleRead:
            onToggleRead(notification.id)
            return .handled
        case .ignored:
            return .ignored
        }
    }
}
