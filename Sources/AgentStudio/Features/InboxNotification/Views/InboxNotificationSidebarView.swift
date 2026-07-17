import AppKit
import Foundation
import SwiftUI
import os.log

private let inboxNotificationSidebarLogger = Logger(
    subsystem: "com.agentstudio",
    category: "InboxNotificationSidebarView"
)

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
    let workspaceRepositoryTopologyAtom: RepositoryTopologyAtom
    let repoCache: RepoCacheAtom
    let dispatcher: AppCommandDispatcher
    let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    let initialProjectionTrigger: String
    let onRefocusActivePane: @MainActor @Sendable () -> Void

    @State private var searchText = ""
    @State private var cachedListModel: InboxNotificationListModel
    @State private var cachedListModelKey: InboxNotificationListProjectionKey
    @State private var projectionWorker = InboxNotificationListProjectionWorker()
    @State private var projectionTask: Task<Void, Never>?
    @State private var projectionGeneration = 0
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
        workspaceRepositoryTopologyAtom: RepositoryTopologyAtom,
        repoCache: RepoCacheAtom,
        dispatcher: AppCommandDispatcher,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder? = nil,
        initialProjectionTrigger: String = "startup_diagnostic",
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
        self.performanceTraceRecorder = performanceTraceRecorder
        self.initialProjectionTrigger = initialProjectionTrigger
        self.onRefocusActivePane = onRefocusActivePane
        let initialRepoEnrichmentByRepoId = Self.repoEnrichmentByRepoId(
            repos: workspaceRepositoryTopologyAtom.repos,
            repoCache: repoCache
        )
        let initialRepoPresentationByRepoId = Self.repoPresentationByRepoId(
            repos: workspaceRepositoryTopologyAtom.repos,
            repoEnrichmentByRepoId: initialRepoEnrichmentByRepoId
        )
        let initialKey = InboxNotificationListProjectionKey(
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
        self._cachedListModel = State(initialValue: .empty)
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
                onSelectGrouping: selectGrouping,
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
            refreshListModel(force: true)
        }
        .onDisappear {
            projectionTask?.cancel()
            projectionTask = nil
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
            )
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

    private func refreshListModel(force: Bool = false) {
        let clock = ContinuousClock()
        let requestBuildStart = clock.now
        let resolvedRepoPresentationByRepoId = repoPresentationByRepoId
        let key = InboxNotificationListProjectionKey(
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
        guard force || key != cachedListModelKey else { return }
        if projectionTask != nil {
            performanceTraceRecorder?.record(
                .sidebarProjection,
                attributes: sidebarProjectionTraceAttributes(
                    for: key,
                    phase: "projection_worker",
                    extra: ["agentstudio.performance.sidebar.cancellation.count": .int(1)]
                )
            )
        }
        projectionGeneration += 1
        let generation = projectionGeneration
        let projectionTrigger = sidebarProjectionTrigger(previous: cachedListModelKey, next: key)
        cachedListModelKey = key
        projectionTask?.cancel()
        let request = InboxNotificationListProjectionRequest(
            generation: generation,
            key: key,
            trigger: projectionTrigger,
            repoPresentationByRepoId: resolvedRepoPresentationByRepoId
        )
        let requestBuildDuration = requestBuildStart.duration(to: clock.now)
        performanceTraceRecorder?.recordDuration(
            .sidebarProjection,
            duration: requestBuildDuration,
            attributes: sidebarProjectionTraceAttributes(
                for: key,
                trigger: projectionTrigger,
                phase: "request_build_mainactor",
                extra: [
                    "agentstudio.performance.sidebar.request_build_mainactor_elapsed_ms": .double(
                        AgentStudioPerformanceTraceRecorder.milliseconds(from: requestBuildDuration)),
                    "agentstudio.performance.sidebar.group.count": .int(0),
                ]
            )
        )
        let worker = projectionWorker
        projectionTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            do {
                let result = try await worker.project(request)
                guard !Task.isCancelled else { return }
                applyProjectionResult(result)
            } catch is CancellationError {
                clearProjectionTaskIfCurrent(generation: generation)
            } catch {
                inboxNotificationSidebarLogger.error(
                    "Inbox list projection failed for generation \(generation, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                clearProjectionTaskIfCurrent(generation: generation)
            }
        }
    }

    private func clearProjectionTaskIfCurrent(generation: Int) {
        guard generation == projectionGeneration else { return }
        projectionTask = nil
    }

    private func applyProjectionResult(_ result: InboxNotificationListProjectionResult) {
        guard result.generation == projectionGeneration, result.key == cachedListModelKey else {
            performanceTraceRecorder?.record(
                .sidebarProjection,
                attributes: sidebarProjectionTraceAttributes(
                    for: result.key,
                    trigger: result.trigger,
                    phase: "mainactor_apply",
                    extra: ["agentstudio.performance.sidebar.stale_discard.count": .int(1)]
                )
            )
            return
        }

        performanceTraceRecorder?.recordDuration(
            .sidebarProjection,
            duration: result.workerDuration,
            attributes: sidebarProjectionTraceAttributes(
                for: result.key,
                trigger: result.trigger,
                phase: "projection_worker",
                extra: [
                    "agentstudio.performance.sidebar.total_worker_elapsed_ms": .double(
                        AgentStudioPerformanceTraceRecorder.milliseconds(from: result.workerDuration)),
                    "agentstudio.performance.sidebar.group.count": .int(result.model.sections.count),
                ]
            )
        )

        let clock = ContinuousClock()
        let applyStart = clock.now
        cachedListModel = result.model
        projectionTask = nil
        let applyDuration = applyStart.duration(to: clock.now)
        performanceTraceRecorder?.recordDuration(
            .sidebarProjection,
            duration: applyDuration,
            attributes: sidebarProjectionTraceAttributes(
                for: result.key,
                trigger: result.trigger,
                phase: "mainactor_apply",
                extra: [
                    "agentstudio.performance.sidebar.mainactor_apply_elapsed_ms": .double(
                        AgentStudioPerformanceTraceRecorder.milliseconds(from: applyDuration)),
                    "agentstudio.performance.sidebar.group.count": .int(result.model.sections.count),
                ]
            )
        )
    }

    private func sidebarProjectionTraceAttributes(
        for key: InboxNotificationListProjectionKey,
        trigger: String = "startup_diagnostic",
        phase: String,
        extra: [String: AgentStudioTraceValue] = [:]
    ) -> [String: AgentStudioTraceValue] {
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.performance.sidebar.surface": .string("inbox"),
            "agentstudio.performance.sidebar.phase": .string(phase),
            "agentstudio.performance.sidebar.trigger": .string(trigger),
            "agentstudio.performance.sidebar.query_state": .string(key.searchText.isEmpty ? "empty" : "non_empty"),
            "agentstudio.performance.sidebar.group_mode": .string(key.grouping.performanceMetricValue),
            "agentstudio.performance.sidebar.input.count": .int(key.notifications.count),
            "agentstudio.performance.sidebar.query_character.count": .int(key.searchText.count),
        ]
        attributes.merge(extra) { _, newValue in newValue }
        return attributes
    }

    private func sidebarProjectionTrigger(
        previous: InboxNotificationListProjectionKey?,
        next: InboxNotificationListProjectionKey
    ) -> String {
        guard let previous else {
            return initialProjectionTrigger == "surface_switch"
                ? "surface_switch"
                : (next.grouping == .byTab ? "startup_diagnostic" : "grouping_switch")
        }
        if previous.grouping != next.grouping {
            return "grouping_switch"
        }
        if previous.searchText != next.searchText {
            return "search"
        }
        if previous.collapsedGroups != next.collapsedGroups {
            return "collapse_toggle"
        }
        return "data_refresh"
    }

    static func repoPresentationByRepoId(
        repos: [Repo],
        repoEnrichmentByRepoId: [UUID: RepoEnrichment]
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
        let originalReposByGroupId = Dictionary(grouping: sidebarRepos) { repo in
            repoMetadataById[repo.id]?.groupKey ?? "path:\(repo.repoPath.standardizedFileURL.path)"
        }

        var presentationsByRepoId: [UUID: InboxNotificationRepoGroupPresentation] = [:]
        for group in resolvedGroups {
            let sourceGroupAccentColorHex = RepoPresentationColoring.sourceGroupColorHex(
                for: group
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

    private func selectGrouping(_ grouping: InboxNotificationGrouping) {
        let command: AppCommand =
            switch grouping {
            case .byTab: .setInboxGroupingTab
            case .byRepo: .setInboxGroupingRepo
            case .byPane: .setInboxGroupingPane
            case .none: .setInboxGroupingNone
            }
        dispatcher.dispatch(command)
    }

    private func toggleRowStateFilter() {
        displayOverride = nil
        dispatcher.dispatch(
            AppCommandExecutionRequest(
                command: .setInboxRowStateFilter,
                arguments: .inboxRowStateFilter(effectiveRowStateFilter == .unreadOnly ? .all : .unreadOnly)
            )
        )
    }

    private func cycleContentMode() {
        displayOverride = nil
        dispatcher.dispatch(
            AppCommandExecutionRequest(
                command: .setInboxContentMode,
                arguments: .inboxContentMode(effectiveContentMode == .rollUpAlerts ? .all : .rollUpAlerts)
            )
        )
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
        case .openFullDiskAccessSettings:
            NSWorkspace.shared.open(FullDiskAccessSettings.url)
        }
    }
}
