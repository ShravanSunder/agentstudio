import AgentStudioCore
import AgentStudioInfrastructure
import AppKit
import SwiftUI

@MainActor
enum PaneTabEmptyStateViewFactory {
    static func make(
        model: WorkspaceEmptyStateModel,
        octiconLoader: OcticonLoader,
        onWatchFolder: @escaping () -> Void,
        onOpenRecent: @escaping (RecentWorkspaceTarget) -> Void,
        onOpenAllRecent: @escaping () -> Void
    ) -> NSHostingView<WorkspaceEmptyStateView> {
        let view = NSHostingView(
            rootView: WorkspaceEmptyStateView(
                model: model,
                octiconLoader: octiconLoader,
                onWatchFolder: onWatchFolder,
                onOpenRecent: onOpenRecent,
                onOpenAllRecent: onOpenAllRecent
            )
        )
        view.sizingOptions = []
        return view
    }
}
