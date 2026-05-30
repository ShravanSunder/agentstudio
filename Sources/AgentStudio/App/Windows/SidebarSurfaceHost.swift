import SwiftUI

struct SidebarSurfaceHost: View {
    enum ChildKind: Equatable {
        case repoExplorer
        case inbox
    }

    let store: WorkspaceStore
    let uiState: WorkspaceSidebarState
    let sidebarCache: SidebarCacheAtom
    let inboxSidebarState: InboxSidebarStateAtom
    let inboxAtom: InboxNotificationAtom
    let prefsAtom: InboxNotificationPrefsAtom
    let repoCache: RepoCacheAtom
    let onRefocusActivePane: () -> Void
    let onDismissInbox: @MainActor @Sendable () -> Void

    static var surfaceChromePolicy: SidebarSurfaceChromePolicy {
        SidebarSurfaceChrome<EmptyView>.policy
    }

    var body: some View {
        SidebarSurfaceChrome {
            currentSurface
        }
    }

    @ViewBuilder
    private var currentSurface: some View {
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
                    Self.unreadCount(for: worktree, inboxAtom: inboxAtom)
                }
            )
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
                onRefocusActivePane: onDismissInbox
            )
        }
    }

    static func currentChildKind(uiState: WorkspaceSidebarState) -> ChildKind {
        switch uiState.sidebarSurface {
        case .repos:
            .repoExplorer
        case .inbox:
            .inbox
        }
    }

    static func unreadCount(
        for worktree: Worktree,
        inboxAtom: InboxNotificationAtom
    ) -> Int {
        inboxAtom.unreadCount(forWorktreeId: worktree.id)
    }

    static func showNotifications(
        for worktree: Worktree,
        inboxSidebarState: InboxSidebarStateAtom,
        dispatcher: CommandDispatcher
    ) {
        inboxSidebarState.setPendingFilter(.worktree(id: worktree.id))
        dispatcher.dispatch(.showInboxNotifications)
    }
}
