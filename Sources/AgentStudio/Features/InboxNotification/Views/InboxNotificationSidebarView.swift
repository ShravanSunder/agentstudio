import Foundation
import SwiftUI
import os.log

private let inboxNotificationSidebarLogger = Logger(
    subsystem: "com.agentstudio",
    category: "InboxNotificationSidebarView"
)

private struct InboxNotificationListModelKey: Equatable {
    let notifications: [InboxNotification]
    let grouping: InboxNotificationGrouping
    let sort: InboxNotificationSort
    let searchText: String
    let filter: InboxFilter?
    let collapsedGroups: Set<InboxNotificationGroupKey>
    let repoPresentationFingerprint: String
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
    let workspaceRepositoryTopologyAtom: WorkspaceRepositoryTopologyAtom
    let repoCache: RepoCacheAtom
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
        workspaceRepositoryTopologyAtom: WorkspaceRepositoryTopologyAtom,
        repoCache: RepoCacheAtom,
        dispatcher: CommandDispatcher,
        onRefocusActivePane: @escaping @MainActor @Sendable () -> Void
    ) {
        self.inboxAtom = inboxAtom
        self.prefsAtom = prefsAtom
        self.uiState = uiState
        self.sidebarCache = sidebarCache
        self.inboxFilterDraft = inboxFilterDraft
        self.workspacePaneAtom = workspacePaneAtom
        self.workspaceRepositoryTopologyAtom = workspaceRepositoryTopologyAtom
        self.repoCache = repoCache
        self.dispatcher = dispatcher
        self.onRefocusActivePane = onRefocusActivePane
        let initialRepoPresentationByRepoId = Self.repoPresentationByRepoId(
            repos: workspaceRepositoryTopologyAtom.repos,
            repoEnrichmentByRepoId: repoCache.repoEnrichmentByRepoId,
            checkoutColors: sidebarCache.checkoutColors
        )
        let initialKey = InboxNotificationListModelKey(
            notifications: inboxAtom.notifications,
            grouping: prefsAtom.grouping,
            sort: prefsAtom.sort,
            searchText: "",
            filter: nil,
            collapsedGroups: sidebarCache.collapsedInboxGroups,
            repoPresentationFingerprint: Self.repoPresentationFingerprint(
                initialRepoPresentationByRepoId
            )
        )
        self._cachedListModelKey = State(initialValue: initialKey)
        self._cachedListModel = State(
            initialValue: InboxNotificationListModel(
                notifications: inboxAtom.notifications,
                grouping: prefsAtom.grouping,
                sort: prefsAtom.sort,
                searchText: "",
                filter: nil,
                collapsedGroups: sidebarCache.collapsedInboxGroups,
                repoPresentation: { repoId in
                    guard let repoId else { return nil }
                    return initialRepoPresentationByRepoId[repoId]
                }
            )
        )
    }

    var body: some View {
        InboxSidebarRootContainer(
            uiState: uiState,
            searchText: $searchText,
            activeFilter: activeFilter,
            activeFilterLabel: activeFilterLabel,
            sort: prefsAtom.sort,
            groupingMenuOpen: $groupingMenuOpen,
            grouping: prefsAtom.grouping,
            focusedField: $focusedField,
            sections: listModel.sections,
            flashingRowIds: flashingRowIds,
            actions: .init(
                onEscape: handleEscape,
                onToggleSort: toggleSort,
                onClearFilter: clearFilter,
                onClearReadHistory: clearReadInboxNotifications,
                onSelectGrouping: { prefsAtom.setGrouping($0) },
                onToggleGroupCollapse: toggleGroupCollapse,
                onMoveGroupBoundary: moveFocusToGroupBoundary,
                onMoveEnd: moveFocusToEnd,
                onActivate: activate,
                onToggleRead: { inboxAtom.toggleReadState(id: $0) }
            )
        )
        .onChange(of: inboxAtom.notifications) { _, _ in refreshListModel() }
        .onChange(of: prefsAtom.grouping) { _, _ in refreshListModel() }
        .onChange(of: prefsAtom.sort) { _, _ in refreshListModel() }
        .onChange(of: searchText) { _, _ in refreshListModel() }
        .onChange(of: activeFilter) { _, _ in refreshListModel() }
        .onChange(of: sidebarCache.collapsedInboxGroups) { _, _ in refreshListModel() }
        .onChange(of: repoPresentationFingerprint) { _, _ in refreshListModel() }
        .onChange(of: inboxFilterDraft.pendingFilter) { _, _ in
            applyPendingFilterDraft()
        }
        .task {
            applyPendingFilterDraft()
        }
    }

    private var listModel: InboxNotificationListModel {
        cachedListModel
    }

    private var activeFilterLabel: String? {
        Self.activeFilterLabel(activeFilter: activeFilter, notifications: inboxAtom.notifications)
    }

    private var repoPresentationByRepoId: [UUID: InboxNotificationRepoGroupPresentation] {
        Self.repoPresentationByRepoId(
            repos: workspaceRepositoryTopologyAtom.repos,
            repoEnrichmentByRepoId: repoCache.repoEnrichmentByRepoId,
            checkoutColors: sidebarCache.checkoutColors
        )
    }

    private var repoPresentationFingerprint: String {
        Self.repoPresentationFingerprint(repoPresentationByRepoId)
    }

    static func activeFilterLabel(
        activeFilter: InboxFilter?,
        notifications: [InboxNotification]
    ) -> String? {
        guard let activeFilter else { return nil }
        return notifications
            .lazy
            .compactMap { notification in
                InboxNotificationSourceDisplay(notification: notification).filterLabel(for: activeFilter)
            }
            .first ?? fallbackFilterLabel(for: activeFilter)
    }

    private static func fallbackFilterLabel(for filter: InboxFilter) -> String {
        switch filter {
        case .worktree:
            return "Filtered worktree"
        case .repo:
            return "Filtered repo"
        }
    }

    private func refreshListModel() {
        let resolvedRepoPresentationByRepoId = repoPresentationByRepoId
        let key = InboxNotificationListModelKey(
            notifications: inboxAtom.notifications,
            grouping: prefsAtom.grouping,
            sort: prefsAtom.sort,
            searchText: searchText,
            filter: activeFilter,
            collapsedGroups: sidebarCache.collapsedInboxGroups,
            repoPresentationFingerprint: Self.repoPresentationFingerprint(resolvedRepoPresentationByRepoId)
        )
        guard key != cachedListModelKey else { return }
        cachedListModelKey = key
        cachedListModel = InboxNotificationListModel(
            notifications: key.notifications,
            grouping: key.grouping,
            sort: key.sort,
            searchText: key.searchText,
            filter: key.filter,
            collapsedGroups: key.collapsedGroups,
            repoPresentation: { repoId in
                guard let repoId else { return nil }
                return resolvedRepoPresentationByRepoId[repoId]
            }
        )
    }

    static func repoPresentationByRepoId(
        repos: [Repo],
        repoEnrichmentByRepoId: [UUID: RepoEnrichment],
        checkoutColors: [SidebarCheckoutColorKey: String]
    ) -> [UUID: InboxNotificationRepoGroupPresentation] {
        let sidebarRepos = repos.map(RepoPresentationItem.init(repo:))
        let repoMetadataById = RepoPresentationColoring.buildRepoMetadata(
            repos: sidebarRepos,
            repoEnrichmentByRepoId: repoEnrichmentByRepoId
        )
        let resolvedGroups = RepoPresentationGrouping.buildGroups(
            repos: sidebarRepos,
            metadataByRepoId: repoMetadataById
        )
        let checkoutColorOverrides = Dictionary(
            uniqueKeysWithValues: checkoutColors.map { key, value in
                (key.rawValue, value)
            }
        )
        let originalReposByGroupId = Dictionary(grouping: sidebarRepos) { repo in
            repoMetadataById[repo.id]?.groupKey ?? "path:\(repo.repoPath.standardizedFileURL.path)"
        }

        var presentationsByRepoId: [UUID: InboxNotificationRepoGroupPresentation] = [:]
        for group in resolvedGroups {
            let sourceGroupAccentColorHex = RepoPresentationColoring.sourceGroupColorHex(
                for: group,
                checkoutColorOverrides: checkoutColorOverrides
            )
            for repo in originalReposByGroupId[group.id] ?? group.repos {
                presentationsByRepoId[repo.id] = InboxNotificationRepoGroupPresentation(
                    groupId: group.id,
                    title: group.repoTitle,
                    organizationName: group.organizationName,
                    accentColorHex: sourceGroupAccentColorHex
                )
            }
        }
        return presentationsByRepoId
    }

    static func repoPresentationFingerprint(
        _ presentationsByRepoId: [UUID: InboxNotificationRepoGroupPresentation]
    ) -> String {
        presentationsByRepoId
            .map { repoId, presentation in
                [
                    repoId.uuidString,
                    presentation.groupId ?? "",
                    presentation.title,
                    presentation.organizationName ?? "",
                    presentation.accentColorHex ?? "",
                ]
                .joined(separator: ":")
            }
            .sorted()
            .joined(separator: "|")
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

    func clearReadInboxNotifications() {
        dispatcher.dispatch(.clearReadInboxNotifications)
    }

    private func clearFilter() {
        inboxFilterDraft.clear()
        activeFilter = nil
    }

    private func applyPendingFilterDraft() {
        guard let filter = inboxFilterDraft.consume() else { return }
        activeFilter = filter
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
        let didMarkRead = inboxAtom.markRead(id: notification.id)
        let didDismiss = inboxAtom.dismissFromPaneInbox(id: notification.id)
        if !didMarkRead || !didDismiss {
            inboxNotificationSidebarLogger.warning(
                "Inbox activation used stale notification id \(notification.id.uuidString, privacy: .public)"
            )
        }

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
