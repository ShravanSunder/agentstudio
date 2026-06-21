import SwiftUI

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

    static var surfaceChromePolicy: SidebarSurfaceChromePolicy {
        SidebarSurfaceChrome<EmptyView>.policy
    }

    var body: some View {
        SidebarSurfaceChrome {
            currentSurface
        }
        .onChange(of: uiState.sidebarSurface) { _, newSurface in
            let clock = ContinuousClock()
            let switchStart = clock.now
            surfaceSwitchSequence += 1
            let switchDuration = switchStart.duration(to: clock.now)
            performanceTraceRecorder?.recordDuration(
                .sidebarProjection,
                duration: switchDuration,
                attributes: sidebarSurfaceSwitchTraceAttributes(for: newSurface, duration: switchDuration)
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
                initialProjectionTrigger: initialProjectionTrigger
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
                onRefocusActivePane: onDismissInbox
            )
            .id(surfaceSwitchSequence)
        }
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
