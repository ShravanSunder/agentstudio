import AgentStudioCore
import AgentStudioInboxNotification
import AgentStudioInfrastructure
import AgentStudioRepoExplorer
import AgentStudioSharedComponents
import SwiftUI

struct SidebarSurfaceSwitchMetricState {
    private struct PendingSwitch {
        let sequence: Int
        let surface: SidebarSurface
        let start: ContinuousClock.Instant
    }

    private var pendingSwitch: PendingSwitch?

    mutating func begin(sequence: Int, surface: SidebarSurface, at start: ContinuousClock.Instant) {
        pendingSwitch = PendingSwitch(sequence: sequence, surface: surface, start: start)
    }

    mutating func complete(
        sequence: Int,
        surface: SidebarSurface,
        at completion: ContinuousClock.Instant
    ) -> Duration? {
        guard
            let pendingSwitch,
            pendingSwitch.sequence == sequence,
            pendingSwitch.surface == surface
        else { return nil }

        self.pendingSwitch = nil
        return pendingSwitch.start.duration(to: completion)
    }
}

struct SidebarSurfaceHost: View {
    enum ChildKind: Equatable {
        case repoExplorer
        case inbox
    }

    let store: WorkspaceStore
    let octiconLoader: OcticonLoader
    let uiState: WorkspaceSidebarState
    let sidebarCache: SidebarCacheState
    let inboxSidebarState: InboxSidebarState
    let inboxAtom: InboxNotificationAtom
    let prefsAtom: InboxNotificationPrefsAtom
    let repoCache: RepoCacheAtom
    let repoExplorerSidebarPrefs: RepoExplorerSidebarPrefsAtom
    let bridgeAttendanceSnapshot: BridgeAttendanceSnapshot
    let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    let onRefocusActivePane: () -> Void
    let onSidebarVisibleWorktreesChanged: @MainActor @Sendable () -> Void
    let onDismissInbox: @MainActor @Sendable () -> Void
    @State private var surfaceSwitchSequence = 0
    @State private var surfaceSwitchMetricState = SidebarSurfaceSwitchMetricState()
    @State private var repoCommandPresentationBatch: RepoExplorerCommandPresentationBatch?

    static var surfaceChromePolicy: SidebarSurfaceChromePolicy {
        SidebarSurfaceChrome<EmptyView>.policy
    }

    var body: some View {
        SidebarSurfaceChrome {
            currentSurface
        }
        .onChange(of: uiState.sidebarSurface) { _, newSurface in
            surfaceSwitchSequence += 1
            surfaceSwitchMetricState.begin(
                sequence: surfaceSwitchSequence,
                surface: newSurface,
                at: ContinuousClock().now
            )
        }
    }

    @ViewBuilder
    private var currentSurface: some View {
        let initialProjectionTrigger = surfaceSwitchSequence == 0 ? "data_refresh" : "surface_switch"
        switch uiState.sidebarSurface {
        case .repos:
            RepoExplorerView(
                store: store,
                octiconLoader: octiconLoader,
                repoExplorerPrefs: repoExplorerSidebarPrefs,
                bridgeAttendanceSnapshot: bridgeAttendanceSnapshot,
                commandDispatcher: AppCommandDispatcher.shared,
                commandPresentationSnapshot: repoCommandPresentationBatch?.snapshot ?? .empty,
                onSetVisibilityMode: { mode in
                    AppCommandDispatcher.shared.dispatch(
                        AppCommandExecutionRequest(
                            command: .setRepoSidebarVisibilityMode,
                            arguments: .repoSidebarVisibilityMode(mode)
                        )
                    )
                },
                onSetSortOrder: { order in
                    AppCommandDispatcher.shared.dispatch(
                        AppCommandExecutionRequest(
                            command: .setRepoSidebarSortOrder,
                            arguments: .repoSidebarSortOrder(order)
                        )
                    )
                },
                onRefocusActivePane: onRefocusActivePane,
                onSidebarVisibleWorktreesChanged: onSidebarVisibleWorktreesChanged,
                onShowNotificationsForWorktree: { worktree in
                    Self.showNotifications(
                        for: worktree,
                        inboxSidebarState: inboxSidebarState,
                        dispatcher: AppCommandDispatcher.shared
                    )
                },
                unreadCount: { worktree in
                    Self.rollUpAlertCount(for: worktree, inboxAtom: inboxAtom)
                },
                performanceTraceRecorder: performanceTraceRecorder,
                initialProjectionTrigger: initialProjectionTrigger,
                initialProjectionSequence: surfaceSwitchSequence,
                onInitialProjectionApplied: { sequence in
                    completeSurfaceSwitch(sequence: sequence, surface: .repos)
                }
            )
            .id(surfaceSwitchSequence)
            .task {
                guard repoCommandPresentationBatch == nil else { return }
                let batch = RepoExplorerCommandPresentationBatch(
                    store: store,
                    repoExplorerPrefs: repoExplorerSidebarPrefs,
                    visibleWorktrees: atom(\.sidebarVisibleWorktreesRuntime),
                    dispatcher: .shared,
                    performanceTraceRecorder: performanceTraceRecorder
                )
                repoCommandPresentationBatch = batch
                batch.start()
            }
            .onDisappear {
                repoCommandPresentationBatch?.stop()
                repoCommandPresentationBatch = nil
            }
        case .inbox:
            InboxNotificationSidebarView(
                inboxAtom: inboxAtom,
                octiconLoader: octiconLoader,
                prefsAtom: prefsAtom,
                uiState: uiState,
                sidebarCache: sidebarCache,
                inboxSidebarState: inboxSidebarState,
                workspacePaneAtom: store.paneAtom,
                workspaceRepositoryTopologyAtom: store.repositoryTopologyAtom,
                repoCache: repoCache,
                dispatcher: AppCommandDispatcher.shared,
                canSetRowStateFilter: { filter in
                    AppCommandDispatcher.shared.canDispatch(
                        AppCommandExecutionRequest(
                            command: .setInboxRowStateFilter,
                            arguments: .inboxRowStateFilter(filter)
                        )
                    )
                },
                canSetContentMode: { mode in
                    AppCommandDispatcher.shared.canDispatch(
                        AppCommandExecutionRequest(
                            command: .setInboxContentMode,
                            arguments: .inboxContentMode(mode)
                        )
                    )
                },
                onSetRowStateFilter: { filter in
                    AppCommandDispatcher.shared.dispatch(
                        AppCommandExecutionRequest(
                            command: .setInboxRowStateFilter,
                            arguments: .inboxRowStateFilter(filter)
                        )
                    )
                },
                onSetContentMode: { mode in
                    AppCommandDispatcher.shared.dispatch(
                        AppCommandExecutionRequest(
                            command: .setInboxContentMode,
                            arguments: .inboxContentMode(mode)
                        )
                    )
                },
                performanceTraceRecorder: performanceTraceRecorder,
                initialProjectionTrigger: initialProjectionTrigger,
                initialProjectionSequence: surfaceSwitchSequence,
                onInitialProjectionApplied: { sequence in
                    completeSurfaceSwitch(sequence: sequence, surface: .inbox)
                },
                onRefocusActivePane: onDismissInbox
            )
            .id(surfaceSwitchSequence)
        }
    }

    private func completeSurfaceSwitch(sequence: Int, surface: SidebarSurface) {
        guard
            let switchDuration = surfaceSwitchMetricState.complete(
                sequence: sequence,
                surface: surface,
                at: ContinuousClock().now
            )
        else { return }

        performanceTraceRecorder?.recordDuration(
            .sidebarProjection,
            duration: switchDuration,
            attributes: sidebarSurfaceSwitchTraceAttributes(for: surface, duration: switchDuration)
        )
    }

    private func sidebarSurfaceSwitchTraceAttributes(
        for surface: SidebarSurface,
        duration: Duration
    ) -> [String: AgentStudioTraceValue] {
        [
            "agentstudio.performance.sidebar.surface": .string(surface == .repos ? "repo" : "inbox"),
            "agentstudio.performance.sidebar.phase": .string("surface_switch"),
            "agentstudio.performance.sidebar.trigger": .string("surface_switch"),
            "agentstudio.performance.sidebar.query_state": .string("empty"),
            "agentstudio.performance.sidebar.group_mode": .string("not_applicable"),
            "agentstudio.performance.sidebar.group.count": .int(0),
            "agentstudio.performance.sidebar.surface_switch_elapsed_ms": .double(
                AgentStudioPerformanceTraceRecorder.milliseconds(from: duration)),
        ]
    }

    static func currentChildKind(uiState: WorkspaceSidebarState) -> ChildKind {
        switch uiState.sidebarSurface {
        case .repos:
            .repoExplorer
        case .inbox:
            .inbox
        }
    }

    static func rollUpAlertCount(
        for worktree: Worktree,
        inboxAtom: InboxNotificationAtom
    ) -> Int {
        inboxAtom.rollUpAlertCount(forWorktreeId: worktree.id)
    }

    static func showNotifications(
        for worktree: Worktree,
        inboxSidebarState: InboxSidebarState,
        dispatcher: AppCommandDispatcher
    ) {
        inboxSidebarState.setPendingFilter(.worktree(id: worktree.id))
        inboxSidebarState.setPendingDisplayOverride(
            .init(contentMode: .rollUpAlerts, rowStateFilter: .unreadOnly)
        )
        dispatcher.dispatch(.showInboxNotifications)
    }
}
