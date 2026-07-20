import AppKit
import Foundation
import SwiftUI

private enum RepoSidebarToolbarTooltipTarget: Hashable {
    case sort
    case grouping
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
    let initialProjectionTrigger: AppPolicies.SidebarProjection.Trigger
    let initialProjectionSequence: Int
    let onInitialProjectionApplied: @MainActor (Int) -> Void
    static let groupHeaderChromePolicy = SidebarRepoGroupHeader<EmptyView>.chromePolicy
    static let headerLayoutPolicy = SidebarHeaderLayout<EmptyView, EmptyView, EmptyView, EmptyView>.policy
    static let tooltipCoordinateSpaceName = "repoSidebarHeaderTooltips"

    init(
        store: WorkspaceStore,
        onRefocusActivePane: @escaping () -> Void,
        onSidebarVisibleWorktreesChanged: @escaping @MainActor @Sendable () -> Void,
        onShowNotificationsForWorktree: @escaping (Worktree) -> Void,
        unreadCount: @escaping (Worktree) -> Int,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder? = nil,
        initialProjectionTrigger: String = AppPolicies.SidebarProjection.Trigger.startupDiagnostic.rawValue,
        initialProjectionSequence: Int = 0,
        onInitialProjectionApplied: @escaping @MainActor (Int) -> Void = { _ in }
    ) {
        self.store = store
        self.onRefocusActivePane = onRefocusActivePane
        self.onSidebarVisibleWorktreesChanged = onSidebarVisibleWorktreesChanged
        self.onShowNotificationsForWorktree = onShowNotificationsForWorktree
        self.unreadCount = unreadCount
        self.performanceTraceRecorder = performanceTraceRecorder
        self.initialProjectionTrigger =
            AppPolicies.SidebarProjection.Trigger(rawValue: initialProjectionTrigger) ?? .startupDiagnostic
        self.initialProjectionSequence = initialProjectionSequence
        self.onInitialProjectionApplied = onInitialProjectionApplied
    }

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
    @State private var hasReportedInitialProjection = false
    @State private var hoveredTooltipTarget: RepoSidebarToolbarTooltipTarget?
    @State private var tooltipFrames: [RepoSidebarToolbarTooltipTarget: CGRect] = [:]
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
            visibilityMode: repoExplorerPrefs.repoVisibilityMode,
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
            trigger: initialProjectionTrigger,
            worktreeFactsByWorktreeId: sidebarWorktreeFactsByWorktreeId
        )
    }

    private var sidebarWorktreeFactsByWorktreeId: [UUID: RepoWorktreeCacheFacts] {
        let sidebarWorktreeIds = Set(sidebarRepos.flatMap(\.worktrees).map(\.id))
        return repoCache.worktreeFactsSnapshot().filter { sidebarWorktreeIds.contains($0.key) }
    }

    var body: some View {
        VStack(spacing: 0) {
            RepoExplorerFocusBridge(
                uiState: uiState
            )
            .frame(width: 1, height: 1)
            .opacity(0.001)

            filterBar

            if currentProjection.emptyState != .content {
                RepoExplorerEmptyStateView(emptyState: currentProjection.emptyState)
                    .onAppear {
                        updateSidebarVisibleWorktrees([])
                    }
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
        .coordinateSpace(name: Self.tooltipCoordinateSpaceName)
        .onPreferenceChange(HoverTooltipAnchorPreferenceKey<RepoSidebarToolbarTooltipTarget>.self) {
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
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var repoToolbarRow: some View {
        let sortAction = AppCommand.setRepoSidebarSortOrder.definition
        let groupingAction = LocalActionSpec.groupRepoExplorerWorktrees.actionSpec
        let isFavoritesOnly = repoExplorerPrefs.repoVisibilityMode == .favoritesOnly
        return HStack(spacing: AppStyles.General.Spacing.standard) {
            Spacer(minLength: 0)

            RepoExplorerVisibilityButton(isFavoritesOnly: isFavoritesOnly) {
                AppCommandDispatcher.shared.dispatch(
                    AppCommandExecutionRequest(
                        command: .setRepoSidebarVisibilityMode,
                        arguments: .repoSidebarVisibilityMode(isFavoritesOnly ? .all : .favoritesOnly)
                    )
                )
            }

            SidebarToolbarSortButton(
                sortValue: repoExplorerPrefs.sortOrder,
                isReversed: repoExplorerPrefs.sortOrder == .descending,
                label: sortAction.label,
                accessibilityIdentifier: "repoSidebarSortButton",
                tooltipValue: sortAction.controlTooltipRenderValue(
                    textOverride: "Sort \(repoExplorerPrefs.sortOrder.title.lowercased())"
                ),
                icon: {
                    sortAction.icon.swiftUIImage(size: AppStyles.General.Icon.compact)
                },
                tooltipTarget: RepoSidebarToolbarTooltipTarget.sort,
                tooltipCoordinateSpaceName: Self.tooltipCoordinateSpaceName,
                frameAccessibilityIdentifier: "repoSidebarSortButtonFrame",
                onHover: { updateTooltipTarget(.sort, isHovered: $0) },
                onToggle: {
                    AppCommandDispatcher.shared.dispatch(
                        AppCommandExecutionRequest(
                            command: .setRepoSidebarSortOrder,
                            arguments: .repoSidebarSortOrder(repoExplorerPrefs.sortOrder.toggled)
                        )
                    )
                }
            )

            SidebarToolbarDivider()

            SidebarToolbarGroupingButton(
                label: groupingAction.label,
                selectionLabel: repoExplorerPrefs.groupingMode.title,
                accessibilityIdentifier: "repoSidebarGroupingButton",
                tooltipValue: groupingAction.controlTooltipRenderValue(
                    provenance: .localAction(rawValue: "groupRepoExplorerWorktrees"),
                    textOverride: "Group"
                ),
                isOpen: groupingMenuOpen,
                tooltipTarget: RepoSidebarToolbarTooltipTarget.grouping,
                tooltipCoordinateSpaceName: Self.tooltipCoordinateSpaceName,
                frameAccessibilityIdentifier: "repoSidebarGroupingButtonFrame",
                onHover: { updateTooltipTarget(.grouping, isHovered: $0) },
                action: {
                    groupingMenuOpen.toggle()
                }
            )
            .popover(isPresented: $groupingMenuOpen) {
                SidebarGroupingPopover(
                    items: RepoExplorerGroupingMode.allCases,
                    selectedItem: repoExplorerPrefs.groupingMode,
                    icon: { groupingMode in
                        groupingMode.icon.swiftUIImage(size: AppStyles.General.Icon.compact)
                    },
                    label: \.title,
                    onSelect: { candidate in
                        AppCommandDispatcher.shared.dispatch(groupingCommand(for: candidate))
                        groupingMenuOpen = false
                    },
                    onDismiss: { groupingMenuOpen = false }
                )
            }
        }
        .background(
            AccessibilityLabelBridge(
                identifier: "repoSidebarToolbarRow",
                label: "Repo toolbar row"
            )
        )
    }

    private func groupingCommand(for mode: RepoExplorerGroupingMode) -> AppCommand {
        switch mode {
        case .repo: .setRepoSidebarGroupingRepo
        case .pane: .setRepoSidebarGroupingPane
        case .tab: .setRepoSidebarGroupingTab
        }
    }

    private var activeTooltipTarget: RepoSidebarToolbarTooltipTarget? {
        groupingMenuOpen ? nil : hoveredTooltipTarget
    }

    private func updateTooltipTarget(_ target: RepoSidebarToolbarTooltipTarget, isHovered: Bool) {
        withAnimation(.easeInOut(duration: AppStyles.General.Animation.fast)) {
            hoveredTooltipTarget = isHovered ? target : nil
        }
    }

    private func tooltipValue(for target: RepoSidebarToolbarTooltipTarget) -> ControlTooltipRenderValue? {
        switch target {
        case .sort:
            let sortAction = AppCommand.setRepoSidebarSortOrder.definition
            return sortAction.controlTooltipRenderValue(
                textOverride: "Sort \(repoExplorerPrefs.sortOrder.title.lowercased())"
            )
        case .grouping:
            return LocalActionSpec.groupRepoExplorerWorktrees.actionSpec.controlTooltipRenderValue(
                provenance: .localAction(rawValue: "groupRepoExplorerWorktrees"),
                textOverride: "Group"
            )
        }
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
                            branchName: cachedProjectionResult.branchNameByWorktreeId[
                                resolvedWorktreeContext.worktree.id
                            ] ?? "detached HEAD",
                            placementText: resolvedWorktreeContext.placementContext?.displayText ?? "",
                            checkoutIconKind: checkoutIconKind(
                                for: resolvedWorktreeContext.worktree,
                                in: resolvedWorktreeContext.repo
                            ),
                            iconColor: colorForCheckout(hex: resolvedWorktreeContext.checkoutColorHex),
                            branchStatus: cachedProjectionResult.branchStatusByWorktreeId[
                                resolvedWorktreeContext.worktree.id
                            ] ?? .unknown,
                            unreadCount: unreadCount(resolvedWorktreeContext.worktree),
                            bridgeCommandResolution: AppCommandDispatcher.shared
                                .bridgePaneCommandTarget(
                                    worktreeId: resolvedWorktreeContext.worktree.id
                                )?.resolution ?? .create,
                            isFavorite: currentRepoFavoriteState(
                                repoId: resolvedWorktreeContext.repo.id,
                                projectedFallback: resolvedWorktreeContext.repo.isFavorite
                            ),
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

                case .topologyFault(let fault):
                    RepoExplorerTopologyFaultRow(fault: fault)
                        .listRowInsets(
                            EdgeInsets(
                                top: AppStyles.General.Spacing.standard,
                                leading: AppStyles.Shell.Sidebar.groupChildRowLeadingInset,
                                bottom: AppStyles.General.Spacing.standard,
                                trailing: AppStyles.General.Spacing.standard
                            )
                        )
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
        .scrollContentBackground(.hidden)
        .background(Self.surfaceBackground.color)
        .background(
            RepoExplorerVisibleRowsBridge(
                entries: rowIndex.entries,
                onVisibleWorktreeIdsChange: updateSidebarVisibleWorktrees
            )
        )
        .transition(
            .opacity.animation(.easeInOut(duration: AppStyles.General.Animation.standard))
        )
    }

    private func colorForCheckout(hex colorHex: String) -> Color {
        Color(nsColor: NSColor(hex: colorHex) ?? .controlAccentColor)
    }

    private func iconForGroup(_ group: RepoPresentationGroup) -> AppEntityIcon {
        Self.groupIcon(
            for: group,
            projectionGroupingMode: cachedProjectionResult.snapshot.groupingMode
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
        AppCommandDispatcher.shared.dispatch(
            repo.isFavorite ? .removeRepoFavorite : .addRepoFavorite,
            target: repoId,
            targetType: .repo
        )
    }

    private func currentRepoFavoriteState(repoId: UUID, projectedFallback: Bool) -> Bool {
        store.repositoryTopologyAtom.repo(repoId)?.isFavorite ?? projectedFallback
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
        let worktreeFactsByWorktreeId: [UUID: RepoWorktreeCacheFacts]
    }

    private var projectionRequestKey: ProjectionRequestKey {
        let request = projectionRequest
        return ProjectionRequestKey(
            snapshot: request.snapshot,
            expandedGroupIds: request.expandedGroupIds,
            isFiltering: request.isFiltering,
            worktreeFactsByWorktreeId: request.worktreeFactsByWorktreeId
        )
    }

    private func refreshProjection(
        force: Bool = false,
        trigger: AppPolicies.SidebarProjection.Trigger? = nil
    ) {
        let clock = ContinuousClock()
        let requestBuildStart = clock.now
        let request = projectionRequest
        let requestKey = ProjectionRequestKey(
            snapshot: request.snapshot,
            expandedGroupIds: request.expandedGroupIds,
            isFiltering: request.isFiltering,
            worktreeFactsByWorktreeId: request.worktreeFactsByWorktreeId
        )
        if !force,
            let cachedProjectionRequest,
            ProjectionRequestKey(
                snapshot: cachedProjectionRequest.snapshot,
                expandedGroupIds: cachedProjectionRequest.expandedGroupIds,
                isFiltering: cachedProjectionRequest.isFiltering,
                worktreeFactsByWorktreeId: cachedProjectionRequest.worktreeFactsByWorktreeId
            ) == requestKey
        {
            return
        }

        if projectionTask != nil, let cancelledRequest = cachedProjectionRequest {
            performanceTraceRecorder?.record(
                .sidebarProjection,
                attributes: sidebarProjectionTraceAttributes(
                    for: cancelledRequest,
                    phase: "projection_worker",
                    extra: ["agentstudio.performance.sidebar.cancellation.count": .int(1)]
                )
            )
        }

        projectionGeneration += 1
        let projectionTrigger =
            trigger
            ?? Self.sidebarProjectionTrigger(
                previous: cachedProjectionRequest,
                next: request,
                initialProjectionTrigger: initialProjectionTrigger
            )
        let generatedRequest = RepoExplorerProjectionRequest(
            generation: projectionGeneration,
            snapshot: request.snapshot,
            expandedGroupIds: request.expandedGroupIds,
            isFiltering: request.isFiltering,
            trigger: projectionTrigger,
            worktreeFactsByWorktreeId: request.worktreeFactsByWorktreeId
        )
        let requestBuildDuration = requestBuildStart.duration(to: clock.now)
        performanceTraceRecorder?.recordDuration(
            .sidebarProjection,
            duration: requestBuildDuration,
            attributes: sidebarProjectionTraceAttributes(
                for: generatedRequest,
                phase: "request_build_mainactor",
                extra: [
                    "agentstudio.performance.sidebar.request_build_mainactor_elapsed_ms": .double(
                        AgentStudioPerformanceTraceRecorder.milliseconds(from: requestBuildDuration))
                ]
            )
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
                failProjectionIfCurrent(generation: generatedRequest.generation)
            }
        }
    }

    private func clearProjectionTaskIfCurrent(generation: Int) {
        guard generation == projectionGeneration else { return }
        projectionTask = nil
    }

    private func failProjectionIfCurrent(generation: Int) {
        guard generation == projectionGeneration else { return }
        cachedProjectionRequest = nil
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
        if Self.shouldReportInitialProjection(
            hasReportedInitialProjection: hasReportedInitialProjection
        ) {
            hasReportedInitialProjection = true
            onInitialProjectionApplied(initialProjectionSequence)
        }
    }

    private func sidebarProjectionTraceAttributes(
        for request: RepoExplorerProjectionRequest,
        phase: String,
        extra: [String: AgentStudioTraceValue] = [:]
    ) -> [String: AgentStudioTraceValue] {
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.performance.sidebar.surface": .string("repo"),
            "agentstudio.performance.sidebar.phase": .string(phase),
            "agentstudio.performance.sidebar.trigger": .string(request.trigger.rawValue),
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

}

private struct RepoExplorerTopologyFaultRow: View {
    let fault: RepoExplorerTopologyFault

    var body: some View {
        HStack(alignment: .top, spacing: AppStyles.General.Spacing.standard) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: AppStyles.General.Spacing.tight) {
                Text("Repository data unavailable")
                    .font(.system(size: AppStyles.General.Typography.textBase, weight: .semibold))
                Text(
                    "Detected \(fault.duplicateIdentityCount) duplicate worktree identity claim(s). Refresh repositories to recover."
                )
                .font(.system(size: AppStyles.General.Typography.textSm))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .allowsHitTesting(false)
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
