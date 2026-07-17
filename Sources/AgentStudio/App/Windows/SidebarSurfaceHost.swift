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
    let uiState: WorkspaceSidebarState
    let sidebarCache: SidebarCacheState
    let inboxSidebarState: InboxSidebarState
    let inboxAtom: InboxNotificationAtom
    let prefsAtom: InboxNotificationPrefsAtom
    let repoCache: RepoCacheAtom
    let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    let onRefocusActivePane: () -> Void
    let onDismissInbox: @MainActor @Sendable () -> Void
    @State private var surfaceSwitchSequence = 0
    @State private var surfaceSwitchMetricState = SidebarSurfaceSwitchMetricState()

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
        let initialProjectionTrigger = surfaceSwitchSequence == 0 ? "startup_diagnostic" : "surface_switch"
        switch uiState.sidebarSurface {
        case .repos:
            RepoExplorerView(
                store: store,
                onRefocusActivePane: onRefocusActivePane,
                onShowNotificationsForWorktree: { worktree in
                    Self.showNotifications(
                        for: worktree,
                        inboxSidebarState: inboxSidebarState,
                        dispatcher: .shared
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
        case .inbox:
            InboxNotificationSidebarView(
                inboxAtom: inboxAtom,
                prefsAtom: prefsAtom,
                uiState: uiState,
                sidebarCache: sidebarCache,
                inboxSidebarState: inboxSidebarState,
                workspacePaneAtom: store.paneAtom,
                workspaceRepositoryTopologyAtom: store.repositoryTopologyAtom,
                repoCache: repoCache,
                dispatcher: .shared,
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
            "agentstudio.performance.sidebar.phase": .string("mainactor_apply"),
            "agentstudio.performance.sidebar.trigger": .string("surface_switch"),
            "agentstudio.performance.sidebar.query_state": .string("empty"),
            "agentstudio.performance.sidebar.group_mode": .string("not_applicable"),
            "agentstudio.performance.sidebar.group.count": .int(0),
            "agentstudio.performance.sidebar.mainactor_apply_elapsed_ms": .double(
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
