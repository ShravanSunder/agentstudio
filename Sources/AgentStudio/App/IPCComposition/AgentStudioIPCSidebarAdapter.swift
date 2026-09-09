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
        guard params.surface == .repo else {
            throw AppIPCQueryError(reason: .targetNotFound)
        }
        return IPCSidebarGroupingResult(surface: .repo, mode: sidebarGroupingMode(from: repoPrefs.groupingMode))
    }

    func getSurface(_: IPCSidebarSurfaceGetParams) throws -> IPCSidebarSurfaceResult {
        IPCSidebarSurfaceResult(surface: sidebarSurface(from: sidebarState.sidebarSurface))
    }

    private func sidebarGroupingMode(from mode: RepoExplorerGroupingMode) -> IPCSidebarGroupingMode {
        switch mode {
        case .repo:
            return .repo
        case .pane:
            return .pane
        case .tab:
            return .tab
        }
    }

    private func sidebarSurface(from surface: SidebarSurface) -> IPCSidebarSurface {
        _ = surface
        return .repo
    }
}
