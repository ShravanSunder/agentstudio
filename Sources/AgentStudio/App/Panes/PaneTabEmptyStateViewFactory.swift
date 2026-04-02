import AppKit
import SwiftUI

@MainActor
enum PaneTabEmptyStateViewFactory {
    static func make(
        model: WorkspaceEmptyStateModel,
        onAddFolder: @escaping () -> Void,
        onOpenRecent: @escaping (RecentWorkspaceTarget) -> Void,
        onOpenAllRecent: @escaping () -> Void
    ) -> NSView {
        NSHostingView(
            rootView: WorkspaceEmptyStateView(
                model: model,
                onAddFolder: onAddFolder,
                onOpenRecent: onOpenRecent,
                onOpenAllRecent: onOpenAllRecent
            )
        )
    }
}
