import AgentStudioCore
import Foundation

enum RepoExplorerPaneLocationProjection {
    static func unassociatedDestinations(
        from locations: [WorkspacePaneLocation]
    ) -> [RepoExplorerUnassociatedPaneDestination] {
        locations.map { location in
            RepoExplorerUnassociatedPaneDestination(
                paneId: location.paneId,
                tabId: location.tabId,
                tabIndex: location.tabIndex,
                paneIndexInTab: location.paneIndexInTab,
                isActiveInTab: location.isActiveInTab
            )
        }
    }

    static func sortedUniqueTabIds(_ locations: [WorkspacePaneLocation]) -> [UUID] {
        var seenTabIds = Set<UUID>()
        return
            locations
            .sorted {
                if $0.tabIndex != $1.tabIndex {
                    return $0.tabIndex > $1.tabIndex
                }
                return $0.tabId.uuidString < $1.tabId.uuidString
            }
            .compactMap { location in
                seenTabIds.insert(location.tabId).inserted ? location.tabId : nil
            }
    }
}
