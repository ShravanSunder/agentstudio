import AgentStudioCore
import Foundation

struct RepoExplorerObservationRegistration: Equatable, Sendable {
    let repositoryIDs: Set<UUID>
    let worktreeIDs: Set<UUID>
    let paneIDs: Set<UUID>
    let tabIDs: Set<UUID>
    let observesPanePresentation: Bool
    let observesAttention: Bool
    let observesTabPresentation: Bool

    static let hidden = Self(
        repositoryIDs: [],
        worktreeIDs: [],
        paneIDs: [],
        tabIDs: [],
        observesPanePresentation: false,
        observesAttention: false,
        observesTabPresentation: false
    )

    var requiresRecencyDeadline: Bool {
        observesPanePresentation && !paneIDs.isEmpty
    }

    static func make(
        isVisible: Bool,
        surface: SidebarSurface = .repos,
        groupingMode: RepoExplorerGroupingMode,
        subgroupMode: SidebarSubgroupMode = .ungrouped,
        sortField: SidebarSortField = .name,
        repositoryIDs: Set<UUID>,
        worktreeIDs: Set<UUID>,
        paneIDs: Set<UUID>,
        tabIDs: Set<UUID>
    ) -> Self {
        guard isVisible else { return .hidden }

        switch surface {
        case .repos, .inbox:
            let observesPaneActivity = groupingMode == .activity || sortField == .activity
            return Self(
                repositoryIDs: repositoryIDs,
                worktreeIDs: worktreeIDs,
                paneIDs: observesPaneActivity ? paneIDs : [],
                tabIDs: [],
                observesPanePresentation: false,
                observesAttention: false,
                observesTabPresentation: false
            )
        case .panes:
            return Self(
                repositoryIDs: repositoryIDs,
                worktreeIDs: worktreeIDs,
                paneIDs: paneIDs,
                tabIDs: groupingMode == .tab ? tabIDs : [],
                observesPanePresentation: true,
                observesAttention: true,
                observesTabPresentation: groupingMode == .tab
            )
        }
    }
}
