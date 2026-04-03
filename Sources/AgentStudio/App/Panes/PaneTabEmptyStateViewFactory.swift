import AppKit
import SwiftUI

@MainActor
enum PaneTabEmptyStateViewFactory {
    static func make(
        model: WorkspaceEmptyStateModel,
        repoCount: Int,
        onAddFolder: @escaping () -> Void,
        onOpenRecent: @escaping (RecentWorkspaceTarget) -> Void,
        onOpenAllRecent: @escaping () -> Void
    ) -> NSHostingView<WorkspaceEmptyStateView> {
        NSHostingView(
            rootView: WorkspaceEmptyStateView(
                model: model,
                repoCount: repoCount,
                onAddFolder: onAddFolder,
                onOpenRecent: onOpenRecent,
                onOpenAllRecent: onOpenAllRecent
            )
        )
    }
}
