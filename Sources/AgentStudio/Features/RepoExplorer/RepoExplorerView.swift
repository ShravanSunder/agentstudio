import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import AppKit
import Foundation
import Observation
import SwiftUI

// The view remains one cohesive SwiftUI surface; its projection lifecycle and
// render helpers share private state that is not a reusable module boundary.
// swiftlint:disable file_length type_body_length

enum RepoExplorerOutlineApplyOutcome: String, Equatable, Sendable {
    case equal
    case changed
}

struct RepoExplorerOutlineApplyMeasurement: Equatable, Sendable {
    let duration: Duration
    let totalRowCount: Int
    let changedRowCount: Int
    let equalPublishCount: Int
    let outcome: RepoExplorerOutlineApplyOutcome
}

enum RepoExplorerRowKind: String, Equatable, Sendable {
    case sectionHeader = "section_header"
    case loadingSectionHeader = "loading_section_header"
    case loadingRepo = "loading_repo"
    case resolvedGroupHeader = "resolved_group_header"
    case resolvedWorktree = "resolved_worktree"
    case resolvedPane = "resolved_pane"
    case topologyFault = "topology_fault"
}

enum RepoExplorerRowBodyEvaluationOutcome: String, Equatable, Sendable {
    case success
    case failed
    case incomplete
}

struct RepoExplorerRowBodyEvaluationMeasurement<Content> {
    let content: Content
    let duration: Duration
    let rowKind: RepoExplorerRowKind
    let outcome: RepoExplorerRowBodyEvaluationOutcome
}
package typealias BridgeAttendanceSnapshot =
    @MainActor (UUID) -> UInt64?
package typealias LatestPaneMessageSnapshot =
    @MainActor (UUID) -> String?

private enum RepoSidebarToolbarTooltipTarget: Hashable {
    case sort
}

/// Sidebar content grouped by repository identity (worktree family / remote).
@MainActor
package struct RepoExplorerView: View {
    typealias SidebarProjection = RepoExplorerSidebarProjection

    let store: WorkspaceStore
    let octiconLoader: OcticonLoader
    let repoExplorerPrefs: RepoExplorerSidebarPrefsAtom
    let bridgeAttendanceSnapshot: BridgeAttendanceSnapshot
    let latestPaneMessageSnapshot: LatestPaneMessageSnapshot
    let commandDispatcher: any AppCommandDispatching
    let commandPresentationSnapshot: RepoExplorerCommandPresentationSnapshot
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
        commandPresentationSnapshot: RepoExplorerCommandPresentationSnapshot = .empty,
        onSetSortOrder: @escaping (RepoExplorerSortOrder) -> Void,
        onRefocusActivePane: @escaping () -> Void,
        onSidebarVisibleWorktreesChanged: @escaping @MainActor @Sendable () -> Void,
        onShowNotificationsForWorktree: @escaping (Worktree) -> Void,
        unreadCount: @escaping (Worktree) -> Int,
        latestPaneMessageSnapshot: @escaping LatestPaneMessageSnapshot = { _ in nil },
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
        self.commandPresentationSnapshot = commandPresentationSnapshot
        self.onSetSortOrder = onSetSortOrder
        self.onRefocusActivePane = onRefocusActivePane
        self.onSidebarVisibleWorktreesChanged = onSidebarVisibleWorktreesChanged
        self.onShowNotificationsForWorktree = onShowNotificationsForWorktree
        self.unreadCount = unreadCount
        self.latestPaneMessageSnapshot = latestPaneMessageSnapshot
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
    @State private var hasReportedInitialProjection = false
    @State private var hoveredTooltipTarget: RepoSidebarToolbarTooltipTarget?
    @State private var tooltipFrames: [RepoSidebarToolbarTooltipTarget: CGRect] = [:]
    @FocusState private var focusedField: RepoExplorerFocus?
    @State private var debounceTask: Task<Void, Never>?
    @State private var projectionAdapter = RepoExplorerProjectionAdapter()
    @State private var projectionGeneration = 0
    @State private var cachedProjectionResult = RepoExplorerProjectionResult.empty
    @State private var cachedProjectionRequest: RepoExplorerProjectionRequest?
    @State private var projectionObservationID: UUID?
    @State private var scrollInstrumentationState = RepoExplorerScrollInstrumentationState()
    @State private var paneRecencyDisplayReferenceDate = Date()
    private static let filterDebounceMilliseconds = 25

    private var sidebarRepos: [RepoPresentationItem] {
        store.repositoryTopologyAtom.repositoryIdsInOrder.compactMap { repositoryID in
            store.repositoryTopologyAtom.repo(repositoryID).map(RepoPresentationItem.init(repo:))
        }
    }

    private var sidebarSnapshot: RepoExplorerSnapshot {
        makeSidebarSnapshot(
            repos: sidebarRepos,
            repoEnrichmentByRepoId: sidebarRepoEnrichmentByRepoId,
            groupingMode: repoExplorerPrefs.groupingMode,
            sortOrder: repoExplorerPrefs.sortOrder,
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
        let worktreeEnrichmentSnapshot = sidebarWorktreeEnrichmentSnapshot
        return RepoExplorerProjectionRequest(
            generation: 0,
            snapshot: sidebarSnapshot,
            collapsedGroupIds: Set(sidebarCache.collapsedGroups.map(\.rawValue)),
            isFiltering: isFiltering,
            trigger: initialProjectionTrigger,
            worktreeEnrichmentSnapshot: worktreeEnrichmentSnapshot,
            pullRequestFactsSnapshot: Self.pullRequestFactsSnapshot(
                for: worktreeEnrichmentSnapshot,
                repoCache: repoCache
            ),
            paneRowFactsByPaneId: paneRowFactsByPaneId(now: paneRecencyDisplayReferenceDate),
            tabGroupFactsByTabId: tabGroupFactsByTabId()
        )
    }

    /// Reads only the keyed observation slots that can change the projection.
    /// The comparatively expensive immutable request is assembled after an
    /// observed slot has admitted a rebuild.
    private var projectionInputRevision: Int {
        let repositoryIDs = store.repositoryTopologyAtom.repositoryIdsInOrder
        var observedSlotCount = Self.observeRepoEnrichmentInputs(
            repositoryIDs: repositoryIDs,
            repoCache: repoCache
        )
        for repositoryID in repositoryIDs {
            guard let repository = store.repositoryTopologyAtom.repo(repositoryID) else { continue }
            for worktree in repository.worktrees {
                let enrichment = repoCache.worktreeEnrichment(for: worktree.id)
                if let enrichment,
                    let branchKey = RepoBranchKey(repoId: enrichment.repoId, branch: enrichment.branch)
                {
                    _ = repoCache.pullRequestFacts(for: branchKey)
                }
                observedSlotCount += 1
            }
        }

        _ = repoExplorerPrefs.groupingMode
        _ = repoExplorerPrefs.sortOrder
        _ = sidebarCache.collapsedGroups
        _ = atom(\.workspaceEntityRecency).recentEntities

        let workspaceTab = WorkspaceTabLayoutDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )
        let paneGraph = store.paneAtom.graphAtom
        for tab in workspaceTab.tabs {
            _ = store.tabLayoutAtom.tab(tab.id)
            for paneID in tab.allPaneIds {
                _ = paneGraph.paneStructuralFacts(paneID)
                _ = store.paneAtom.pane(paneID)
                _ = bridgeAttendanceSnapshot(paneID)
                _ = latestPaneMessageSnapshot(paneID)
                observedSlotCount += 1
            }
        }
        for paneID in paneGraph.paneIDs {
            _ = paneGraph.paneStructuralFacts(paneID)
            observedSlotCount += 1
        }
        return observedSlotCount
    }

    static func observeRepoEnrichmentInputs(
        repositoryIDs: [UUID],
        repoCache: RepoCacheAtom
    ) -> Int {
        for repositoryID in repositoryIDs {
            _ = repoCache.repoEnrichment(for: repositoryID)
        }
        return repositoryIDs.count
    }

    private var sidebarWorktreeEnrichmentSnapshot: [UUID: WorktreeEnrichment] {
        Self.worktreeEnrichmentSnapshot(
            for: sidebarRepos.flatMap(\.worktrees).map(\.id),
            repoCache: repoCache
        )
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
            while !Task.isCancelled {
                try? await Task.sleep(
                    nanoseconds: AppPolicies.SidebarProjection.paneRecencyDisplayCadence.nanosecondsForTaskSleep
                )
                guard !Task.isCancelled else { return }
                paneRecencyDisplayReferenceDate = Date()
                let clock = ContinuousClock()
                let requestBuildStart = clock.now
                let request = projectionRequest
                refreshProjection(
                    request: request,
                    requestBuildDuration: requestBuildStart.duration(to: clock.now)
                )
            }
        }
        .onDisappear {
            debounceTask?.cancel()
            projectionAdapter.stop()
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
        .onChange(of: projectionAdapter.publishedResult) { _, result in
            guard let result else { return }
            applyProjectionResult(result)
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
        hoveredTooltipTarget
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
        }
    }

    private var groupList: some View {
        let rowIndex = currentRowIndex
        return List {
            ForEach(rowIndex.entries) { entry in
                RepoExplorerRowBodyEvaluationProxy(
                    entry: entry,
                    scrollInstrumentationState: scrollInstrumentationState,
                    performanceTraceRecorder: performanceTraceRecorder
                ) {
                    switch entry {
                    case .sectionHeader(let kind):
                        sectionHeader(kind: kind)

                    case .loadingSectionHeader(let kind):
                        RepoExplorerLoadingSectionHeaderRow(
                            state: currentProjection.sections
                                .first(where: { $0.kind == kind })?
                                .loadingState(
                                    enrichmentByRepoId: cachedProjectionResult.snapshot.repoEnrichmentSnapshotByRepoId
                                ) ?? .scanning
                        )
                        .padding(.top, AppStyles.General.Spacing.standard)
                        .padding(.bottom, AppStyles.General.Spacing.tight)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)

                    case .loadingRepoRow(_, let repo):
                        RepoExplorerLoadingRepoRow(
                            repoName: repo.name,
                            isStatusUnavailable: {
                                if case .statusUnavailable = cachedProjectionResult.snapshot
                                    .repoEnrichmentSnapshotByRepoId[repo.id]
                                {
                                    return true
                                }
                                return false
                            }()
                        )
                        .listRowInsets(
                            EdgeInsets(
                                top: 0,
                                leading: AppStyles.Shell.Sidebar.groupChildRowLeadingInset,
                                bottom: 0,
                                trailing: AppStyles.General.Spacing.loose
                            )
                        )
                        .listRowBackground(Color.clear)
                        .allowsHitTesting(false)

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
                                snapshot: commandPresentationSnapshot
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
                                bridgeCommandResolution:
                                    cachedProjectionResult
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
                                row: resolvedPaneContext.row,
                                pullRequestCount: cachedProjectionResult.branchStatusByWorktreeId[
                                    resolvedPaneContext.destination.worktreeId
                                ]?.prCount,
                                octiconLoader: octiconLoader,
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
            }

        }
        .sidebarSurfaceListStyle(Self.surfaceListPolicy)
        .scrollContentBackground(.hidden)
        .background(Self.surfaceBackground.color)
        .background(
            RepoExplorerVisibleRowsBridge(
                entries: rowIndex.entries,
                scrollInstrumentationState: scrollInstrumentationState,
                performanceTraceRecorder: performanceTraceRecorder,
                onVisibleWorktreeIdsChange: updateSidebarVisibleWorktrees
            )
        )
        .transition(
            .opacity.animation(.easeInOut(duration: AppStyles.General.Animation.standard))
        )
    }

    private func sectionHeader(kind: RepoExplorerSidebarSectionKind) -> some View {
        SectionSubheadingLabel(kind.title)
            .padding(.leading, Self.sectionHeaderLeadingInset)
            .padding(.trailing, AppStyles.Components.SectionSubheading.horizontalPadding)
            .padding(.top, AppStyles.Components.SectionSubheading.topPadding)
            .padding(.bottom, AppStyles.Components.SectionSubheading.bottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(kind.title)
            .accessibilityIdentifier("repoSidebarSectionHeader.\(kind.rawValue)")
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
    }

    package static var sectionHeaderLeadingInset: CGFloat {
        AppStyles.Shell.Sidebar.listRowLeadingInset
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

        let inputRevision = withObservationTracking {
            projectionInputRevision
        } onChange: {
            Task { @MainActor in
                await Task.yield()
                guard projectionObservationID == observationID else { return }
                observeProjectionInputs(observationID: observationID)
            }
        }
        _ = inputRevision
        let clock = ContinuousClock()
        let requestBuildStart = clock.now
        let request = projectionRequest
        let requestBuildDuration = requestBuildStart.duration(to: clock.now)
        if !force {
            AtomPerformanceTelemetry.shared.recordRepoExplorerKeyedWake(
                stage: "capture_rebuild",
                outcome: "admitted"
            )
        }
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

        if !force, let previousRequest = cachedProjectionRequest,
            let scopedChange = request.scopedChange(from: previousRequest)
        {
            projectionGeneration += 1
            let generatedRequest = request.generated(
                generation: projectionGeneration,
                trigger: .dataRefresh
            )
            if let scopedResult = RepoExplorerProjectionWorker.applyScopedChange(
                scopedChange,
                request: generatedRequest,
                previous: cachedProjectionResult
            ) {
                AtomPerformanceTelemetry.shared.recordRepoExplorerKeyedWake(
                    stage: "affected_row",
                    outcome: "changed"
                )
                cachedProjectionRequest = generatedRequest
                applyProjectionResult(scopedResult)
                return
            }
        }

        if !force {
            let captureScope =
                cachedProjectionRequest.map {
                    request.hasMembershipChange(from: $0) ? "membership_path" : "whole_surface"
                } ?? "whole_surface"
            AtomPerformanceTelemetry.shared.recordRepoExplorerKeyedWake(
                stage: captureScope,
                outcome: "admitted"
            )
        }

        if projectionAdapter.materializedProjection?.hasUnsettledProjectionTasks == true,
            let cancelledRequest = cachedProjectionRequest
        {
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
        let generatedRequest = request.generated(
            generation: projectionGeneration,
            trigger: projectionTrigger
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
        projectionAdapter.admit(generatedRequest)
    }

    // Projection validation, telemetry, and the single state publication form
    // one ordered commit path; splitting them would obscure that ordering.
    // swiftlint:disable:next function_body_length
    private func applyProjectionResult(_ result: RepoExplorerProjectionResult) {
        guard
            result.generation == projectionGeneration,
            result.snapshot == cachedProjectionRequest?.snapshot,
            result.collapsedGroupIds == cachedProjectionRequest?.collapsedGroupIds,
            result.isFiltering == cachedProjectionRequest?.isFiltering
        else {
            AtomPerformanceTelemetry.shared.recordRepoExplorerKeyedWake(
                stage: "mainactor_apply",
                outcome: "superseded"
            )
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

        AtomPerformanceTelemetry.shared.recordRepoExplorerKeyedWake(
            stage: "mainactor_apply",
            outcome: "published"
        )
        if AtomPerformanceTelemetry.shared.isRepoExplorerKeyedWakeContextActive {
            let referenceProjection = RepoExplorerProjection.project(
                result.snapshot,
                paneRowFactsByPaneId: result.paneRowFactsByPaneId,
                tabGroupFactsByTabId: result.tabGroupFactsByTabId
            )
            AtomPerformanceTelemetry.shared.recordRepoExplorerKeyedWake(
                stage: "final_projection",
                outcome: referenceProjection == result.projection ? "reference_equal" : "reference_different"
            )
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
                    "agentstudio.performance.sidebar.loading_repo.count": .int(
                        result.projection.scanningRepoCount(
                            enrichmentByRepoId: result.snapshot.repoEnrichmentSnapshotByRepoId)),
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

        let previousRowIDs = currentRowIndex.entries.map(\.id)
        let nextRowIDs = result.rowIndex.entries.map(\.id)
        let outlineApplyMeasurement = Self.measureOutlineApplyProxy(
            previousRowIDs: previousRowIDs,
            nextRowIDs: nextRowIDs,
            apply: { cachedProjectionResult = result }
        )
        performanceTraceRecorder?.recordDuration(
            .sidebarProjection,
            duration: outlineApplyMeasurement.duration,
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
                        AgentStudioPerformanceTraceRecorder.milliseconds(
                            from: outlineApplyMeasurement.duration)),
                    "agentstudio.performance.sidebar.group.count": .int(result.projection.resolvedGroups.count),
                    "agentstudio.performance.sidebar.loading_repo.count": .int(
                        result.projection.scanningRepoCount(
                            enrichmentByRepoId: result.snapshot.repoEnrichmentSnapshotByRepoId)),
                ]
            )
        )
        recordOutlineApplyProxy(outlineApplyMeasurement)
        if Self.shouldReportInitialProjection(
            hasReportedInitialProjection: hasReportedInitialProjection
        ) {
            hasReportedInitialProjection = true
            onInitialProjectionApplied(initialProjectionSequence)
        }
    }

    private func recordOutlineApplyProxy(_ measurement: RepoExplorerOutlineApplyMeasurement) {
        performanceTraceRecorder?.recordDuration(
            .repoExplorerOutlineApplyProxy,
            duration: measurement.duration,
            attributes: [
                "agentstudio.performance.repo_explorer.outline_apply_proxy.outcome": .string(
                    measurement.outcome.rawValue),
                "agentstudio.performance.repo_explorer.outline_apply_proxy.rows_total.count": .int(
                    measurement.totalRowCount),
                "agentstudio.performance.repo_explorer.outline_apply_proxy.rows_changed.count": .int(
                    measurement.changedRowCount),
                "agentstudio.performance.repo_explorer.outline_apply_proxy.equal_publish.count": .int(
                    measurement.equalPublishCount),
                "agentstudio.performance.repo_explorer.outline_apply_proxy.mainactor_held_ms": .double(
                    AgentStudioPerformanceTraceRecorder.milliseconds(from: measurement.duration)),
            ]
        )
    }
}
extension RepoExplorerView {
    @ViewBuilder
    private var repoToolbarRow: some View {
        let nextSortOrder = repoExplorerPrefs.sortOrder.toggled
        let commandPresentation = RepoExplorerToolbarCommandPresentation.resolve(
            nextSortOrder: nextSortOrder,
            snapshot: commandPresentationSnapshot
        )
        let presentedGroupingModes = RepoExplorerGroupingMode.allCases.filter { groupingMode in
            commandPresentation.command(groupingCommand(for: groupingMode)) != nil
        }

        HStack(spacing: AppStyles.General.Spacing.standard) {
            Spacer(minLength: 0)

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
                .id("repoSidebarSortButton.stable")
                .disabled(!sortCommand.isEnabled)
            }

            if !presentedGroupingModes.isEmpty {
                SidebarToolbarDivider()

                SidebarToolbarSegmentedControl(
                    segments: presentedGroupingModes.map { groupingMode in
                        let command = presentedGroupingCommand(
                            for: groupingMode,
                            in: commandPresentation
                        )
                        return SidebarToolbarSegment(
                            value: groupingMode,
                            label: groupingMode.title,
                            accessibilityIdentifier: "repoSidebarGroupingSegment.\(groupingMode.rawValue)",
                            tooltipValue: command.commandSpec.controlTooltipRenderValue(
                                textOverride: groupingMode.title
                            ),
                            isEnabled: command.isEnabled
                        )
                    },
                    selection: repoExplorerPrefs.groupingMode,
                    icon: { groupingMode in
                        groupingModeIcon(for: groupingMode).swiftUIImage(
                            loader: octiconLoader,
                            size: AppStyles.General.Icon.compact
                        )
                    },
                    onSelect: { groupingMode in
                        let command = groupingCommand(for: groupingMode)
                        guard commandPresentation.command(command)?.isEnabled == true else { return }
                        commandDispatcher.dispatch(command)
                    }
                )
                .accessibilityIdentifier("repoSidebarGroupingControl")
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
