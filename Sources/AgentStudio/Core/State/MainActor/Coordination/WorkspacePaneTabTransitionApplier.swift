import Foundation

enum WorkspacePaneTabTransitionApplicationRejection: Equatable, Sendable {
    case paneAlreadyExists(UUID)
    case tabTransitionRejected(WorkspaceTabTransitionApplicationRejection)
}

enum WorkspacePaneTabTransitionPreflightResult: Equatable, Sendable {
    case ready(WorkspacePreparedPaneTabTransitionApplication)
    case rejected(WorkspacePaneTabTransitionApplicationRejection)
}

struct WorkspacePreparedPaneTabTransitionApplication: Equatable, Sendable {
    fileprivate let paneState: PaneGraphState
    fileprivate let tabApplication: WorkspacePreparedTabTransitionApplication
}

@MainActor
final class WorkspacePaneTabTransitionApplier {
    private let workspacePaneGraphAtom: WorkspacePaneGraphAtom
    private let workspaceTabTransitionApplier: WorkspaceTabTransitionApplier

    init(
        workspacePaneGraphAtom: WorkspacePaneGraphAtom,
        workspaceTabTransitionApplier: WorkspaceTabTransitionApplier
    ) {
        self.workspacePaneGraphAtom = workspacePaneGraphAtom
        self.workspaceTabTransitionApplier = workspaceTabTransitionApplier
    }

    func preflight(
        paneState: PaneGraphState,
        tabTransition: WorkspaceTabTransition
    ) -> WorkspacePaneTabTransitionPreflightResult {
        guard workspacePaneGraphAtom.paneState(paneState.id) == nil else {
            return .rejected(.paneAlreadyExists(paneState.id))
        }

        switch workspaceTabTransitionApplier.preflight(tabTransition) {
        case .ready(let tabApplication):
            return .ready(
                WorkspacePreparedPaneTabTransitionApplication(
                    paneState: paneState,
                    tabApplication: tabApplication
                )
            )
        case .rejected(let rejection):
            return .rejected(.tabTransitionRejected(rejection))
        }
    }

    func apply(_ preparation: WorkspacePreparedPaneTabTransitionApplication) {
        precondition(
            workspacePaneGraphAtom.paneState(preparation.paneState.id) == nil,
            "prepared pane-tab transition pane identity is stale"
        )
        workspaceTabTransitionApplier.preconditionPreparedApplicationIsFresh(
            preparation.tabApplication
        )

        workspacePaneGraphAtom.setCanonicalPaneState(preparation.paneState)
        workspaceTabTransitionApplier.apply(preparation.tabApplication)
    }
}
