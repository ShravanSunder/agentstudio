import SwiftUI

struct SidebarSurfaceHost: View {
    enum ChildKind: Equatable {
        case repoExplorer
        case inboxPlaceholder
    }

    let store: WorkspaceStore
    let uiState: UIStateAtom
    let onRefocusActivePane: () -> Void
    let onDismissInbox: @MainActor @Sendable () -> Void

    var body: some View {
        switch uiState.sidebarSurface {
        case .repos:
            RepoExplorerView(
                store: store,
                onRefocusActivePane: onRefocusActivePane
            )
        case .inbox:
            InboxNotificationPlaceholderView(
                uiState: uiState,
                onEscape: onDismissInbox
            )
        }
    }

    static func currentChildKind(uiState: UIStateAtom) -> ChildKind {
        switch uiState.sidebarSurface {
        case .repos:
            .repoExplorer
        case .inbox:
            .inboxPlaceholder
        }
    }
}
