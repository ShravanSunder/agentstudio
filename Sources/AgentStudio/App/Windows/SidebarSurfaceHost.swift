import SwiftUI

struct SidebarSurfaceHost: View {
    enum ChildKind: Equatable {
        case repoExplorer
        case inbox
    }

    let store: WorkspaceStore
    let uiState: UIStateAtom
    let inboxAtom: InboxNotificationAtom
    let prefsAtom: InboxNotificationPrefsAtom
    let onRefocusActivePane: () -> Void
    let onDismissInbox: @MainActor @Sendable () -> Void

    var body: some View {
        switch uiState.sidebarSurface {
        case .repos:
            RepoExplorerView(
                store: store,
                onRefocusActivePane: onRefocusActivePane,
                unreadCount: { worktree in
                    Self.unreadCount(for: worktree, inboxAtom: inboxAtom)
                }
            )
        case .inbox:
            InboxNotificationSidebarView(
                inboxAtom: inboxAtom,
                prefsAtom: prefsAtom,
                uiState: uiState,
                workspacePaneAtom: store.paneAtom,
                dispatcher: .shared,
                onRefocusActivePane: onDismissInbox
            )
        }
    }

    static func currentChildKind(uiState: UIStateAtom) -> ChildKind {
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
}
