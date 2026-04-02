import Foundation

enum WorkspaceEmptyStateKind: Equatable {
    case noFolders
    case launcher
}

struct WorkspaceEmptyStateModel: Equatable {
    let kind: WorkspaceEmptyStateKind
    let recentTargets: [RecentWorkspaceTarget]

    var showsOpenAll: Bool {
        recentTargets.count > 1
    }
}

enum WorkspaceLauncherProjector {
    static func project(
        repos: [Repo],
        tabs: [Tab],
        recentTargets: [RecentWorkspaceTarget]
    ) -> WorkspaceEmptyStateModel {
        if repos.isEmpty {
            return WorkspaceEmptyStateModel(kind: .noFolders, recentTargets: [])
        }

        if tabs.isEmpty {
            let visibleTargets = Array(recentTargets.prefix(5))
            return WorkspaceEmptyStateModel(
                kind: .launcher,
                recentTargets: visibleTargets
            )
        }

        return WorkspaceEmptyStateModel(kind: .launcher, recentTargets: [])
    }
}
