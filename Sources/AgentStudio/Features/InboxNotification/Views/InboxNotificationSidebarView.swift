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
    let contentMode: InboxNotificationContentMode
    let rowStateFilter: InboxNotificationRowStateFilter
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
    let uiState: WorkspaceSidebarState
    let sidebarCache: SidebarCacheState
    let inboxSidebarState: InboxSidebarState
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
    @State private var displayOverride: InboxNotificationDisplayOverride?
    @FocusState private var focusedField: InboxFocus?

    private let flashDelay = AsyncDelay.taskSleep

    init(
        inboxAtom: InboxNotificationAtom,
        prefsAtom: InboxNotificationPrefsAtom,
        uiState: WorkspaceSidebarState,
        sidebarCache: SidebarCacheState,
        inboxSidebarState: InboxSidebarState,
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
        self.inboxSidebarState = inboxSidebarState
        self.workspacePaneAtom = workspacePaneAtom
        self.workspaceRepositoryTopologyAtom = workspaceRepositoryTopologyAtom
        self.repoCache = repoCache
        self.dispatcher = dispatcher
        self.onRefocusActivePane = onRefocusActivePane
        let initialRepoEnrichmentByRepoId = Self.repoEnrichmentByRepoId(
            repos: workspaceRepositoryTopologyAtom.repos,
            repoCache: repoCache
        )
        let initialRepoPresentationByRepoId = Self.repoPresentationByRepoId(
            repos: workspaceRepositoryTopologyAtom.repos,
            repoEnrichmentByRepoId: initialRepoEnrichmentByRepoId,
            checkoutColors: sidebarCache.checkoutColors
        )
        let initialKey = InboxNotificationListModelKey(
            notifications: inboxAtom.notifications,
            grouping: prefsAtom.grouping,
            sort: prefsAtom.sort,
            searchText: "",
            filter: nil,
            contentMode: Self.globalSidebarContentMode(prefsAtom.globalInboxContentMode),
            rowStateFilter: prefsAtom.globalInboxRowStateFilter,
            collapsedGroups: inboxSidebarState.collapsedGroups,
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
                contentMode: Self.globalSidebarContentMode(prefsAtom.globalInboxContentMode),
                rowStateFilter: prefsAtom.globalInboxRowStateFilter,
                filter: nil,
                collapsedGroups: inboxSidebarState.collapsedGroups,
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
            contentMode: effectiveContentMode,
            rowStateFilter: effectiveRowStateFilter,
            sort: prefsAtom.sort,
            groupingMenuOpen: $groupingMenuOpen,
            grouping: prefsAtom.grouping,
            focusedField: $focusedField,
            sections: listModel.sections,
            flashingRowIds: flashingRowIds,
            actions: .init(
                onEscape: handleEscape,
                onToggleSort: toggleSort,
                onToggleRowStateFilter: toggleRowStateFilter,
                onCycleContentMode: cycleContentMode,
                onClearFilter: clearFilter,
                onClearReadHistory: clearReadInboxNotifications,
                onClearAllHistory: clearAllInboxNotifications,
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
        .onChange(of: prefsAtom.globalInboxContentMode) { _, _ in refreshListModel() }
        .onChange(of: prefsAtom.globalInboxRowStateFilter) { _, _ in refreshListModel() }
        .onChange(of: displayOverride) { _, _ in refreshListModel() }
        .onChange(of: searchText) { _, _ in refreshListModel() }
        .onChange(of: activeFilter) { _, _ in refreshListModel() }
        .onChange(of: inboxSidebarState.collapsedGroups) { _, _ in refreshListModel() }
        .onChange(of: repoPresentationFingerprint) { _, _ in refreshListModel() }
        .onChange(of: inboxSidebarState.pendingFilter) { _, _ in
            applyPendingFilterDraft()
        }
        .onChange(of: inboxSidebarState.pendingDisplayOverride) { _, _ in
            applyPendingFilterDraft()
        }
        .onChange(of: inboxSidebarState.dismissalGeneration) { _, _ in
            activeFilter = nil
            displayOverride = nil
        }
        .task {
            applyPendingFilterDraft()
        }
    }

    private var listModel: InboxNotificationListModel {
        cachedListModel
    }

    private var effectiveContentMode: InboxNotificationContentMode {
        Self.globalSidebarContentMode(displayOverride?.contentMode ?? prefsAtom.globalInboxContentMode)
    }

    private var effectiveRowStateFilter: InboxNotificationRowStateFilter {
        displayOverride?.rowStateFilter ?? prefsAtom.globalInboxRowStateFilter
    }

    private var activeFilterLabel: String? {
        Self.activeFilterLabel(activeFilter: activeFilter, notifications: inboxAtom.notifications)
    }

    private var repoPresentationByRepoId: [UUID: InboxNotificationRepoGroupPresentation] {
        Self.repoPresentationByRepoId(
            repos: workspaceRepositoryTopologyAtom.repos,
            repoEnrichmentByRepoId: Self.repoEnrichmentByRepoId(
                repos: workspaceRepositoryTopologyAtom.repos,
                repoCache: repoCache
            ),
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

    static func globalSidebarContentMode(_ contentMode: InboxNotificationContentMode) -> InboxNotificationContentMode {
        contentMode == .rollUpAlerts ? .rollUpAlerts : .all
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
            contentMode: effectiveContentMode,
            rowStateFilter: effectiveRowStateFilter,
            collapsedGroups: inboxSidebarState.collapsedGroups,
            repoPresentationFingerprint: Self.repoPresentationFingerprint(resolvedRepoPresentationByRepoId)
        )
        guard key != cachedListModelKey else { return }
        cachedListModelKey = key
        cachedListModel = InboxNotificationListModel(
            notifications: key.notifications,
            grouping: key.grouping,
            sort: key.sort,
            searchText: key.searchText,
            contentMode: key.contentMode,
            rowStateFilter: key.rowStateFilter,
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

    private static func repoEnrichmentByRepoId(
        repos: [Repo],
        repoCache: RepoCacheAtom
    ) -> [UUID: RepoEnrichment] {
        Dictionary(
            uniqueKeysWithValues: repos.compactMap { repo in
                repoCache.repoEnrichment(for: repo.id).map { (repo.id, $0) }
            }
        )
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
        dispatcher.dispatch(.toggleInboxNotificationSort)
    }

    private func toggleRowStateFilter() {
        displayOverride = nil
        prefsAtom.setGlobalInboxRowStateFilter(effectiveRowStateFilter == .unreadOnly ? .all : .unreadOnly)
    }

    private func cycleContentMode() {
        displayOverride = nil
        prefsAtom.setGlobalInboxContentMode(effectiveContentMode == .rollUpAlerts ? .all : .rollUpAlerts)
    }

    func clearReadInboxNotifications() {
        dispatcher.dispatch(.clearReadInboxNotifications)
    }

    func clearAllInboxNotifications() {
        dispatcher.dispatch(.clearAllInboxNotifications)
    }

    private func clearFilter() {
        inboxSidebarState.clearPendingFilter()
        inboxSidebarState.clearPendingDisplayOverride()
        activeFilter = nil
        displayOverride = nil
    }

    private func applyPendingFilterDraft() {
        if inboxSidebarState.consumeFilterClearOnNextRetarget() {
            activeFilter = nil
        }
        let filter = inboxSidebarState.consumePendingFilter()
        let override = inboxSidebarState.consumePendingDisplayOverride()
        if let filter {
            activeFilter = filter
        }
        if let override {
            displayOverride = override
        }
    }

    private func toggleGroupCollapse(_ sectionId: String) {
        inboxSidebarState.toggleGroupCollapse(InboxNotificationGroupKey(sectionId))
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
            Task { @MainActor [flashDelay] in
                try? await flashDelay.wait(.milliseconds(600))
                flashingRowIds.remove(rowId)
            }
        case .focusPane(let paneId):
            dispatcher.dispatch(.focusPane, target: paneId, targetType: .pane)
        }
    }
}
