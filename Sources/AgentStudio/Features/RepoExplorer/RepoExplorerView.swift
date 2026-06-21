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

/// Sidebar content grouped by repository identity (worktree family / remote).
@MainActor
struct RepoExplorerView: View {
    typealias SidebarProjection = RepoExplorerSidebarProjection

    let store: WorkspaceStore
    let onRefocusActivePane: () -> Void
    let onShowNotificationsForWorktree: (Worktree) -> Void
    let unreadCount: (Worktree) -> Int
    let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    static let focusTargetIdentifier = NSUserInterfaceItemIdentifier("repoExplorerFocusTarget")
    static let surfaceListPolicy = SidebarSurfaceListPolicy.nativeSidebarList
    static let groupHeaderChromePolicy = SidebarRepoGroupHeader<EmptyView>.chromePolicy
    static let headerLayoutPolicy = SidebarHeaderLayout<EmptyView, EmptyView, EmptyView, EmptyView>.policy

    private var repoCache: RepoCacheAtom {
        atom(\.repoCache)
    }

    private var uiState: WorkspaceSidebarState {
        atom(\.workspaceSidebarState)
    }

    private var sidebarCache: SidebarCacheState {
        atom(\.sidebarCache)
    }

    private var repoExplorerPrefs: RepoExplorerSidebarPrefsAtom {
        atom(\.repoExplorerSidebarPrefs)
    }

    @State private var filterText: String = ""
    @State private var debouncedQuery: String = ""
    @State private var groupingMenuOpen = false
    @FocusState private var focusedField: RepoExplorerFocus?

    @State private var debounceTask: Task<Void, Never>?
    @State private var projectionWorker = RepoExplorerProjectionWorker()
    @State private var projectionTask: Task<Void, Never>?
    @State private var projectionGeneration = 0
    @State private var cachedProjectionResult = RepoExplorerProjectionResult.empty
    @State private var cachedProjectionRequest: RepoExplorerProjectionRequest?

    private static let filterDebounceMilliseconds = 25

    private var sidebarRepos: [RepoPresentationItem] {
        store.repositoryTopologyAtom.repos.map(RepoPresentationItem.init(repo:))
    }

    private var sidebarSnapshot: RepoExplorerSnapshot {
        RepoExplorerSnapshot(
            repos: sidebarRepos,
            repoEnrichmentByRepoId: sidebarRepoEnrichmentByRepoId,
            groupingMode: repoExplorerPrefs.groupingMode,
            sortOrder: repoExplorerPrefs.sortOrder,
            query: debouncedQuery,
            paneLocationsByWorktreeId: atom(\.workspaceLookup).paneLocationsByWorktreeId(
                workspacePane: store.paneAtom,
                workspaceTab: WorkspaceTabLayoutDerived(
                    shellAtom: store.tabShellAtom,
                    arrangementAtom: store.tabArrangementAtom
                )
            )
        )
    }

    private var sidebarRepoEnrichmentByRepoId: [UUID: RepoEnrichment] {
        Dictionary(
            uniqueKeysWithValues: sidebarRepos.compactMap { repo in
                repoCache.repoEnrichment(for: repo.id).map { (repo.id, $0) }
            }
        )
    }

    private var isFiltering: Bool {
        !debouncedQuery.isEmpty
    }

    private var currentProjection: SidebarProjection {
        cachedProjectionResult.projection
    }

    private var currentRowIndex: RepoExplorerRowIndex {
        cachedProjectionResult.rowIndex
    }

    private var projectionRequest: RepoExplorerProjectionRequest {
        RepoExplorerProjectionRequest(
            generation: projectionGeneration + 1,
            snapshot: sidebarSnapshot,
            expandedGroupIds: Set(sidebarCache.expandedGroups.map(\.rawValue)),
            isFiltering: isFiltering,
            trigger: "startup_diagnostic"
        )
    }

    private var worktreeStatusById: [UUID: GitBranchStatus] {
        let factsByWorktreeId = Dictionary(
            uniqueKeysWithValues: sidebarRepos.flatMap(\.worktrees).compactMap { worktree in
                repoCache.worktreeFacts(for: worktree.id).map { (worktree.id, $0) }
            }
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

            if currentProjection.showsNoResults {
                noResultsView
            } else {
                groupList
            }
        }
        .animation(.easeOut(duration: 0.15), value: uiState.isFilterVisible)
        .task {
            filterText = uiState.filterText
            debouncedQuery = uiState.filterText
            refreshProjection(force: true)
        }
        .onDisappear {
            debounceTask?.cancel()
            projectionTask?.cancel()
            projectionTask = nil
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
        .onChange(of: projectionRequestKey) { _, _ in
            refreshProjection()
        }
    }

    private var filterBar: some View {
        SidebarHeaderLayout {
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
        } toolbarRow: {
            repoToolbarRow
        } statusRow: {
            EmptyView()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var repoToolbarRow: some View {
        let sortAction = LocalActionSpec.repoSidebarCurrentOrder.actionSpec
        let groupingAction = LocalActionSpec.groupRepoExplorerWorktrees.actionSpec
        return HStack(spacing: AppStyles.General.Spacing.standard) {
            Spacer(minLength: 0)

            Button {
                repoExplorerPrefs.toggleSortOrder()
            } label: {
                toolbarIcon(sortAction.icon)
                    .rotationEffect(.degrees(repoExplorerPrefs.sortOrder == .ascending ? 0 : 180))
                    .animation(.easeInOut(duration: 0.18), value: repoExplorerPrefs.sortOrder)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(sortAction.label)
            .accessibilityIdentifier("repoSidebarSortButton")
            .controlHelp(
                sortAction.controlTooltipRenderValue(
                    provenance: .localAction(rawValue: "repoSidebarCurrentOrder"),
                    textOverride: "Sort \(repoExplorerPrefs.sortOrder.title.lowercased())"
                )
            )

            Button {
                groupingMenuOpen.toggle()
            } label: {
                toolbarIcon(repoExplorerPrefs.groupingMode.icon)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(groupingAction.label)
            .accessibilityIdentifier("repoSidebarGroupingButton")
            .controlHelp(
                groupingAction.controlTooltipRenderValue(
                    provenance: .localAction(rawValue: "groupRepoExplorerWorktrees"),
                    textOverride: "Group"
                )
            )
            .popover(isPresented: $groupingMenuOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(RepoExplorerGroupingMode.allCases, id: \.self) { candidate in
                        Button {
                            repoExplorerPrefs.setGroupingMode(candidate)
                            groupingMenuOpen = false
                        } label: {
                            HStack {
                                Image(systemName: repoExplorerPrefs.groupingMode == candidate ? "checkmark" : "")
                                    .frame(width: 12)
                                candidate.icon.swiftUIImage(size: AppStyles.General.Icon.compact)
                                    .frame(width: AppStyles.General.Icon.compact)
                                Text(candidate.title)
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
                identifier: "repoSidebarToolbarRow",
                label: "Repo toolbar row"
            )
        )
    }

    private func toolbarIcon(_ icon: CommandIcon) -> some View {
        icon.swiftUIImage(size: AppStyles.General.Icon.compact)
            .frame(
                width: AppStyles.General.Button.compact,
                height: AppStyles.General.Button.compact
            )
            .foregroundStyle(Color.secondary)
            .contentShape(Rectangle())
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
        let rowIndex = currentRowIndex
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

                case .resolvedWorktreeRow(let groupId, let repoId, let worktreeId, let rowId):
                    if let resolvedWorktreeContext = rowIndex.resolve(
                        groupId: groupId,
                        repoId: repoId,
                        worktreeId: worktreeId,
                        rowId: rowId
                    ) {
                        RepoExplorerWorktreeRow(
                            worktree: resolvedWorktreeContext.worktree,
                            checkoutTitle: checkoutTitle(
                                for: resolvedWorktreeContext.worktree,
                                in: resolvedWorktreeContext.repo
                            ),
                            branchName: branchName(for: resolvedWorktreeContext.worktree),
                            placementText: resolvedWorktreeContext.placementContext?.displayText ?? "",
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
                            isFavorite: resolvedWorktreeContext.repo.isFavorite,
                            onToggleFavorite: {
                                toggleFavorite(repoId: resolvedWorktreeContext.repo.id)
                            },
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
        .transition(.opacity.animation(.easeOut(duration: 0.12)))
    }

    private func colorForCheckout(repo: RepoPresentationItem, in group: RepoPresentationGroup) -> Color {
        let colorHex = RepoPresentationColoring.checkoutColorHex(
            for: repo, in: group
        )
        return Color(nsColor: NSColor(hex: colorHex) ?? .controlAccentColor)
    }

    private func iconForGroup(_ group: RepoPresentationGroup) -> AppEntityIcon {
        Self.sourceGroupIcon(
            for: group,
            groupingMode: repoExplorerPrefs.groupingMode
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

    private func toggleFavorite(repoId: UUID) {
        guard let repo = store.repositoryTopologyAtom.repo(repoId) else { return }
        store.repositoryTopologyAtom.setRepoFavorite(repoId, isFavorite: !repo.isFavorite)
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

    private struct ProjectionRequestKey: Equatable {
        let snapshot: RepoExplorerSnapshot
        let expandedGroupIds: Set<String>
        let isFiltering: Bool
    }

    private var projectionRequestKey: ProjectionRequestKey {
        let request = projectionRequest
        return ProjectionRequestKey(
            snapshot: request.snapshot,
            expandedGroupIds: request.expandedGroupIds,
            isFiltering: request.isFiltering
        )
    }

    private func refreshProjection(force: Bool = false) {
        let request = projectionRequest
        let requestKey = ProjectionRequestKey(
            snapshot: request.snapshot,
            expandedGroupIds: request.expandedGroupIds,
            isFiltering: request.isFiltering
        )
        if !force,
            let cachedProjectionRequest,
            ProjectionRequestKey(
                snapshot: cachedProjectionRequest.snapshot,
                expandedGroupIds: cachedProjectionRequest.expandedGroupIds,
                isFiltering: cachedProjectionRequest.isFiltering
            ) == requestKey
        {
            return
        }

        if projectionTask != nil {
            performanceTraceRecorder?.record(
                .sidebarProjection,
                attributes: sidebarProjectionTraceAttributes(
                    for: request,
                    phase: "projection_worker",
                    extra: ["agentstudio.performance.sidebar.cancellation.count": .int(1)]
                )
            )
        }

        projectionGeneration += 1
        let projectionTrigger = sidebarProjectionTrigger(previous: cachedProjectionRequest, next: request)
        let generatedRequest = RepoExplorerProjectionRequest(
            generation: projectionGeneration,
            snapshot: request.snapshot,
            expandedGroupIds: request.expandedGroupIds,
            isFiltering: request.isFiltering,
            trigger: projectionTrigger
        )
        cachedProjectionRequest = generatedRequest
        projectionTask?.cancel()
        let worker = projectionWorker
        projectionTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            do {
                let result = try await worker.project(generatedRequest)
                guard !Task.isCancelled else { return }
                applyProjectionResult(result)
            } catch is CancellationError {
                clearProjectionTaskIfCurrent(generation: generatedRequest.generation)
            } catch {
                clearProjectionTaskIfCurrent(generation: generatedRequest.generation)
            }
        }
    }

    private func clearProjectionTaskIfCurrent(generation: Int) {
        guard generation == projectionGeneration else { return }
        projectionTask = nil
    }

    private func applyProjectionResult(_ result: RepoExplorerProjectionResult) {
        guard
            result.generation == projectionGeneration,
            result.snapshot == cachedProjectionRequest?.snapshot,
            result.expandedGroupIds == cachedProjectionRequest?.expandedGroupIds,
            result.isFiltering == cachedProjectionRequest?.isFiltering
        else {
            performanceTraceRecorder?.record(
                .sidebarProjection,
                attributes: sidebarProjectionTraceAttributes(
                    for: RepoExplorerProjectionRequest(
                        generation: result.generation,
                        snapshot: result.snapshot,
                        expandedGroupIds: result.expandedGroupIds,
                        isFiltering: result.isFiltering,
                        trigger: result.trigger
                    ),
                    phase: "mainactor_apply",
                    extra: ["agentstudio.performance.sidebar.stale_discard.count": .int(1)]
                )
            )
            return
        }

        performanceTraceRecorder?.recordDuration(
            .sidebarProjection,
            duration: result.projectionDuration,
            attributes: sidebarProjectionTraceAttributes(
                for: RepoExplorerProjectionRequest(
                    generation: result.generation,
                    snapshot: result.snapshot,
                    expandedGroupIds: result.expandedGroupIds,
                    isFiltering: result.isFiltering,
                    trigger: result.trigger
                ),
                phase: "projection_worker",
                extra: [
                    "agentstudio.performance.sidebar.total_worker_elapsed_ms": .double(
                        AgentStudioPerformanceTraceRecorder.milliseconds(from: result.workerDuration)),
                    "agentstudio.performance.sidebar.group.count": .int(result.projection.resolvedGroups.count),
                    "agentstudio.performance.sidebar.loading_repo.count": .int(result.projection.loadingRepos.count),
                ]
            )
        )
        performanceTraceRecorder?.recordDuration(
            .sidebarRowIndex,
            duration: result.rowIndexDuration,
            attributes: sidebarProjectionTraceAttributes(
                for: RepoExplorerProjectionRequest(
                    generation: result.generation,
                    snapshot: result.snapshot,
                    expandedGroupIds: result.expandedGroupIds,
                    isFiltering: result.isFiltering,
                    trigger: result.trigger
                ),
                phase: "row_index",
                extra: [
                    "agentstudio.performance.sidebar.row_index_elapsed_ms": .double(
                        AgentStudioPerformanceTraceRecorder.milliseconds(from: result.rowIndexDuration))
                ]
            )
        )

        let clock = ContinuousClock()
        let applyStart = clock.now
        cachedProjectionResult = result
        projectionTask = nil
        let applyDuration = applyStart.duration(to: clock.now)
        performanceTraceRecorder?.recordDuration(
            .sidebarProjection,
            duration: applyDuration,
            attributes: sidebarProjectionTraceAttributes(
                for: RepoExplorerProjectionRequest(
                    generation: result.generation,
                    snapshot: result.snapshot,
                    expandedGroupIds: result.expandedGroupIds,
                    isFiltering: result.isFiltering,
                    trigger: result.trigger
                ),
                phase: "mainactor_apply",
                extra: [
                    "agentstudio.performance.sidebar.mainactor_apply_elapsed_ms": .double(
                        AgentStudioPerformanceTraceRecorder.milliseconds(from: applyDuration)),
                    "agentstudio.performance.sidebar.group.count": .int(result.projection.resolvedGroups.count),
                    "agentstudio.performance.sidebar.loading_repo.count": .int(result.projection.loadingRepos.count),
                ]
            )
        )
    }

    private func sidebarProjectionTraceAttributes(
        for request: RepoExplorerProjectionRequest,
        phase: String,
        extra: [String: AgentStudioTraceValue] = [:]
    ) -> [String: AgentStudioTraceValue] {
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.performance.sidebar.surface": .string("repo"),
            "agentstudio.performance.sidebar.phase": .string(phase),
            "agentstudio.performance.sidebar.trigger": .string(request.trigger),
            "agentstudio.performance.sidebar.query_state": .string(
                request.snapshot.query.isEmpty ? "empty" : "non_empty"),
            "agentstudio.performance.sidebar.group_mode": .string(request.snapshot.groupingMode.rawValue),
            "agentstudio.performance.sidebar.sort_order": .string(request.snapshot.sortOrder.rawValue),
            "agentstudio.performance.sidebar.repo.count": .int(request.snapshot.repos.count),
            "agentstudio.performance.sidebar.query_character.count": .int(request.snapshot.query.count),
            "agentstudio.performance.sidebar.expanded_group.count": .int(request.expandedGroupIds.count),
            "agentstudio.performance.sidebar.is_filtering": .bool(request.isFiltering),
        ]
        attributes.merge(extra) { _, newValue in newValue }
        return attributes
    }

    private func sidebarProjectionTrigger(
        previous: RepoExplorerProjectionRequest?,
        next: RepoExplorerProjectionRequest
    ) -> String {
        guard let previous else {
            return next.snapshot.groupingMode == .repo ? "startup_diagnostic" : "grouping_switch"
        }
        if previous.snapshot.groupingMode != next.snapshot.groupingMode {
            return "grouping_switch"
        }
        if previous.snapshot.query != next.snapshot.query {
            return "search"
        }
        if previous.expandedGroupIds != next.expandedGroupIds {
            return "collapse_toggle"
        }
        return "surface_switch"
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
        for group: RepoPresentationGroup,
        groupingMode: RepoExplorerGroupingMode = .repo
    ) -> AppEntityIcon {
        switch groupingMode {
        case .pane:
            return .paneGroup
        case .tab:
            return .tabGroup
        case .repo:
            break
        }

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
        groupingMode: RepoExplorerGroupingMode = .repo,
        query: String
    ) -> SidebarProjection {
        RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: repos,
                repoEnrichmentByRepoId: repoEnrichmentByRepoId,
                groupingMode: groupingMode,
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
}
