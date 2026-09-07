import AgentStudioAppIPC
import AgentStudioCore
import AgentStudioProgrammaticControl
import AgentStudioRepoExplorer
import Foundation

@MainActor
struct AgentStudioIPCSidebarAdapter: AppIPCSidebarPort, @unchecked Sendable {
    private let repoPrefs: RepoExplorerSidebarPrefsAtom
    private let sidebarState: WorkspaceSidebarState

    init(
        repoPrefs: RepoExplorerSidebarPrefsAtom,
        sidebarState: WorkspaceSidebarState
    ) {
        self.repoPrefs = repoPrefs
        self.sidebarState = sidebarState
    }

    func getGrouping(_ params: IPCSidebarGroupingGetParams) throws -> IPCSidebarGroupingResult {
        let surface: SidebarSurface
        switch params.surface {
        case .repo: surface = .repos
        case .panes: surface = .panes
        case .inbox: throw AppIPCQueryError(reason: .targetNotFound)
        }
        return IPCSidebarGroupingResult(
            surface: params.surface, mode: sidebarGroupingMode(from: repoPrefs.groupingMode(for: surface))
        )
    }

    func getSurface(_: IPCSidebarSurfaceGetParams) throws -> IPCSidebarSurfaceResult {
        switch sidebarState.sidebarSurface {
        case .repos: return IPCSidebarSurfaceResult(surface: .repo)
        case .panes: return IPCSidebarSurfaceResult(surface: .panes)
        case .inbox: throw AppIPCQueryError(reason: .targetNotFound)
        }
    }

    private func sidebarGroupingMode(from mode: RepoExplorerGroupingMode) -> IPCSidebarGroupingMode {
        switch mode {
        case .repo:
            return .repo
        case .activity:
            return .activity
        case .tab:
            return .tab
        }
    }

}
