import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioRepoExplorer
import AgentStudioSharedComponents
import SwiftUI

struct SidebarSurfaceSwitchMetricState {
    private struct PendingSwitch {
        let sequence: Int
        let surface: SidebarSurface
        let start: ContinuousClock.Instant
    }

    private var pendingSwitch: PendingSwitch?

    mutating func begin(sequence: Int, surface: SidebarSurface, at start: ContinuousClock.Instant) {
        pendingSwitch = PendingSwitch(sequence: sequence, surface: surface, start: start)
    }

    mutating func complete(
        sequence: Int,
        surface: SidebarSurface,
        at completion: ContinuousClock.Instant
    ) -> Duration? {
        guard
            let pendingSwitch,
            pendingSwitch.sequence == sequence,
            pendingSwitch.surface == surface
        else { return nil }

        self.pendingSwitch = nil
        return pendingSwitch.start.duration(to: completion)
    }
}

struct SidebarSurfaceHost: View {
    enum SurfaceSwitchPublicationMode: Equatable {
        case cachedThenDelta
    }

    enum ChildKind: Equatable {
        case repoExplorer
    }

    let store: WorkspaceStore
    let octiconLoader: OcticonLoader
    let paneActivityStatusAtom: PaneActivityStatusAtom
    let repoExplorerSidebarPrefs: RepoExplorerSidebarPrefsAtom
    let bridgeAttendanceSnapshot: BridgeAttendanceSnapshot
    let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    let onRefocusActivePane: () -> Void
    let onSidebarVisibleWorktreesChanged: @MainActor @Sendable () -> Void
    @State private var repoCommandPresentationBatch: RepoExplorerCommandPresentationBatch?

    static var surfaceChromePolicy: SidebarSurfaceChromePolicy {
        SidebarSurfaceChrome<EmptyView>.policy
    }

    static let surfaceSwitchPublicationMode: SurfaceSwitchPublicationMode = .cachedThenDelta

    var body: some View {
        SidebarSurfaceChrome {
            RepoExplorerView(
                store: store,
                octiconLoader: octiconLoader,
                repoExplorerPrefs: repoExplorerSidebarPrefs,
                isProjectionDemanded: true,
                bridgeAttendanceSnapshot: bridgeAttendanceSnapshot,
                commandDispatcher: AppCommandDispatcher.shared,
                commandPresentationSnapshot: repoCommandPresentationBatch?.snapshot ?? .empty,
                onSetSortOrder: { order in
                    AppCommandDispatcher.shared.dispatch(
                        AppCommandExecutionRequest(
                            command: .setRepoSidebarSortOrder,
                            arguments: .repoSidebarSortOrder(order)
                        )
                    )
                },
                onRefocusActivePane: onRefocusActivePane,
                onSidebarVisibleWorktreesChanged: onSidebarVisibleWorktreesChanged,
                latestPaneMessageSnapshot: { paneId in
                    paneActivityStatusAtom.status(for: paneId)?.lastOutputLine
                },
                performanceTraceRecorder: performanceTraceRecorder,
                initialProjectionTrigger: "data_refresh"
            )
            .task {
                guard repoCommandPresentationBatch == nil else { return }
                let batch = RepoExplorerCommandPresentationBatch(
                    store: store,
                    repoExplorerPrefs: repoExplorerSidebarPrefs,
                    visibleWorktrees: atom(\.sidebarVisibleWorktreesRuntime),
                    dispatcher: .shared,
                    performanceTraceRecorder: performanceTraceRecorder
                )
                repoCommandPresentationBatch = batch
                batch.start()
            }
            .onDisappear {
                repoCommandPresentationBatch?.stop()
                repoCommandPresentationBatch = nil
            }
        }
    }

    static func currentChildKind(uiState: WorkspaceSidebarState) -> ChildKind {
        _ = uiState
        return .repoExplorer
    }
}
