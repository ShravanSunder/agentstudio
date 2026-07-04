import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation

@MainActor
struct AgentStudioIPCSidebarAdapter: AppIPCSidebarPort, @unchecked Sendable {
    private let repoPrefs: RepoExplorerSidebarPrefsAtom
    private let inboxPrefs: InboxNotificationPrefsAtom
    private let sidebarState: WorkspaceSidebarState

    init(
        repoPrefs: RepoExplorerSidebarPrefsAtom,
        inboxPrefs: InboxNotificationPrefsAtom,
        sidebarState: WorkspaceSidebarState
    ) {
        self.repoPrefs = repoPrefs
        self.inboxPrefs = inboxPrefs
        self.sidebarState = sidebarState
    }

    func getGrouping(_ params: IPCSidebarGroupingGetParams) throws -> IPCSidebarGroupingResult {
        switch params.surface {
        case .repo:
            return IPCSidebarGroupingResult(surface: .repo, mode: sidebarGroupingMode(from: repoPrefs.groupingMode))
        case .inbox:
            return IPCSidebarGroupingResult(surface: .inbox, mode: sidebarGroupingMode(from: inboxPrefs.grouping))
        }
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

    private func sidebarGroupingMode(from grouping: InboxNotificationGrouping) -> IPCSidebarGroupingMode {
        switch grouping {
        case .none:
            return .noGrouping
        case .byRepo:
            return .repo
        case .byPane:
            return .pane
        case .byTab:
            return .tab
        }
    }

    private func sidebarSurface(from surface: SidebarSurface) -> IPCSidebarSurface {
        switch surface {
        case .repos:
            return .repo
        case .inbox:
            return .inbox
        }
    }
}
