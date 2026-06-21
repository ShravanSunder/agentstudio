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

    func setGrouping(_ params: IPCSidebarGroupingSetParams) throws -> IPCSidebarGroupingResult {
        switch params.surface {
        case .repo:
            let groupingMode = try repoGroupingMode(from: params.mode)
            repoPrefs.setGroupingMode(groupingMode)
            return IPCSidebarGroupingResult(surface: .repo, mode: params.mode, correlationId: params.correlationId)
        case .inbox:
            let grouping = try inboxGrouping(from: params.mode)
            inboxPrefs.setGrouping(grouping)
            return IPCSidebarGroupingResult(surface: .inbox, mode: params.mode, correlationId: params.correlationId)
        }
    }

    func getGrouping(_ params: IPCSidebarGroupingGetParams) throws -> IPCSidebarGroupingResult {
        switch params.surface {
        case .repo:
            return IPCSidebarGroupingResult(surface: .repo, mode: sidebarGroupingMode(from: repoPrefs.groupingMode))
        case .inbox:
            return IPCSidebarGroupingResult(surface: .inbox, mode: sidebarGroupingMode(from: inboxPrefs.grouping))
        }
    }

    func setSurface(_ params: IPCSidebarSurfaceSetParams) throws -> IPCSidebarSurfaceResult {
        sidebarState.setSidebarSurface(sidebarSurface(from: params.surface))
        return IPCSidebarSurfaceResult(surface: params.surface, correlationId: params.correlationId)
    }

    func getSurface(_: IPCSidebarSurfaceGetParams) throws -> IPCSidebarSurfaceResult {
        IPCSidebarSurfaceResult(surface: sidebarSurface(from: sidebarState.sidebarSurface))
    }

    private func repoGroupingMode(from mode: IPCSidebarGroupingMode) throws -> RepoExplorerGroupingMode {
        switch mode {
        case .repo:
            return .repo
        case .pane:
            return .pane
        case .tab:
            return .tab
        case .noGrouping:
            throw AppIPCCommandError(reason: .validationRejected)
        }
    }

    private func inboxGrouping(from mode: IPCSidebarGroupingMode) throws -> InboxNotificationGrouping {
        switch mode {
        case .repo:
            return .byRepo
        case .pane:
            return .byPane
        case .tab:
            return .byTab
        case .noGrouping:
            return .none
        }
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

    private func sidebarSurface(from surface: IPCSidebarSurface) -> SidebarSurface {
        switch surface {
        case .repo:
            return .repos
        case .inbox:
            return .inbox
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
