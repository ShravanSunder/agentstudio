import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import AppKit
import Foundation
import Observation
import SwiftUI

enum RepoExplorerOutlineApplyOutcome: String, Equatable, Sendable {
    case equal
    case changed
    case suppressed
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

enum RepoSidebarToolbarTooltipTarget: Hashable {
    case sort
}

/// Sidebar content grouped by repository identity (worktree family / remote).
@MainActor
package struct RepoExplorerView: View {
    typealias SidebarProjection = RepoExplorerSidebarProjection

    let store: WorkspaceStore
    let octiconLoader: OcticonLoader
    let repoExplorerPrefs: RepoExplorerSidebarPrefsAtom
    let isProjectionDemanded: Bool
    let bridgeAttendanceSnapshot: BridgeAttendanceSnapshot
    let latestPaneMessageSnapshot: LatestPaneMessageSnapshot
    let commandDispatcher: any AppCommandDispatching
    let commandPresentationSnapshot: RepoExplorerCommandPresentationSnapshot
    let onSetSortOrder: (RepoExplorerSortOrder) -> Void
    let onRefocusActivePane: () -> Void
    let onSidebarVisibleWorktreesChanged: @MainActor @Sendable () -> Void
    let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    let initialProjectionSequence: Int
    let onInitialProjectionApplied: @MainActor (Int) -> Void
    static let groupHeaderChromePolicy = SidebarRepoGroupHeader<EmptyView>.chromePolicy
    static let headerLayoutPolicy = SidebarHeaderLayout<EmptyView, EmptyView, EmptyView, EmptyView>.policy
    static let tooltipCoordinateSpaceName = "repoSidebarHeaderTooltips"

    package init(
        store: WorkspaceStore,
        octiconLoader: OcticonLoader,
        repoExplorerPrefs: RepoExplorerSidebarPrefsAtom,
        isProjectionDemanded: Bool = true,
        bridgeAttendanceSnapshot: @escaping BridgeAttendanceSnapshot,
        commandDispatcher: any AppCommandDispatching,
        commandPresentationSnapshot: RepoExplorerCommandPresentationSnapshot = .empty,
        onSetSortOrder: @escaping (RepoExplorerSortOrder) -> Void,
        onRefocusActivePane: @escaping () -> Void,
        onSidebarVisibleWorktreesChanged: @escaping @MainActor @Sendable () -> Void,
        latestPaneMessageSnapshot: @escaping LatestPaneMessageSnapshot = { _ in nil },
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder? = nil,
        recencyNow: @escaping @MainActor @Sendable () -> Date = Date.init,
        recencyDelay: AsyncDelay = .taskSleep,
        initialProjectionTrigger: String = AppPolicies.SidebarProjection.Trigger.startupDiagnostic.rawValue,
        initialProjectionSequence: Int = 0,
        onInitialProjectionApplied: @escaping @MainActor (Int) -> Void = { _ in }
    ) {
        let resolvedInitialProjectionTrigger =
            AppPolicies.SidebarProjection.Trigger(rawValue: initialProjectionTrigger) ?? .startupDiagnostic
        self.store = store
        self.octiconLoader = octiconLoader
        self.repoExplorerPrefs = repoExplorerPrefs
        self.isProjectionDemanded = isProjectionDemanded
        self.bridgeAttendanceSnapshot = bridgeAttendanceSnapshot
        self.commandDispatcher = commandDispatcher
        self.commandPresentationSnapshot = commandPresentationSnapshot
        self.onSetSortOrder = onSetSortOrder
        self.onRefocusActivePane = onRefocusActivePane
        self.onSidebarVisibleWorktreesChanged = onSidebarVisibleWorktreesChanged
        self.latestPaneMessageSnapshot = latestPaneMessageSnapshot
        self.performanceTraceRecorder = performanceTraceRecorder
        _projectionAdapter = State(
            initialValue: RepoExplorerProjectionAdapter(
                inputCapture: RepoExplorerProjectionInputCapture(
                    store: store,
                    preferences: repoExplorerPrefs,
                    repoCache: atom(\.repoCache),
                    sidebarState: atom(\.workspaceSidebarState),
                    sidebarCache: atom(\.sidebarCache),
                    coreAtoms: CoreAtomScope.store,
                    bridgeAttendanceSnapshot: bridgeAttendanceSnapshot,
                    latestPaneMessageSnapshot: latestPaneMessageSnapshot
                ),
                performanceTraceRecorder: performanceTraceRecorder,
                recencyNow: recencyNow,
                recencyDelay: recencyDelay,
                initialProjectionTrigger: resolvedInitialProjectionTrigger,
                onProjectionSuppressed: { result in
                    Self.recordSuppressedOutlineApply(
                        rowCount: result.rowIndex.entries.count,
                        performanceTraceRecorder: performanceTraceRecorder
                    )
                }
            )
        )
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
    @State private var projectionAdapter: RepoExplorerProjectionAdapter
    @State private var scrollInstrumentationState = RepoExplorerScrollInstrumentationState()
    private static let filterDebounceMilliseconds = 25

    private var currentProjection: SidebarProjection {
        cachedProjectionResult.projection
    }

    private var currentRowIndex: RepoExplorerRowIndex {
        cachedProjectionResult.rowIndex
    }

    private var isFiltering: Bool {
        !debouncedQuery.isEmpty
    }

    private var cachedProjectionResult: RepoExplorerProjectionResult {
        projectionAdapter.publishedResult ?? .empty
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
            projectionAdapter.updateDemand(
                isVisible: isProjectionDemanded,
                query: uiState.filterText
            )
        }
        .onDisappear {
            debounceTask?.cancel()
            projectionAdapter.stop()
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
            projectionAdapter.updateDemand(
                isVisible: isProjectionDemanded,
                query: debouncedQuery
            )
        }
        .onChange(of: projectionAdapter.publishedResult) { previousResult, result in
            guard let result else { return }
            applyProjectionResult(previous: previousResult ?? .empty, result: result)
        }
        .onChange(of: isProjectionDemanded) { _, isDemanded in
            projectionAdapter.updateDemand(
                isVisible: isDemanded,
                query: debouncedQuery
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
        hoveredTooltipTarget
    }

    func updateTooltipTarget(_ target: RepoSidebarToolbarTooltipTarget, isHovered: Bool) {
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
                        sectionHeader(
                            kind: kind,
                            isFirstRow: entry.id == rowIndex.entries.first?.id
                        )

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

                    case .unassociatedPaneRow(let destination):
                        let paneFacts = cachedProjectionResult.paneRowFactsByPaneId[destination.paneId]
                        let primaryText =
                            "Pane \(destination.paneIndexInTab + 1) · \(paneFacts?.sidebarTerminalTitle ?? "zsh")"
                        RepoExplorerUnassociatedPaneRow(
                            primaryText: primaryText,
                            secondaryLine: paneFacts?.secondaryLine,
                            recencyText: paneFacts?.recencyText ?? "Now",
                            recencyTier: paneFacts?.recencyTier ?? .strongBlue,
                            isActive: paneFacts?.isActive ?? false,
                            isDrawerPane: paneFacts?.isDrawerPane ?? false,
                            octiconLoader: octiconLoader,
                            onFocus: { focusPane(destination.paneId) }
                        )
                        .listRowInsets(
                            EdgeInsets(
                                top: 0,
                                leading: AppStyles.Shell.Sidebar.groupChildRowLeadingInset,
                                bottom: 0,
                                trailing: 0
                            )
                        )

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

    private func sectionHeader(kind: RepoExplorerSidebarSectionKind, isFirstRow: Bool) -> some View {
        SectionSubheadingLabel(kind.title)
            .padding(.leading, Self.sectionHeaderLeadingInset)
            .padding(.trailing, AppStyles.Components.SectionSubheading.horizontalPadding)
            .padding(.top, isFirstRow ? 0 : AppStyles.Components.SectionSubheading.topPadding)
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
        Color(nsColor: NSColor(hex: colorHex) ?? AppStyles.General.Accent.primaryNSColor)
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

    // Projection validation, telemetry, and the single state publication form
    // one ordered commit path; splitting them would obscure that ordering.
    private func applyProjectionResult(
        previous: RepoExplorerProjectionResult,
        result: RepoExplorerProjectionResult
    ) {
        RepoExplorerPerformanceTelemetry.shared.record(
            stage: "mainactor_apply",
            outcome: "published"
        )
        if RepoExplorerPerformanceTelemetry.shared.isContextActive {
            let referenceProjection = RepoExplorerProjection.project(
                result.snapshot,
                paneRowFactsByPaneId: result.paneRowFactsByPaneId,
                tabGroupFactsByTabId: result.tabGroupFactsByTabId,
                branchNameByWorktreeId: result.branchNameByWorktreeId,
                branchStatusByWorktreeId: result.branchStatusByWorktreeId
            )
            RepoExplorerPerformanceTelemetry.shared.record(
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

        let previousRowIDs = previous.rowIndex.entries.map(\.id)
        let nextRowIDs = result.rowIndex.entries.map(\.id)
        let outlineApplyMeasurement = Self.measureOutlineApplyProxy(
            previousRowIDs: previousRowIDs,
            nextRowIDs: nextRowIDs,
            apply: {}
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
        Self.recordOutlineApplyProxy(
            measurement,
            performanceTraceRecorder: performanceTraceRecorder
        )
    }

    private static func recordSuppressedOutlineApply(
        rowCount: Int,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    ) {
        recordOutlineApplyProxy(
            measureSuppressedOutlineApplyProxy(rowCount: rowCount),
            performanceTraceRecorder: performanceTraceRecorder
        )
    }

    private static func recordOutlineApplyProxy(
        _ measurement: RepoExplorerOutlineApplyMeasurement,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    ) {
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
