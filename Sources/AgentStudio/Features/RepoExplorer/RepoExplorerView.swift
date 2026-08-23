import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import AppKit
import Foundation
import Observation
import SwiftUI

package typealias BridgeAttendanceSnapshot =
    @MainActor (UUID) -> UInt64?
package typealias LatestPaneMessageSnapshot =
    @MainActor (UUID) -> String?

enum RepoSidebarToolbarTooltipTarget: Hashable {
    case sort
}

/// Sidebar chrome and interaction wiring around the persistent native presentation host.
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
    let commandPresentationDelta: RepoExplorerCommandPresentationDelta?
    let onSetSortOrder: (RepoExplorerSortOrder) -> Void
    let onRefocusActivePane: () -> Void
    let onSidebarVisibleWorktreesChanged: @MainActor @Sendable () -> Void
    let onVisibleWorktreeSnapshotChanged: @MainActor @Sendable (RepoExplorerVisibleWorktreeSnapshot) -> Void
    let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    let initialProjectionSequence: Int
    let onInitialProjectionApplied: @MainActor (Int) -> Void

    static let groupHeaderChromePolicy = SidebarRepoGroupHeader<EmptyView>.chromePolicy
    static let headerLayoutPolicy = SidebarHeaderLayout<EmptyView, EmptyView, EmptyView, EmptyView>.policy
    static let tooltipCoordinateSpaceName = "repoSidebarHeaderTooltips"
    private static let filterDebounceMilliseconds = 25

    package init(
        store: WorkspaceStore,
        octiconLoader: OcticonLoader,
        repoExplorerPrefs: RepoExplorerSidebarPrefsAtom,
        isProjectionDemanded: Bool = true,
        bridgeAttendanceSnapshot: @escaping BridgeAttendanceSnapshot,
        commandDispatcher: any AppCommandDispatching,
        commandPresentationDelta: RepoExplorerCommandPresentationDelta? = nil,
        onSetSortOrder: @escaping (RepoExplorerSortOrder) -> Void,
        onRefocusActivePane: @escaping () -> Void,
        onSidebarVisibleWorktreesChanged: @escaping @MainActor @Sendable () -> Void,
        onVisibleWorktreeSnapshotChanged:
            @escaping @MainActor @Sendable (RepoExplorerVisibleWorktreeSnapshot) -> Void = { _ in },
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
        self.commandPresentationDelta = commandPresentationDelta
        self.onSetSortOrder = onSetSortOrder
        self.onRefocusActivePane = onRefocusActivePane
        self.onSidebarVisibleWorktreesChanged = onSidebarVisibleWorktreesChanged
        self.onVisibleWorktreeSnapshotChanged = onVisibleWorktreeSnapshotChanged
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
                initialProjectionTrigger: resolvedInitialProjectionTrigger
            )
        )
        self.initialProjectionSequence = initialProjectionSequence
        self.onInitialProjectionApplied = onInitialProjectionApplied
    }

    private var uiState: WorkspaceSidebarState {
        atom(\.workspaceSidebarState)
    }

    private var sidebarCache: SidebarCacheState {
        atom(\.sidebarCache)
    }

    @State private var filterText = ""
    @State private var debouncedQuery = ""
    @State private var hasReportedInitialProjection = false
    @State private var hoveredTooltipTarget: RepoSidebarToolbarTooltipTarget?
    @State private var tooltipFrames: [RepoSidebarToolbarTooltipTarget: CGRect] = [:]
    @FocusState private var focusedField: RepoExplorerFocus?
    @State private var debounceTask: Task<Void, Never>?
    @State private var projectionAdapter: RepoExplorerProjectionAdapter

    var commandPresentationSnapshot: RepoExplorerCommandPresentationSnapshot {
        commandPresentationDelta?.snapshot ?? .empty
    }

    package var body: some View {
        VStack(spacing: 0) {
            RepoExplorerFocusBridge(uiState: uiState)
                .frame(width: 1, height: 1)
                .opacity(0.001)

            filterBar

            RepoExplorerPresentationHostView(
                projectionAdapter: projectionAdapter,
                octiconLoader: octiconLoader,
                commandPresentationDelta: commandPresentationDelta,
                interactions: tableInteractions,
                onVisibleWorktreeSnapshotChange: updateSidebarVisibleWorktrees,
                observeCurrentVisibleTarget: onVisibleWorktreeSnapshotChanged
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            clearSidebarVisibleWorktrees()
            RepoExplorerFocusPublisher.publish(focusedField: nil, into: uiState)
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
                        nanoseconds: Duration.milliseconds(Self.filterDebounceMilliseconds)
                            .nanosecondsForTaskSleep
                    )
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
        .onChange(of: projectionAdapter.publishedResult) { _, result in
            guard let result else { return }
            recordProjectionResult(result)
        }
        .onChange(of: isProjectionDemanded) { _, isDemanded in
            projectionAdapter.updateDemand(
                isVisible: isDemanded,
                query: debouncedQuery
            )
        }
        .onChange(of: focusedField) { _, newValue in
            RepoExplorerFocusPublisher.publish(focusedField: newValue, into: uiState)
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
                    activeTarget: hoveredTooltipTarget,
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

    private var tableInteractions: RepoExplorerTableInteractions {
        RepoExplorerTableInteractions(
            onCommandRequest: dispatchTableCommand,
            onToggleGroup: toggleGroupExpansion,
            onFocusPane: focusPane
        )
    }

    func updateTooltipTarget(_ target: RepoSidebarToolbarTooltipTarget, isHovered: Bool) {
        withAnimation(.easeInOut(duration: AppStyles.General.Animation.fast)) {
            hoveredTooltipTarget = isHovered ? target : nil
        }
    }

    private func tooltipValue(for target: RepoSidebarToolbarTooltipTarget) -> ControlTooltipRenderValue? {
        switch target {
        case .sort:
            AppCommand.setRepoSidebarSortOrder.definition.controlTooltipRenderValue(
                textOverride: "Sort \(repoExplorerPrefs.sortOrder.title.lowercased())"
            )
        }
    }

    private func dispatchTableCommand(_ request: RepoExplorerCommandPresentationRequest) {
        switch request.arguments {
        case .noArguments:
            if let target = request.target, let targetType = request.targetType {
                commandDispatcher.dispatch(request.command, target: target, targetType: targetType)
            } else {
                commandDispatcher.dispatch(request.command)
            }
        case .repoSidebarSortOrder(let sortOrder):
            onSetSortOrder(sortOrder)
        }
    }

    private func toggleGroupExpansion(_ groupID: String) {
        guard projectionAdapter.cachedProjectionRequest?.isFiltering != true else { return }
        let key = SidebarGroupKey(groupID)
        sidebarCache.setGroupExpanded(
            key,
            isExpanded: sidebarCache.collapsedGroups.contains(key)
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

    private func recordProjectionResult(_ result: RepoExplorerProjectionResult) {
        RepoExplorerPerformanceTelemetry.shared.record(
            stage: "mainactor_apply",
            outcome: "published"
        )
        performanceTraceRecorder?.recordDuration(
            .sidebarProjection,
            duration: result.projectionDuration,
            attributes: sidebarProjectionTraceAttributes(
                for: projectionRequest(for: result),
                phase: "projection_worker",
                extra: [
                    "agentstudio.performance.sidebar.total_worker_elapsed_ms": .double(
                        AgentStudioPerformanceTraceRecorder.milliseconds(from: result.workerDuration)
                    ),
                    "agentstudio.performance.sidebar.group.count": .int(
                        result.projection.resolvedGroups.count
                    ),
                ]
            )
        )
        performanceTraceRecorder?.recordDuration(
            .sidebarRowIndex,
            duration: result.rowIndexDuration,
            attributes: sidebarProjectionTraceAttributes(
                for: projectionRequest(for: result),
                phase: "row_index",
                extra: [
                    "agentstudio.performance.sidebar.row_index_elapsed_ms": .double(
                        AgentStudioPerformanceTraceRecorder.milliseconds(from: result.rowIndexDuration)
                    )
                ]
            )
        )
        guard
            Self.shouldReportInitialProjection(
                hasReportedInitialProjection: hasReportedInitialProjection
            ), projectionAdapter.materializationHost?.isPresentationReady == true,
            projectionAdapter.acknowledgedMaterializationBaseline != nil
        else { return }
        hasReportedInitialProjection = true
        onInitialProjectionApplied(initialProjectionSequence)
    }

    private func projectionRequest(
        for result: RepoExplorerProjectionResult
    ) -> RepoExplorerProjectionRequest {
        RepoExplorerProjectionRequest(
            generation: result.generation,
            snapshot: result.snapshot,
            collapsedGroupIds: result.collapsedGroupIds,
            isFiltering: result.isFiltering,
            trigger: result.trigger
        )
    }

    package static var sectionHeaderLeadingInset: CGFloat {
        AppStyles.Shell.Sidebar.listRowLeadingInset
    }

    static func checkoutIconKind(
        for worktree: Worktree,
        in repo: RepoPresentationItem
    ) -> RepoExplorerCheckoutIconKind {
        let isMainCheckout =
            worktree.isMainWorktree
            || worktree.path.standardizedFileURL.path == repo.repoPath.standardizedFileURL.path
        return isMainCheckout ? .mainCheckout : .gitWorktree
    }
}
