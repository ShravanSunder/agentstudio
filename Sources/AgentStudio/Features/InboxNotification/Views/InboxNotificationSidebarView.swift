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

@MainActor
struct InboxNotificationSidebarView: View {
    struct Group: Identifiable, Equatable {
        let key: String
        let label: String
        let notifications: [InboxNotification]

        var id: String { key }

        var unreadCount: Int {
            notifications.reduce(0) { count, notification in
                notification.isRead ? count : count + 1
            }
        }
    }

    enum RenderedEntry: Identifiable, Equatable {
        case groupHeader(key: String, label: String, unreadCount: Int)
        case notification(InboxNotification)

        var id: String {
            switch self {
            case .groupHeader(let key, _, _):
                return "header:\(key)"
            case .notification(let notification):
                return "notification:\(notification.id.uuidString)"
            }
        }
    }

    enum Direction {
        case next
        case previous
    }

    enum Endpoint {
        case first
        case last
    }

    static let focusTargetIdentifier = NSUserInterfaceItemIdentifier(
        "InboxNotificationSidebarView.focusTarget"
    )

    let inboxAtom: InboxNotificationAtom
    let prefsAtom: InboxNotificationPrefsAtom
    let uiState: UIStateAtom
    let workspacePaneAtom: WorkspacePaneAtom
    let dispatcher: CommandDispatcher
    let onRefocusActivePane: @MainActor @Sendable () -> Void

    @State private var searchText = ""
    @State private var groupingMenuOpen = false
    @State private var flashingRowIds: Set<UUID> = []
    @FocusState private var focusedField: InboxFocus?

    private let flashClock = ContinuousClock()

    var body: some View {
        InboxSidebarRootContainer(
            uiState: uiState,
            searchText: $searchText,
            sort: prefsAtom.sort,
            groupingMenuOpen: $groupingMenuOpen,
            grouping: prefsAtom.grouping,
            focusedField: $focusedField,
            entries: renderedEntries,
            flashingRowIds: flashingRowIds,
            onEscape: handleEscape,
            onToggleSort: toggleSort,
            onSelectGrouping: { prefsAtom.setGrouping($0) },
            onMoveGroupBoundary: moveFocusToGroupBoundary,
            onMoveEnd: moveFocusToEnd,
            onActivate: activate,
            onToggleRead: { inboxAtom.toggleReadState(id: $0) }
        )
    }

    private var sortedNotifications: [InboxNotification] {
        switch prefsAtom.sort {
        case .newestFirst:
            return inboxAtom.notifications.sorted { $0.timestamp > $1.timestamp }
        case .oldestFirst:
            return inboxAtom.notifications.sorted { $0.timestamp < $1.timestamp }
        }
    }

    private var filteredNotifications: [InboxNotification] {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedQuery.isEmpty else { return sortedNotifications }

        return sortedNotifications.filter { notification in
            notification.title.lowercased().contains(trimmedQuery)
                || (notification.body ?? "").lowercased().contains(trimmedQuery)
                || (notification.repoName ?? "").lowercased().contains(trimmedQuery)
                || (notification.worktreeName ?? "").lowercased().contains(trimmedQuery)
                || (notification.branchName ?? "").lowercased().contains(trimmedQuery)
        }
    }

    private var groupedRows: [Group] {
        let notifications = filteredNotifications
        switch prefsAtom.grouping {
        case .none:
            return [Group(key: "all", label: "", notifications: notifications)]
        case .byRepo:
            return buildGroups(
                notifications: notifications,
                key: { $0.repoName ?? "(no repo)" },
                label: { $0.repoName ?? "Unknown Repo" }
            )
        case .byPane:
            return buildGroups(
                notifications: notifications,
                key: { $0.paneId?.uuidString ?? "(no pane)" },
                label: { $0.worktreeName ?? $0.branchName ?? "Unknown Pane" }
            )
        case .byTab:
            return buildGroups(
                notifications: notifications,
                key: { $0.tabId?.uuidString ?? "(no tab)" },
                label: { notification in
                    guard let tabId = notification.tabId else { return "Unknown Tab" }
                    return "Tab \(tabId.uuidString.prefix(8))"
                }
            )
        }
    }

    private var renderedEntries: [RenderedEntry] {
        if filteredNotifications.isEmpty {
            return []
        }

        return groupedRows.flatMap { group in
            var entries: [RenderedEntry] = []
            if !group.label.isEmpty {
                entries.append(
                    .groupHeader(
                        key: group.key,
                        label: group.label,
                        unreadCount: group.unreadCount
                    )
                )
            }
            entries.append(contentsOf: group.notifications.map(RenderedEntry.notification))
            return entries
        }
    }

    private func buildGroups(
        notifications: [InboxNotification],
        key: (InboxNotification) -> String,
        label: (InboxNotification) -> String
    ) -> [Group] {
        let buckets = Dictionary(grouping: notifications, by: key)
        return buckets.keys.sorted().compactMap { groupKey in
            guard let notifications = buckets[groupKey], let first = notifications.first else { return nil }
            return Group(key: groupKey, label: label(first), notifications: notifications)
        }
    }

    @discardableResult
    private func moveFocusToGroupBoundary(_ direction: Direction) -> Bool {
        let groups = groupedRows
        guard !groups.isEmpty else { return false }

        let currentGroupIndex = groups.firstIndex { group in
            guard case .row(let rowId) = focusedField else { return false }
            return group.notifications.contains { $0.id == rowId }
        }

        let targetIndex: Int
        switch direction {
        case .next:
            guard let currentGroupIndex, currentGroupIndex + 1 < groups.count else { return false }
            targetIndex = currentGroupIndex + 1
        case .previous:
            guard let currentGroupIndex, currentGroupIndex - 1 >= 0 else { return false }
            targetIndex = currentGroupIndex - 1
        }

        guard let firstNotification = groups[targetIndex].notifications.first else { return false }
        focusedField = .row(firstNotification.id)
        return true
    }

    @discardableResult
    private func moveFocusToEnd(_ endpoint: Endpoint) -> Bool {
        let rows = groupedRows.flatMap(\.notifications)
        guard !rows.isEmpty else { return false }
        switch endpoint {
        case .first:
            focusedField = .row(rows.first!.id)
        case .last:
            focusedField = .row(rows.last!.id)
        }
        return true
    }

    private func toggleSort() {
        let nextSort: InboxNotificationSort =
            prefsAtom.sort == .newestFirst ? .oldestFirst : .newestFirst
        prefsAtom.setSort(nextSort)
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

        guard
            let paneId = notification.paneId,
            workspacePaneAtom.pane(paneId) != nil
        else {
            flashingRowIds.insert(notification.id)
            Task { @MainActor [flashClock] in
                try? await flashClock.sleep(for: .milliseconds(600))
                flashingRowIds.remove(notification.id)
            }
            return
        }

        dispatcher.dispatch(.focusPane, target: paneId, targetType: .pane)
    }
}

private struct InboxSidebarRootContainer: View {
    let uiState: UIStateAtom
    @Binding var searchText: String
    let sort: InboxNotificationSort
    @Binding var groupingMenuOpen: Bool
    let grouping: InboxNotificationGrouping
    let focusedField: FocusState<InboxFocus?>.Binding
    let entries: [InboxNotificationSidebarView.RenderedEntry]
    let flashingRowIds: Set<UUID>
    let onEscape: @MainActor @Sendable () -> Void
    let onToggleSort: () -> Void
    let onSelectGrouping: (InboxNotificationGrouping) -> Void
    let onMoveGroupBoundary: (InboxNotificationSidebarView.Direction) -> Bool
    let onMoveEnd: (InboxNotificationSidebarView.Endpoint) -> Bool
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
        if event.modifiers == .option {
            if event.characters == "f" {
                focusedField.wrappedValue = .search
                return .handled
            }
            if event.characters == "g" {
                groupingMenuOpen.toggle()
                return .handled
            }
            if event.characters == "s" {
                onToggleSort()
                return .handled
            }
            if event.key == .downArrow {
                return onMoveGroupBoundary(.next) ? .handled : .ignored
            }
            if event.key == .upArrow {
                return onMoveGroupBoundary(.previous) ? .handled : .ignored
            }
        }

        if event.modifiers == .command {
            if event.key == .downArrow {
                return onMoveEnd(.last) ? .handled : .ignored
            }
            if event.key == .upArrow {
                return onMoveEnd(.first) ? .handled : .ignored
            }
        }

        return .ignored
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
                sort: sort,
                groupingMenuOpen: $groupingMenuOpen,
                grouping: grouping,
                focusedField: focusedField,
                onEscape: onEscape,
                onToggleSort: onToggleSort,
                onSelectGrouping: onSelectGrouping
            )

            Divider()

            InboxSidebarContent(
                entries: entries,
                focusedField: focusedField,
                flashingRowIds: flashingRowIds,
                onActivate: onActivate,
                onToggleRead: onToggleRead
            )
        }
    }
}

private struct InboxSidebarHeader: View {
    @Binding var searchText: String
    let sort: InboxNotificationSort
    @Binding var groupingMenuOpen: Bool
    let grouping: InboxNotificationGrouping
    let focusedField: FocusState<InboxFocus?>.Binding
    let onEscape: () -> Void
    let onToggleSort: () -> Void
    let onSelectGrouping: (InboxNotificationGrouping) -> Void

    var body: some View {
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

private struct InboxSidebarContent: View {
    let entries: [InboxNotificationSidebarView.RenderedEntry]
    let focusedField: FocusState<InboxFocus?>.Binding
    let flashingRowIds: Set<UUID>
    let onActivate: (InboxNotification) -> Void
    let onToggleRead: (UUID) -> Void

    var body: some View {
        if entries.isEmpty {
            InboxNotificationEmptyState()
        } else {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(entries) { entry in
                            InboxSidebarEntryView(
                                entry: entry,
                                now: context.date,
                                focusedField: focusedField,
                                isFlashing: entry.notificationId.map { flashingRowIds.contains($0) } ?? false,
                                onActivate: onActivate,
                                onToggleRead: onToggleRead
                            )
                        }
                    }
                }
                .focused(focusedField, equals: .list)
            }
        }
    }
}

private struct InboxSidebarEntryView: View {
    let entry: InboxNotificationSidebarView.RenderedEntry
    let now: Date
    let focusedField: FocusState<InboxFocus?>.Binding
    let isFlashing: Bool
    let onActivate: (InboxNotification) -> Void
    let onToggleRead: (UUID) -> Void

    var body: some View {
        switch entry {
        case .groupHeader(_, let label, let unreadCount):
            InboxNotificationGroupHeader(label: label, unreadCount: unreadCount)
        case .notification(let notification):
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
                    onActivate(notification)
                    return .handled
                }
                .onKeyPress(.space) {
                    guard focusedField.wrappedValue == .row(notification.id) else { return .ignored }
                    onToggleRead(notification.id)
                    return .handled
                }
        }
    }
}

extension InboxNotificationSidebarView.RenderedEntry {
    fileprivate var notificationId: UUID? {
        switch self {
        case .groupHeader:
            return nil
        case .notification(let notification):
            return notification.id
        }
    }
}
