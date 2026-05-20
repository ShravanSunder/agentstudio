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
    let uiState: UIStateAtom

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
        into uiState: UIStateAtom
    ) {
        uiState.setSidebarHasFocus(focusedField != nil)
    }
}

/// Sidebar content grouped by repository identity (worktree family / remote).
@MainActor
struct RepoExplorerView: View {
    struct SidebarProjection {
        let resolvedGroups: [RepoPresentationGroup]
        let loadingRepos: [RepoPresentationItem]
        let showsNoResults: Bool
    }

    let store: WorkspaceStore
    let onRefocusActivePane: () -> Void
    let onShowNotificationsForWorktree: (Worktree) -> Void
    let unreadCount: (Worktree) -> Int
    static let focusTargetIdentifier = NSUserInterfaceItemIdentifier("repoExplorerFocusTarget")
    static let surfaceListPolicy = SidebarSurfaceListPolicy.nativeSidebarList
    static let groupHeaderChromePolicy = SidebarRepoGroupHeader<EmptyView>.chromePolicy

    private var repoCache: RepoCacheAtom {
        atom(\.repoCache)
    }

    private var uiState: UIStateAtom {
        atom(\.uiState)
    }

    private var sidebarCache: SidebarCacheAtom {
        atom(\.sidebarCache)
    }

    @State private var filterText: String = ""
    @State private var debouncedQuery: String = ""
    @FocusState private var focusedField: RepoExplorerFocus?

    @State private var debounceTask: Task<Void, Never>?

    private static let filterDebounceMilliseconds = 25

    private var sidebarRepos: [RepoPresentationItem] {
        store.repositoryTopologyAtom.repos.map(RepoPresentationItem.init(repo:))
    }

    private var sidebarProjectionFingerprint: String {
        Self.projectionFingerprint(for: sidebarProjection)
    }

    private var sidebarProjection: SidebarProjection {
        Self.projectSidebar(
            repos: sidebarRepos,
            repoEnrichmentByRepoId: repoCache.repoEnrichmentByRepoId,
            query: debouncedQuery
        )
    }

    private var groups: [RepoPresentationGroup] {
        sidebarProjection.resolvedGroups
    }

    private var loadingReposList: [RepoPresentationItem] {
        sidebarProjection.loadingRepos
    }

    private var resolvedListEntries: [RepoExplorerListEntry] {
        Self.buildListEntries(
            groups: groups,
            expandedGroupIds: Set(sidebarCache.expandedGroups.map(\.rawValue)),
            isFiltering: isFiltering
        )
    }

    private var isFiltering: Bool {
        !debouncedQuery.isEmpty
    }

    private var checkoutColorOverrides: [String: String] {
        Dictionary(
            uniqueKeysWithValues: sidebarCache.checkoutColors.map { key, value in
                (key.rawValue, value)
            }
        )
    }

    private var worktreeStatusById: [UUID: GitBranchStatus] {
        Self.mergeBranchStatuses(
            worktreeEnrichmentsByWorktreeId: repoCache.worktreeEnrichmentByWorktreeId,
            pullRequestCountsByWorktreeId: repoCache.pullRequestCountByWorktreeId
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
            uiState.setFilterText(trimmed)
            debounceTask?.cancel()
            if trimmed.isEmpty {
                withAnimation(.easeOut(duration: 0.12)) {
                    debouncedQuery = ""
                }
            } else {
                debounceTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(Self.filterDebounceMilliseconds))
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
    }

    private var groupList: some View {
        List {
            ForEach(resolvedListEntries) { entry in
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
                                openRepoInFinder(primaryRepo.repoPath)
                            }
                        }

                        Button(LocalActionSpec.refreshWorktrees.actionSpec.label) {
                            CommandDispatcher.shared.appCommandRouter?.refreshWorktrees()
                        }
                    }

                case .resolvedWorktreeRow(let groupId, let repoId, let worktreeId):
                    if let resolvedWorktreeContext = resolvedWorktreeContext(
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
                            onUnreadPillTap: {
                                onShowNotificationsForWorktree(resolvedWorktreeContext.worktree)
                            },
                            onOpen: {
                                CommandDispatcher.shared.dispatch(
                                    .openWorktree,
                                    target: resolvedWorktreeContext.worktree.id,
                                    targetType: .worktree
                                )
                            },
                            onOpenNew: {
                                CommandDispatcher.shared.dispatch(
                                    .openNewTerminalInTab,
                                    target: resolvedWorktreeContext.worktree.id,
                                    targetType: .worktree
                                )
                            },
                            onOpenInPane: {
                                CommandDispatcher.shared.dispatch(
                                    .openWorktreeInPane,
                                    target: resolvedWorktreeContext.worktree.id,
                                    targetType: .worktree
                                )
                            },
                            onSetIconColor: { colorHex in
                                let key = resolvedWorktreeContext.repo.id.uuidString
                                sidebarCache.setCheckoutColor(colorHex, for: SidebarCheckoutColorKey(key))
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

            if !loadingReposList.isEmpty {
                Section {
                    ForEach(loadingReposList, id: \.id) { repo in
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
        .id(sidebarProjectionFingerprint)
        .transition(.opacity.animation(.easeOut(duration: 0.12)))
    }

    private func colorForCheckout(repo: RepoPresentationItem, in group: RepoPresentationGroup) -> Color {
        let colorHex = RepoPresentationColoring.checkoutColorHex(
            for: repo, in: group, checkoutColorOverrides: checkoutColorOverrides
        )
        return Color(nsColor: NSColor(hex: colorHex) ?? .controlAccentColor)
    }

    private func iconForGroup(_ group: RepoPresentationGroup) -> AppEntityIcon {
        Self.sourceGroupIcon(
            for: group,
            checkoutColorOverrides: checkoutColorOverrides
        )
    }

    private func isGroupExpanded(_ groupId: String) -> Bool {
        isFiltering || sidebarCache.expandedGroups.contains(SidebarGroupKey(groupId))
    }

    private func toggleGroupExpansion(_ groupId: String) {
        guard !isFiltering else { return }

        let key = SidebarGroupKey(groupId)
        sidebarCache.setGroupExpanded(key, isExpanded: !sidebarCache.expandedGroups.contains(key))
    }

    private func resolvedWorktreeContext(
        groupId: String,
        repoId: UUID,
        worktreeId: UUID
    ) -> (group: RepoPresentationGroup, repo: RepoPresentationItem, worktree: Worktree)? {
        guard let group = groups.first(where: { $0.id == groupId }) else { return nil }
        guard let repo = group.repos.first(where: { $0.id == repoId }) else { return nil }
        guard let worktree = repo.worktrees.first(where: { $0.id == worktreeId }) else { return nil }
        return (group, repo, worktree)
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
            enrichment: repoCache.worktreeEnrichmentByWorktreeId[worktree.id]
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

enum RepoExplorerListEntry: Identifiable {
    case resolvedGroupHeader(RepoPresentationGroup)
    case resolvedWorktreeRow(groupId: String, repoId: UUID, worktreeId: UUID)

    var id: String {
        switch self {
        case .resolvedGroupHeader(let group):
            return "group:\(group.id)"
        case .resolvedWorktreeRow(let groupId, let repoId, let worktreeId):
            return "worktree:\(groupId):\(repoId.uuidString):\(worktreeId.uuidString)"
        }
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

struct GitBranchStatus: Equatable, Sendable {
    enum SyncState: Equatable, Sendable {
        case synced
        case ahead(Int)
        case behind(Int)
        case diverged(ahead: Int, behind: Int)
        case noUpstream
        case unknown
    }

    let isDirty: Bool
    let syncState: SyncState
    let prCount: Int?
    let linesAdded: Int
    let linesDeleted: Int

    static let unknown = Self(isDirty: false, syncState: .unknown, prCount: nil, linesAdded: 0, linesDeleted: 0)
}

extension RepoExplorerView {
    static func checkoutColorHex(
        for repo: RepoPresentationItem,
        in group: RepoPresentationGroup,
        checkoutColorOverrides: [String: String] = [:]
    ) -> String {
        RepoPresentationColoring.checkoutColorHex(
            for: repo,
            in: group,
            checkoutColorOverrides: checkoutColorOverrides
        )
    }

    static func sourceGroupIcon(
        for group: RepoPresentationGroup,
        checkoutColorOverrides: [String: String] = [:]
    ) -> AppEntityIcon {
        guard
            let colorHex = RepoPresentationColoring.sourceGroupColorHex(
                for: group,
                checkoutColorOverrides: checkoutColorOverrides
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
        var entries: [RepoExplorerListEntry] = []

        for group in groups {
            entries.append(.resolvedGroupHeader(group))

            let shouldExpandGroup = isFiltering || expandedGroupIds.contains(group.id)
            guard shouldExpandGroup else { continue }

            for repo in group.repos {
                for worktree in sortedWorktrees(for: repo) {
                    entries.append(
                        .resolvedWorktreeRow(
                            groupId: group.id,
                            repoId: repo.id,
                            worktreeId: worktree.id
                        )
                    )
                }
            }
        }

        return entries
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
        let resolvedRepos = resolvedRepos(repos, enrichmentByRepoId: repoEnrichmentByRepoId)
        let loadingRepos = loadingRepos(repos, enrichmentByRepoId: repoEnrichmentByRepoId)
        let filteredResolvedRepos = RepoExplorerFilter.filter(repos: resolvedRepos, query: query)
        let filteredLoadingRepos = filterLoadingRepos(loadingRepos, query: query)
        let repoMetadataById = RepoPresentationColoring.buildRepoMetadata(
            repos: filteredResolvedRepos,
            repoEnrichmentByRepoId: repoEnrichmentByRepoId
        )
        let resolvedGroups = RepoPresentationGrouping.buildGroups(
            repos: filteredResolvedRepos,
            metadataByRepoId: repoMetadataById
        )

        return SidebarProjection(
            resolvedGroups: resolvedGroups,
            loadingRepos: filteredLoadingRepos,
            showsNoResults: !query.isEmpty && resolvedGroups.isEmpty && filteredLoadingRepos.isEmpty
        )
    }

    static func resolvedRepos(
        _ repos: [RepoPresentationItem],
        enrichmentByRepoId: [UUID: RepoEnrichment]
    ) -> [RepoPresentationItem] {
        repos.filter { repo in
            switch enrichmentByRepoId[repo.id] {
            case .resolvedLocal, .resolvedRemote:
                return true
            case .awaitingOrigin, .none:
                return false
            }
        }
    }

    static func loadingRepos(
        _ repos: [RepoPresentationItem],
        enrichmentByRepoId: [UUID: RepoEnrichment]
    ) -> [RepoPresentationItem] {
        repos.filter { repo in
            switch enrichmentByRepoId[repo.id] {
            case .resolvedLocal, .resolvedRemote:
                return false
            case .awaitingOrigin, .none:
                return true
            }
        }
    }

    private static func filterLoadingRepos(
        _ repos: [RepoPresentationItem],
        query: String
    ) -> [RepoPresentationItem] {
        let filteredRepos: [RepoPresentationItem]
        if query.isEmpty {
            filteredRepos = repos
        } else {
            filteredRepos = repos.filter { repo in
                repo.name.localizedCaseInsensitiveContains(query)
            }
        }

        return filteredRepos.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func primaryRepoForGroup(_ group: RepoPresentationGroup) -> RepoPresentationItem? {
        RepoPresentationColoring.primaryRepoForSourceGroup(group)
    }

    static func mergeBranchStatuses(
        worktreeEnrichmentsByWorktreeId: [UUID: WorktreeEnrichment],
        pullRequestCountsByWorktreeId: [UUID: Int]
    ) -> [UUID: GitBranchStatus] {
        let allWorktreeIds = Set(worktreeEnrichmentsByWorktreeId.keys).union(pullRequestCountsByWorktreeId.keys)
        var mergedByWorktreeId: [UUID: GitBranchStatus] = [:]
        mergedByWorktreeId.reserveCapacity(allWorktreeIds.count)

        for worktreeId in allWorktreeIds {
            let enrichment = worktreeEnrichmentsByWorktreeId[worktreeId]
            let pullRequestCount = pullRequestCountsByWorktreeId[worktreeId]
            mergedByWorktreeId[worktreeId] = branchStatus(
                enrichment: enrichment,
                pullRequestCount: pullRequestCount
            )
        }

        return mergedByWorktreeId
    }

    static func branchStatus(
        enrichment: WorktreeEnrichment?,
        pullRequestCount: Int?
    ) -> GitBranchStatus {
        guard let enrichment else {
            return GitBranchStatus(
                isDirty: GitBranchStatus.unknown.isDirty,
                syncState: GitBranchStatus.unknown.syncState,
                prCount: pullRequestCount,
                linesAdded: GitBranchStatus.unknown.linesAdded,
                linesDeleted: GitBranchStatus.unknown.linesDeleted
            )
        }

        let summary = enrichment.snapshot?.summary
        let isDirty: Bool
        if let summary {
            isDirty = summary.changed > 0 || summary.staged > 0 || summary.untracked > 0
        } else {
            isDirty = false
        }

        let syncState: GitBranchStatus.SyncState
        if let summary {
            switch summary.hasUpstream {
            case .some(false):
                syncState = .noUpstream
            case .some(true):
                let ahead = summary.aheadCount ?? 0
                let behind = summary.behindCount ?? 0
                if ahead > 0 && behind > 0 {
                    syncState = .diverged(ahead: ahead, behind: behind)
                } else if ahead > 0 {
                    syncState = .ahead(ahead)
                } else if behind > 0 {
                    syncState = .behind(behind)
                } else if summary.aheadCount != nil || summary.behindCount != nil {
                    syncState = .synced
                } else {
                    syncState = .unknown
                }
            case .none:
                syncState = .unknown
            }
        } else {
            syncState = .unknown
        }
        return GitBranchStatus(
            isDirty: isDirty,
            syncState: syncState,
            prCount: pullRequestCount,
            linesAdded: summary?.linesAdded ?? 0,
            linesDeleted: summary?.linesDeleted ?? 0
        )
    }

    static func sortedWorktrees(for repo: RepoPresentationItem) -> [Worktree] {
        repo.worktrees.sorted { lhs, rhs in
            if lhs.isMainWorktree != rhs.isMainWorktree {
                return lhs.isMainWorktree
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
