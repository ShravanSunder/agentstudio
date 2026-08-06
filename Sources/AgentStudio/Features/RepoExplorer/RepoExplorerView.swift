import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import AppKit
import Foundation
import Observation
import SwiftUI

package typealias BridgeAttendanceSnapshot =
    @MainActor () -> [UUID: UInt64]

private enum RepoSidebarToolbarTooltipTarget: Hashable {
    case sort
    case grouping
}

/// Sidebar content grouped by repository identity (worktree family / remote).
@MainActor
package struct RepoExplorerView: View {
    typealias SidebarProjection = RepoExplorerSidebarProjection

    let store: WorkspaceStore
    let octiconLoader: OcticonLoader
    let repoExplorerPrefs: RepoExplorerSidebarPrefsAtom
    let bridgeAttendanceSnapshot: BridgeAttendanceSnapshot
    let commandDispatcher: any AppCommandDispatching
    let canSetVisibilityMode: ((RepoExplorerVisibilityMode) -> Bool)?
    let canSetSortOrder: ((RepoExplorerSortOrder) -> Bool)?
    let onSetVisibilityMode: (RepoExplorerVisibilityMode) -> Void
    let onSetSortOrder: (RepoExplorerSortOrder) -> Void
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

    package init(
        store: WorkspaceStore,
        octiconLoader: OcticonLoader,
        repoExplorerPrefs: RepoExplorerSidebarPrefsAtom,
        bridgeAttendanceSnapshot: @escaping BridgeAttendanceSnapshot,
        commandDispatcher: any AppCommandDispatching,
        canSetVisibilityMode: ((RepoExplorerVisibilityMode) -> Bool)? = nil,
        canSetSortOrder: ((RepoExplorerSortOrder) -> Bool)? = nil,
        onSetVisibilityMode: @escaping (RepoExplorerVisibilityMode) -> Void,
        onSetSortOrder: @escaping (RepoExplorerSortOrder) -> Void,
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
        self.octiconLoader = octiconLoader
        self.repoExplorerPrefs = repoExplorerPrefs
        self.bridgeAttendanceSnapshot = bridgeAttendanceSnapshot
        self.commandDispatcher = commandDispatcher
        self.canSetVisibilityMode = canSetVisibilityMode
        self.canSetSortOrder = canSetSortOrder
        self.onSetVisibilityMode = onSetVisibilityMode
        self.onSetSortOrder = onSetSortOrder
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
    @State private var projectionObservationID: UUID?

    private static let filterDebounceMilliseconds = 25

    private var sidebarRepos: [RepoPresentationItem] {
        store.repositoryTopologyAtom.repos.map(RepoPresentationItem.init(repo:))
    }

    private var sidebarSnapshot: RepoExplorerSnapshot {
        makeSidebarSnapshot(
            repos: sidebarRepos,
            repoEnrichmentByRepoId: sidebarRepoEnrichmentByRepoId,
            groupingMode: repoExplorerPrefs.groupingMode,
            sortOrder: repoExplorerPrefs.sortOrder,
            visibilityMode: repoExplorerPrefs.repoVisibilityMode,
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
            generation: 0,
            snapshot: sidebarSnapshot,
            collapsedGroupIds: Set(sidebarCache.collapsedGroups.map(\.rawValue)),
            isFiltering: isFiltering,
            trigger: initialProjectionTrigger,
            worktreeFactsByWorktreeId: sidebarWorktreeFactsByWorktreeId
        )
    }

    private var sidebarWorktreeFactsByWorktreeId: [UUID: RepoWorktreeCacheFacts] {
        let sidebarWorktreeIds = Set(sidebarRepos.flatMap(\.worktrees).map(\.id))
        return repoCache.worktreeFactsSnapshot().filter { sidebarWorktreeIds.contains($0.key) }
    }

    package var body: some View {
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
            startProjectionObservation()
        }
        .onDisappear {
            debounceTask?.cancel()
            projectionTask?.cancel()
            projectionTask = nil
            projectionObservationID = nil
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
        .onChange(of: debouncedQuery) { _, _ in
            let clock = ContinuousClock()
            let requestBuildStart = clock.now
            let request = projectionRequest
            refreshProjection(
                request: request,
                requestBuildDuration: requestBuildStart.duration(to: clock.now)
            )
        }
        .onChange(of: focusedField) { _, newValue in
            RepoExplorerFocusPublisher.publish(
                focusedField: newValue,
                into: uiState
            )
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
                    let semanticRepo = Self.semanticRepoForHeader(
                        group,
                        groupingMode: cachedProjectionResult.snapshot.groupingMode
                    )
                    SidebarRepoGroupHeader(
                        isCollapsed: !isGroupExpanded(group.id),
                        octiconLoader: octiconLoader,
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
                    .modifier(
                        RepoExplorerRepoHeaderContextMenuModifier(
                            repo: semanticRepo,
                            panePresentations: panePresentations(
                                semanticRepo.flatMap {
                                    currentProjection.paneDestinationsByRepoId[$0.id]
                                } ?? []
                            ),
                            onFocusPane: focusPane
                        )
                    )

                case .resolvedWorktreeRow(let groupId, let repoId, let worktreeId, let rowId):
                    if let resolvedWorktreeContext = rowIndex.resolve(
                        groupId: groupId,
                        repoId: repoId,
                        worktreeId: worktreeId,
                        rowId: rowId
                    ) {
                        let isFavorite = currentRepoFavoriteState(
                            repoId: resolvedWorktreeContext.repo.id,
                            projectedFallback: resolvedWorktreeContext.repo.isFavorite
                        )
                        let favoriteControlVisibility = RepoExplorerFavoriteControlVisibility(
                            isMainWorktree: resolvedWorktreeContext.worktree.isMainWorktree
                        )
                        let commandPresentation = RepoExplorerWorktreeCommandPresentation.resolve(
                            worktreeId: resolvedWorktreeContext.worktree.id,
                            repoId: resolvedWorktreeContext.repo.id,
                            isFavorite: isFavorite,
                            showsFavoriteControl: favoriteControlVisibility.showsInlineButton,
                            dispatcher: commandDispatcher
                        )
                        RepoExplorerWorktreeRow(
                            octiconLoader: octiconLoader,
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
                            bridgeCommandResolution: cachedProjectionResult.snapshot
                                .bridgeCommandResolutionByWorktreeId[
                                    resolvedWorktreeContext.worktree.id
                                ] ?? .create,
                            isFavorite: isFavorite,
                            commandPresentation: commandPresentation,
                            panePresentations: panePresentations(
                                currentProjection.paneDestinationsByWorktreeId[
                                    resolvedWorktreeContext.worktree.id
                                ] ?? []
                            ),
                            onToggleFavorite: {
                                toggleFavorite(repoId: resolvedWorktreeContext.repo.id)
                            },
                            onUnreadPillTap: {
                                onShowNotificationsForWorktree(resolvedWorktreeContext.worktree)
                            },
                            onOpen: {
                                commandDispatcher.dispatch(
                                    .openWorktree,
                                    target: resolvedWorktreeContext.worktree.id,
                                    targetType: .worktree
                                )
                            },
                            onOpenNew: {
                                commandDispatcher.dispatch(
                                    .openNewTerminalInTab,
                                    target: resolvedWorktreeContext.worktree.id,
                                    targetType: .worktree
                                )
                            },
                            onReview: {
                                commandDispatcher.dispatch(
                                    .showBridgeReview,
                                    target: resolvedWorktreeContext.worktree.id,
                                    targetType: .worktree
                                )
                            },
                            onOpenFiles: {
                                commandDispatcher.dispatch(
                                    .showBridgeFiles,
                                    target: resolvedWorktreeContext.worktree.id,
                                    targetType: .worktree
                                )
                            },
                            onOpenReviewInNewTab: {
                                commandDispatcher.dispatch(
                                    .openBridgeReviewInNewTab,
                                    target: resolvedWorktreeContext.worktree.id,
                                    targetType: .worktree
                                )
                            },
                            onOpenFilesInNewTab: {
                                commandDispatcher.dispatch(
                                    .openBridgeFilesInNewTab,
                                    target: resolvedWorktreeContext.worktree.id,
                                    targetType: .worktree
                                )
                            },
                            onOpenInPane: {
                                commandDispatcher.dispatch(
                                    .openWorktreeInPane,
                                    target: resolvedWorktreeContext.worktree.id,
                                    targetType: .worktree
                                )
                            },
                            onFocusPane: focusPane
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

                case .resolvedPaneRow(let groupId, let identity, let rowId):
                    if let resolvedPaneContext = rowIndex.resolvePane(
                        groupId: groupId,
                        repoId: identity.repoId,
                        paneId: identity.paneId,
                        rowId: rowId
                    ) {
                        RepoExplorerPaneRow(
                            label: panePresentation(for: resolvedPaneContext.destination).label,
                            onFocus: { focusPane(resolvedPaneContext.destination.paneId) }
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
        isFiltering || !sidebarCache.collapsedGroups.contains(SidebarGroupKey(groupId))
    }

    private func toggleGroupExpansion(_ groupId: String) {
        guard !isFiltering else { return }

        let key = SidebarGroupKey(groupId)
        sidebarCache.setGroupExpanded(key, isExpanded: sidebarCache.collapsedGroups.contains(key))
    }

    private func toggleFavorite(repoId: UUID) {
        guard let repo = store.repositoryTopologyAtom.repo(repoId) else { return }
        commandDispatcher.dispatch(
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

    private func startProjectionObservation() {
        let observationID = UUID()
        projectionObservationID = observationID
        observeProjectionInputs(observationID: observationID, force: true)
    }

    private func observeProjectionInputs(
        observationID: UUID,
        force: Bool = false
    ) {
        guard projectionObservationID == observationID else { return }

        let clock = ContinuousClock()
        let requestBuildStart = clock.now
        let request = withObservationTracking {
            projectionRequest
        } onChange: {
            Task { @MainActor in
                await Task.yield()
                guard projectionObservationID == observationID else { return }
                observeProjectionInputs(observationID: observationID)
            }
        }
        let requestBuildDuration = requestBuildStart.duration(to: clock.now)
        refreshProjection(
            request: request,
            requestBuildDuration: requestBuildDuration,
            force: force
        )
    }

    private func refreshProjection(
        request: RepoExplorerProjectionRequest,
        requestBuildDuration: Duration,
        force: Bool = false,
        trigger: AppPolicies.SidebarProjection.Trigger? = nil
    ) {
        let requestKey = Self.projectionRequestKey(for: request)
        if !force,
            let cachedProjectionRequest,
            Self.projectionRequestKey(for: cachedProjectionRequest) == requestKey
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
            collapsedGroupIds: request.collapsedGroupIds,
            isFiltering: request.isFiltering,
            trigger: projectionTrigger,
            worktreeFactsByWorktreeId: request.worktreeFactsByWorktreeId
        )
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
            result.collapsedGroupIds == cachedProjectionRequest?.collapsedGroupIds,
            result.isFiltering == cachedProjectionRequest?.isFiltering
        else {
            performanceTraceRecorder?.record(
                .sidebarProjection,
                attributes: sidebarProjectionTraceAttributes(
                    for: RepoExplorerProjectionRequest(
                        generation: result.generation,
                        snapshot: result.snapshot,
                        collapsedGroupIds: result.collapsedGroupIds,
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
                    collapsedGroupIds: result.collapsedGroupIds,
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
                    collapsedGroupIds: result.collapsedGroupIds,
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
                    collapsedGroupIds: result.collapsedGroupIds,
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

}

extension RepoExplorerView {
    private var currentCommandContext: CommandContext {
        let workspaceTab = WorkspaceTabLayoutDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )
        let focusedPane = atom(\.workspaceFocusedPane).resolve(
            workspaceTab: workspaceTab,
            workspacePane: store.paneAtom,
            requestedOwner: atom(\.workspaceFocusOwner).owner
        )
        return atom(\.commandContext).currentContext(
            workspaceTab: workspaceTab,
            workspacePane: store.paneAtom,
            focusedPane: focusedPane,
            workspacePanePresentation: store.panePresentationAtom
        )
    }

    @ViewBuilder
    private var repoToolbarRow: some View {
        let isFavoritesOnly = repoExplorerPrefs.repoVisibilityMode == .favoritesOnly
        let nextVisibilityMode: RepoExplorerVisibilityMode = isFavoritesOnly ? .all : .favoritesOnly
        let nextSortOrder = repoExplorerPrefs.sortOrder.toggled
        let commandPresentation = RepoExplorerToolbarCommandPresentation.resolve(
            commandContext: currentCommandContext,
            dispatcher: commandDispatcher,
            capabilityOverrides: Self.argumentCommandCapabilities(
                nextVisibilityMode: nextVisibilityMode,
                nextSortOrder: nextSortOrder,
                canSetVisibilityMode: canSetVisibilityMode,
                canSetSortOrder: canSetSortOrder
            )
        )
        let groupingAction = LocalActionSpec.groupRepoExplorerWorktrees.actionSpec
        let presentedGroupingModes = RepoExplorerGroupingMode.allCases.filter { groupingMode in
            commandPresentation.command(groupingCommand(for: groupingMode)) != nil
        }

        HStack(spacing: AppStyles.General.Spacing.standard) {
            Spacer(minLength: 0)

            if let visibilityCommand = commandPresentation.command(.setRepoSidebarVisibilityMode) {
                RepoExplorerVisibilityButton(
                    octiconLoader: octiconLoader,
                    isFavoritesOnly: isFavoritesOnly,
                    commandPresentation: visibilityCommand
                ) {
                    onSetVisibilityMode(nextVisibilityMode)
                }
            }

            if let sortCommand = commandPresentation.command(.setRepoSidebarSortOrder) {
                SidebarToolbarSortButton(
                    sortValue: repoExplorerPrefs.sortOrder,
                    isReversed: repoExplorerPrefs.sortOrder == .descending,
                    label: sortCommand.commandSpec.label,
                    accessibilityIdentifier: "repoSidebarSortButton",
                    tooltipValue: sortCommand.commandSpec.controlTooltipRenderValue(
                        textOverride: "Sort \(repoExplorerPrefs.sortOrder.title.lowercased())"
                    ),
                    icon: {
                        sortCommand.commandSpec.icon.swiftUIImage(
                            loader: octiconLoader,
                            size: AppStyles.General.Icon.compact
                        )
                    },
                    tooltipTarget: RepoSidebarToolbarTooltipTarget.sort,
                    tooltipCoordinateSpaceName: Self.tooltipCoordinateSpaceName,
                    frameAccessibilityIdentifier: "repoSidebarSortButtonFrame",
                    onHover: { updateTooltipTarget(.sort, isHovered: $0) },
                    onToggle: {
                        onSetSortOrder(nextSortOrder)
                    }
                )
                .disabled(!sortCommand.isEnabled)
            }

            if !presentedGroupingModes.isEmpty {
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
                    },
                )
                .disabled(
                    !presentedGroupingModes.contains { groupingMode in
                        commandPresentation.command(groupingCommand(for: groupingMode))?.isEnabled == true
                    }
                )
                .popover(isPresented: $groupingMenuOpen) {
                    SidebarGroupingPopover(
                        items: presentedGroupingModes,
                        selectedItem: repoExplorerPrefs.groupingMode,
                        icon: { groupingMode in
                            presentedGroupingCommand(
                                for: groupingMode,
                                in: commandPresentation
                            ).commandSpec.icon.swiftUIImage(
                                loader: octiconLoader,
                                size: AppStyles.General.Icon.compact
                            )
                        },
                        label: { groupingMode in
                            groupingMode.title
                        },
                        onSelect: { candidate in
                            let command = groupingCommand(for: candidate)
                            guard commandPresentation.command(command)?.isEnabled == true else {
                                return
                            }
                            commandDispatcher.dispatch(command)
                            groupingMenuOpen = false
                        },
                        onDismiss: { groupingMenuOpen = false }
                    )
                }
            }
        }
        .background(
            AccessibilityLabelBridge(
                identifier: "repoSidebarToolbarRow",
                label: "Repo toolbar row"
            )
        )
    }

}
