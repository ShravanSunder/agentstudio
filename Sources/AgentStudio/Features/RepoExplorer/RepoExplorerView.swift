import AppKit
import Foundation
import SwiftUI

enum RepoExplorerFocus: Hashable {
    case filter
}

final class RepoExplorerFocusableView: NSView {
    var onFocusChange: @MainActor (Bool) -> Void = { _ in }

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
    }
}

struct RepoExplorerFocusBridge: NSViewRepresentable {
    let uiState: WorkspaceSidebarState

    func makeNSView(context: Context) -> RepoExplorerFocusableView {
        let view = RepoExplorerFocusableView()
        view.identifier = RepoExplorerView.focusTargetIdentifier
        view.onFocusChange = { hasFocus in
            uiState.setSidebarHasFocus(hasFocus)
        }
        return view
    }

    func updateNSView(_ nsView: RepoExplorerFocusableView, context: Context) {
        nsView.onFocusChange = { hasFocus in
            uiState.setSidebarHasFocus(hasFocus)
        }
    }

    static func dismantleNSView(_ nsView: RepoExplorerFocusableView, coordinator: ()) {
        MainActor.assumeIsolated {
            nsView.onFocusChange(false)
        }
    }
}

enum RepoExplorerFocusPublisher {
    @MainActor
    static func publish(
        focusedField: RepoExplorerFocus?,
        into uiState: WorkspaceSidebarState
    ) {
        uiState.setSidebarHasFocus(focusedField != nil)
    }
}

private struct RepoExplorerVisibleRowsBridge: NSViewRepresentable {
    let entries: [RepoExplorerListEntry]
    let onVisibleWorktreeIdsChange: @MainActor @Sendable (Set<UUID>) -> Void

    func makeNSView(context: Context) -> RepoExplorerVisibleRowsObserverView {
        let view = RepoExplorerVisibleRowsObserverView()
        view.entries = entries
        view.onVisibleWorktreeIdsChange = onVisibleWorktreeIdsChange
        return view
    }

    func updateNSView(_ nsView: RepoExplorerVisibleRowsObserverView, context: Context) {
        nsView.entries = entries
        nsView.onVisibleWorktreeIdsChange = onVisibleWorktreeIdsChange
        nsView.scheduleVisibleRowsReport()
    }

    static func dismantleNSView(_ nsView: RepoExplorerVisibleRowsObserverView, coordinator: ()) {
        nsView.stopObservingTable()
    }
}

@MainActor
private final class RepoExplorerVisibleRowsObserverView: NSView {
    var entries: [RepoExplorerListEntry] = []
    var onVisibleWorktreeIdsChange: @MainActor @Sendable (Set<UUID>) -> Void = { _ in }

    private weak var observedTableView: NSTableView?
    private var boundsObserver: NSObjectProtocol?
    private var reportTask: Task<Void, Never>?
    private var lastReportedWorktreeIds: Set<UUID> = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleTableResolution()
    }

    func scheduleVisibleRowsReport() {
        guard reportTask == nil else { return }
        reportTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.reportTask = nil
            self.reportVisibleWorktrees()
        }
    }

    func stopObservingTable() {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
            self.boundsObserver = nil
        }
        reportTask?.cancel()
        reportTask = nil
        observedTableView = nil
    }

    private func scheduleTableResolution() {
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.resolveTableViewIfNeeded()
            self?.scheduleVisibleRowsReport()
        }
    }

    private func resolveTableViewIfNeeded() {
        guard window != nil else { return }
        let tableView = nearestTableView()
        guard observedTableView !== tableView else { return }
        stopObservingTable()
        observedTableView = tableView
        guard let clipView = tableView?.enclosingScrollView?.contentView else { return }
        clipView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleVisibleRowsReport()
            }
        }
    }

    private func nearestTableView() -> NSTableView? {
        var candidate: NSView? = self
        while let current = candidate {
            if let tableView = current as? NSTableView {
                return tableView
            }
            candidate = current.superview
        }
        return window?.contentView?.firstDescendant(ofType: NSTableView.self)
    }

    private func reportVisibleWorktrees() {
        resolveTableViewIfNeeded()
        guard let tableView = observedTableView else { return }
        let visibleRows = tableView.rows(in: tableView.visibleRect)
        let visibleWorktreeIds = visibleWorktreeIds(in: visibleRows)
        guard visibleWorktreeIds != lastReportedWorktreeIds else { return }
        lastReportedWorktreeIds = visibleWorktreeIds
        onVisibleWorktreeIdsChange(visibleWorktreeIds)
    }

    private func visibleWorktreeIds(in rowRange: NSRange) -> Set<UUID> {
        guard rowRange.location != NSNotFound else { return [] }
        let lowerBound = max(0, rowRange.location)
        let upperBound = min(entries.count, rowRange.location + rowRange.length)
        guard lowerBound < upperBound else { return [] }

        return entries[lowerBound..<upperBound].reduce(into: Set<UUID>()) { result, entry in
            guard case .resolvedWorktreeRow(_, _, let worktreeId) = entry else { return }
            result.insert(worktreeId)
        }
    }
}

extension NSView {
    fileprivate func firstDescendant<T>(ofType type: T.Type) -> T? {
        if let match = self as? T {
            return match
        }
        for subview in subviews {
            if let match = subview.firstDescendant(ofType: type) {
                return match
            }
        }
        return nil
    }
}

/// Sidebar content grouped by repository identity (worktree family / remote).
@MainActor
struct RepoExplorerView: View {
    typealias SidebarProjection = RepoExplorerSidebarProjection

    let store: WorkspaceStore
    let onRefocusActivePane: () -> Void
    let onSidebarVisibleWorktreesChanged: @MainActor @Sendable () -> Void
    let onShowNotificationsForWorktree: (Worktree) -> Void
    let unreadCount: (Worktree) -> Int
    let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    static let focusTargetIdentifier = NSUserInterfaceItemIdentifier("repoExplorerFocusTarget")
    static let surfaceListPolicy = SidebarSurfaceListPolicy.nativeSidebarList
    static let groupHeaderChromePolicy = SidebarRepoGroupHeader<EmptyView>.chromePolicy

    private var repoCache: RepoCacheAtom {
        atom(\.repoCache)
    }

    private var uiState: WorkspaceSidebarState {
        atom(\.workspaceSidebarState)
    }

    private var sidebarCache: SidebarCacheState {
        atom(\.sidebarCache)
    }

    private var sidebarVisibleWorktreesRuntime: SidebarVisibleWorktreesRuntimeAtom {
        atom(\.sidebarVisibleWorktreesRuntime)
    }

    @State private var filterText: String = ""
    @State private var debouncedQuery: String = ""
    @FocusState private var focusedField: RepoExplorerFocus?

    @State private var debounceTask: Task<Void, Never>?

    private static let filterDebounceMilliseconds = 25

    private var sidebarRepos: [RepoPresentationItem] {
        store.repositoryTopologyAtom.repos.map(RepoPresentationItem.init(repo:))
    }

    private var sidebarSnapshot: RepoExplorerSnapshot {
        RepoExplorerSnapshot(
            repos: sidebarRepos,
            repoEnrichmentByRepoId: sidebarRepoEnrichmentByRepoId,
            query: debouncedQuery
        )
    }

    private var sidebarRepoEnrichmentByRepoId: [UUID: RepoEnrichment] {
        Dictionary(
            uniqueKeysWithValues: sidebarRepos.compactMap { repo in
                repoCache.repoEnrichment(for: repo.id).map { (repo.id, $0) }
            }
        )
    }

    private var sidebarProjection: SidebarProjection {
        let snapshot = sidebarSnapshot
        return performanceTraceRecorder?.measure(
            .sidebarProjection,
            attributes: [
                "agentstudio.performance.sidebar.repo.count": .int(snapshot.repos.count),
                "agentstudio.performance.sidebar.query_character.count": .int(snapshot.query.count),
            ]
        ) {
            RepoExplorerProjection.project(snapshot)
        } ?? RepoExplorerProjection.project(snapshot)
    }

    private var sidebarRowIndex: RepoExplorerRowIndex {
        let projection = sidebarProjection
        let expandedGroupIds = Set(sidebarCache.expandedGroups.map(\.rawValue))
        return performanceTraceRecorder?.measure(
            .sidebarRowIndex,
            attributes: [
                "agentstudio.performance.sidebar.group.count": .int(projection.resolvedGroups.count),
                "agentstudio.performance.sidebar.loading_repo.count": .int(projection.loadingRepos.count),
                "agentstudio.performance.sidebar.expanded_group.count": .int(expandedGroupIds.count),
                "agentstudio.performance.sidebar.is_filtering": .bool(isFiltering),
            ]
        ) {
            RepoExplorerRowIndex(
                projection: projection,
                expandedGroupIds: expandedGroupIds,
                isFiltering: isFiltering
            )
        }
            ?? RepoExplorerRowIndex(
                projection: projection,
                expandedGroupIds: expandedGroupIds,
                isFiltering: isFiltering
            )
    }

    private var isFiltering: Bool {
        !debouncedQuery.isEmpty
    }

    private var worktreeStatusById: [UUID: GitBranchStatus] {
        let factsByWorktreeId = Self.worktreeFactsByWorktreeId(
            sidebarRepos: sidebarRepos,
            repoCache: repoCache
        )
        return Self.mergeBranchStatuses(
            worktreeEnrichmentsByWorktreeId: factsByWorktreeId.compactMapValues { $0.enrichment },
            pullRequestCountsByWorktreeId: factsByWorktreeId.compactMapValues { $0.pullRequestCount }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            RepoExplorerFocusBridge(
                uiState: uiState
            )
            .frame(width: 1, height: 1)
            .opacity(0.001)

            filterBar

            if sidebarProjection.showsNoResults {
                noResultsView
            } else {
                groupList
            }
        }
        .animation(.easeOut(duration: 0.15), value: uiState.isFilterVisible)
        .task {
            filterText = uiState.filterText
            debouncedQuery = uiState.filterText
        }
        .onDisappear {
            debounceTask?.cancel()
            updateSidebarVisibleWorktrees([])
            RepoExplorerFocusPublisher.publish(
                focusedField: nil,
                into: uiState
            )
        }
        .onChange(of: uiState.isFilterVisible) { _, isVisible in
            if isVisible {
                Task { @MainActor in
                    await Task.yield()
                    focusedField = .filter
                }
            } else {
                focusedField = nil
                if !filterText.isEmpty || !debouncedQuery.isEmpty {
                    filterText = ""
                    debouncedQuery = ""
                    uiState.setFilterText("")
                }
            }
        }
        .onChange(of: filterText) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            performanceTraceRecorder?.record(
                .sidebarFilterInput,
                attributes: [
                    "agentstudio.performance.sidebar.query_character.count": .int(trimmed.count),
                    "agentstudio.performance.sidebar.was_empty": .bool(trimmed.isEmpty),
                ]
            )
            uiState.setFilterText(trimmed)
            debounceTask?.cancel()
            if trimmed.isEmpty {
                withAnimation(.easeOut(duration: 0.12)) {
                    debouncedQuery = ""
                }
            } else {
                debounceTask = Task { @MainActor in
                    try? await Task.sleep(
                        nanoseconds: Duration.milliseconds(Self.filterDebounceMilliseconds).nanosecondsForTaskSleep)
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        debouncedQuery = trimmed
                    }
                }
            }
        }
        .onChange(of: focusedField) { _, newValue in
            RepoExplorerFocusPublisher.publish(
                focusedField: newValue,
                into: uiState
            )
        }
    }

    private var filterBar: some View {
        SidebarSearchField(
            placeholder: "Filter...",
            text: $filterText,
            focusedField: $focusedField,
            focusValue: .filter,
            clearHelp: LocalActionSpec.clearFilter.actionSpec.helpText,
            onExit: hideFilter,
            onDownArrow: {
                focusedField = nil
                return .handled
            }
        )
        .padding(.horizontal, AppStyles.Shell.Sidebar.SearchField.outerHorizontalPadding)
        .padding(.vertical, AppStyles.Shell.Sidebar.SearchField.outerVerticalPadding)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var noResultsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: AppStyles.General.Typography.text2xl))
                .foregroundStyle(.secondary)
                .opacity(0.5)

            Text("No results")
                .font(.system(size: AppStyles.General.Typography.textSm, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.animation(.easeOut(duration: 0.12)))
        .onAppear {
            updateSidebarVisibleWorktrees([])
        }
    }

    private var groupList: some View {
        let rowIndex = sidebarRowIndex
        return List {
            ForEach(rowIndex.entries) { entry in
                switch entry {
                case .resolvedGroupHeader(let group):
                    SidebarRepoGroupHeader(
                        isCollapsed: !isGroupExpanded(group.id),
                        icon: iconForGroup(group),
                        repoTitle: group.repoTitle,
                        organizationName: group.organizationName,
                        onToggle: { toggleGroupExpansion(group.id) }
                    )
                    .listRowInsets(
                        EdgeInsets(
                            top: 0,
                            leading: 0,
                            bottom: 0,
                            trailing: 0
                        )
                    )
                    .contextMenu {
                        Divider()

                        if let primaryRepo = Self.primaryRepoForGroup(group) {
                            Button(LocalActionSpec.revealInFinder.actionSpec.label) {
                                PathActions.revealInFinder(primaryRepo.repoPath)
                            }
                        }

                        Button(LocalActionSpec.refreshWorktrees.actionSpec.label) {
                            AppCommandDispatcher.shared.appCommandRouter?.refreshWorktrees()
                        }
                    }

                case .resolvedWorktreeRow(let groupId, let repoId, let worktreeId):
                    if let resolvedWorktreeContext = rowIndex.resolve(
                        groupId: groupId,
                        repoId: repoId,
                        worktreeId: worktreeId
                    ) {
                        RepoExplorerWorktreeRow(
                            worktree: resolvedWorktreeContext.worktree,
                            checkoutTitle: checkoutTitle(
                                for: resolvedWorktreeContext.worktree,
                                in: resolvedWorktreeContext.repo
                            ),
                            branchName: branchName(for: resolvedWorktreeContext.worktree),
                            checkoutIconKind: checkoutIconKind(
                                for: resolvedWorktreeContext.worktree,
                                in: resolvedWorktreeContext.repo
                            ),
                            iconColor: colorForCheckout(
                                repo: resolvedWorktreeContext.repo,
                                in: resolvedWorktreeContext.group
                            ),
                            branchStatus: worktreeStatusById[resolvedWorktreeContext.worktree.id] ?? .unknown,
                            unreadCount: unreadCount(resolvedWorktreeContext.worktree),
                            bridgeCommandResolution: AppCommandDispatcher.shared
                                .bridgePaneCommandTarget(
                                    worktreeId: resolvedWorktreeContext.worktree.id
                                )?.resolution ?? .create,
                            onUnreadPillTap: {
                                onShowNotificationsForWorktree(resolvedWorktreeContext.worktree)
                            },
                            onOpen: {
                                AppCommandDispatcher.shared.dispatch(
                                    .openWorktree,
                                    target: resolvedWorktreeContext.worktree.id,
                                    targetType: .worktree
                                )
                            },
                            onOpenNew: {
                                AppCommandDispatcher.shared.dispatch(
                                    .openNewTerminalInTab,
                                    target: resolvedWorktreeContext.worktree.id,
                                    targetType: .worktree
                                )
                            },
                            onReview: {
                                AppCommandDispatcher.shared.dispatch(
                                    .showBridgeReview,
                                    target: resolvedWorktreeContext.worktree.id,
                                    targetType: .worktree
                                )
                            },
                            onOpenFiles: {
                                AppCommandDispatcher.shared.dispatch(
                                    .showBridgeFiles,
                                    target: resolvedWorktreeContext.worktree.id,
                                    targetType: .worktree
                                )
                            },
                            onOpenReviewInNewTab: {
                                AppCommandDispatcher.shared.dispatch(
                                    .openBridgeReviewInNewTab,
                                    target: resolvedWorktreeContext.worktree.id,
                                    targetType: .worktree
                                )
                            },
                            onOpenFilesInNewTab: {
                                AppCommandDispatcher.shared.dispatch(
                                    .openBridgeFilesInNewTab,
                                    target: resolvedWorktreeContext.worktree.id,
                                    targetType: .worktree
                                )
                            },
                            onOpenInPane: {
                                AppCommandDispatcher.shared.dispatch(
                                    .openWorktreeInPane,
                                    target: resolvedWorktreeContext.worktree.id,
                                    targetType: .worktree
                                )
                            }
                        )
                        .listRowInsets(
                            EdgeInsets(
                                top: 0,
                                leading: AppStyles.Shell.Sidebar.groupChildRowLeadingInset,
                                bottom: 0,
                                trailing: 0
                            )
                        )
                    }
                }
            }

            if !rowIndex.projection.loadingRepos.isEmpty {
                Section {
                    ForEach(rowIndex.projection.loadingRepos, id: \.id) { repo in
                        RepoExplorerLoadingRepoRow(repoName: repo.name)
                            .listRowInsets(
                                EdgeInsets(
                                    top: 0,
                                    leading: AppStyles.Shell.Sidebar.groupChildRowLeadingInset,
                                    bottom: 0,
                                    trailing: 8
                                )
                            )
                            .listRowBackground(Color.clear)
                            .allowsHitTesting(false)
                    }
                } header: {
                    RepoExplorerLoadingSectionHeaderRow()
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }
            }
        }
        .sidebarSurfaceListStyle(Self.surfaceListPolicy)
        .background(
            RepoExplorerVisibleRowsBridge(
                entries: rowIndex.entries,
                onVisibleWorktreeIdsChange: updateSidebarVisibleWorktrees
            )
        )
        .transition(.opacity.animation(.easeOut(duration: 0.12)))
    }

    private func updateSidebarVisibleWorktrees(_ worktreeIds: Set<UUID>) {
        sidebarVisibleWorktreesRuntime.setVisibleWorktreeIds(worktreeIds)
        onSidebarVisibleWorktreesChanged()
    }

    private func colorForCheckout(repo: RepoPresentationItem, in group: RepoPresentationGroup) -> Color {
        let colorHex = RepoPresentationColoring.checkoutColorHex(
            for: repo, in: group
        )
        return Color(nsColor: NSColor(hex: colorHex) ?? .controlAccentColor)
    }

    private func iconForGroup(_ group: RepoPresentationGroup) -> AppEntityIcon {
        Self.sourceGroupIcon(for: group)
    }

    private func isGroupExpanded(_ groupId: String) -> Bool {
        isFiltering || sidebarCache.expandedGroups.contains(SidebarGroupKey(groupId))
    }

    private func toggleGroupExpansion(_ groupId: String) {
        guard !isFiltering else { return }

        let key = SidebarGroupKey(groupId)
        sidebarCache.setGroupExpanded(key, isExpanded: !sidebarCache.expandedGroups.contains(key))
    }

    private func checkoutTitle(for worktree: Worktree, in repo: RepoPresentationItem) -> String {
        let folderName = worktree.path.lastPathComponent
        if !folderName.isEmpty {
            return folderName
        }
        return repo.name
    }

    static func checkoutIconKind(
        for worktree: Worktree,
        in repo: RepoPresentationItem
    ) -> RepoExplorerCheckoutIconKind {
        let isMainCheckout =
            worktree.isMainWorktree
            || worktree.path.standardizedFileURL.path == repo.repoPath.standardizedFileURL.path

        if !isMainCheckout {
            return .gitWorktree
        }

        return .mainCheckout
    }

    private func checkoutIconKind(
        for worktree: Worktree,
        in repo: RepoPresentationItem
    ) -> RepoExplorerCheckoutIconKind {
        Self.checkoutIconKind(for: worktree, in: repo)
    }

    private func branchName(for worktree: Worktree) -> String {
        atom(\.paneDisplay).resolvedBranchName(
            worktree: worktree,
            enrichment: repoCache.worktreeEnrichment(for: worktree.id)
        )
    }

    private func hideFilter() {
        filterText = ""
        debouncedQuery = ""
        focusedField = nil
        uiState.setFilterText("")
        uiState.setFilterVisible(false)
        onRefocusActivePane()
    }

    private func openRepoInFinder(_ path: URL) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path.path)
    }

}

private struct RepoExplorerLoadingSectionHeaderRow: View {
    var body: some View {
        HStack(spacing: AppStyles.General.Spacing.standard) {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)

            HStack(spacing: AppStyles.General.Spacing.tight) {
                ProgressView()
                    .controlSize(.small)

                Text("Scanning...")
                    .font(.system(size: AppStyles.General.Typography.textXs, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, AppStyles.General.Spacing.standard)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.06))
            )

            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RepoExplorerLoadingRepoRow: View {
    let repoName: String

    var body: some View {
        HStack(spacing: AppStyles.General.Spacing.standard) {
            Text(repoName)
                .font(.system(size: AppStyles.General.Typography.textBase))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(0.55)
    }
}

extension RepoExplorerView {
    static func checkoutColorHex(
        for repo: RepoPresentationItem,
        in group: RepoPresentationGroup
    ) -> String {
        RepoPresentationColoring.checkoutColorHex(
            for: repo,
            in: group
        )
    }

    static func sourceGroupIcon(
        for group: RepoPresentationGroup
    ) -> AppEntityIcon {
        guard
            let colorHex = RepoPresentationColoring.sourceGroupColorHex(
                for: group
            )
        else {
            return .repo
        }
        return .coloredRepo(
            colorHex: colorHex
        )
    }

    static func buildRepoMetadata(
        repos: [RepoPresentationItem],
        repoEnrichmentByRepoId: [UUID: RepoEnrichment]
    ) -> [UUID: RepoIdentityMetadata] {
        RepoPresentationColoring.buildRepoMetadata(
            repos: repos,
            repoEnrichmentByRepoId: repoEnrichmentByRepoId
        )
    }

    static func buildListEntries(
        groups: [RepoPresentationGroup],
        expandedGroupIds: Set<String>,
        isFiltering: Bool
    ) -> [RepoExplorerListEntry] {
        RepoExplorerRowIndex.buildListEntries(
            groups: groups,
            expandedGroupIds: expandedGroupIds,
            isFiltering: isFiltering
        )
    }

    static func projectionFingerprint(for projection: SidebarProjection) -> String {
        let resolvedGroupsFingerprint = projection.resolvedGroups.map { group in
            let repoIds = group.repos.map(\.id.uuidString).joined(separator: ",")
            return "\(group.id):\(repoIds)"
        }
        .joined(separator: "|")

        let loadingFingerprint = projection.loadingRepos
            .map { "\($0.id.uuidString):\($0.name)" }
            .joined(separator: "|")

        return """
            resolved[\(resolvedGroupsFingerprint)]\
            /loading[\(loadingFingerprint)]\
            /noResults[\(projection.showsNoResults)]
            """
    }

    static func projectSidebar(
        repos: [RepoPresentationItem],
        repoEnrichmentByRepoId: [UUID: RepoEnrichment],
        query: String
    ) -> SidebarProjection {
        RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: repos,
                repoEnrichmentByRepoId: repoEnrichmentByRepoId,
                query: query
            )
        )
    }

    static func resolvedRepos(
        _ repos: [RepoPresentationItem],
        enrichmentByRepoId: [UUID: RepoEnrichment]
    ) -> [RepoPresentationItem] {
        RepoExplorerProjection.resolvedRepos(repos, enrichmentByRepoId: enrichmentByRepoId)
    }

    static func loadingRepos(
        _ repos: [RepoPresentationItem],
        enrichmentByRepoId: [UUID: RepoEnrichment]
    ) -> [RepoPresentationItem] {
        RepoExplorerProjection.loadingRepos(repos, enrichmentByRepoId: enrichmentByRepoId)
    }

    static func primaryRepoForGroup(_ group: RepoPresentationGroup) -> RepoPresentationItem? {
        RepoPresentationColoring.primaryRepoForSourceGroup(group)
    }

    static func mergeBranchStatuses(
        worktreeEnrichmentsByWorktreeId: [UUID: WorktreeEnrichment],
        pullRequestCountsByWorktreeId: [UUID: Int]
    ) -> [UUID: GitBranchStatus] {
        GitBranchStatus.merge(
            worktreeEnrichmentsByWorktreeId: worktreeEnrichmentsByWorktreeId,
            pullRequestCountsByWorktreeId: pullRequestCountsByWorktreeId
        )
    }

    static func branchStatus(
        enrichment: WorktreeEnrichment?,
        pullRequestCount: Int?
    ) -> GitBranchStatus {
        GitBranchStatus.status(enrichment: enrichment, pullRequestCount: pullRequestCount)
    }

    static func sortedWorktrees(for repo: RepoPresentationItem) -> [Worktree] {
        RepoExplorerRowIndex.sortedWorktrees(for: repo)
    }

    static func worktreeFactsByWorktreeId(
        sidebarRepos: [RepoPresentationItem],
        repoCache: RepoCacheAtom
    ) -> [UUID: RepoWorktreeCacheFacts] {
        var factsByWorktreeId: [UUID: RepoWorktreeCacheFacts] = [:]
        for worktree in sidebarRepos.flatMap(\.worktrees) where factsByWorktreeId[worktree.id] == nil {
            factsByWorktreeId[worktree.id] = repoCache.worktreeFacts(for: worktree.id)
        }
        return factsByWorktreeId
    }
}
