import Foundation

enum WorkspaceLayoutResizeApplyRejection: Equatable, Sendable {
    case staleTabGraph(tabID: UUID, expected: TabGraphState, actual: WorkspaceTabGraphStateWitness)
    case staleActiveArrangement(
        tabID: UUID,
        expected: WorkspaceActiveArrangementSelection,
        actual: WorkspaceActiveArrangementSelection
    )
}

enum WorkspaceLayoutResizeApplyResult: Equatable, Sendable {
    case applied
    case rejected(WorkspaceLayoutResizeApplyRejection)
}

enum WorkspaceLayoutResizePreflightResult: Equatable, Sendable {
    case ready(WorkspacePreparedLayoutResizeApplication)
    case rejected(WorkspaceLayoutResizeApplyRejection)
}

struct WorkspacePreparedLayoutResizeApplication: Equatable, Sendable {
    fileprivate let transition: WorkspaceLayoutResizeTransition
}

@MainActor
final class WorkspaceLayoutResizeTransitionApplier {
    private let workspaceTabGraphAtom: WorkspaceTabGraphAtom
    private let workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom

    init(
        workspaceTabGraphAtom: WorkspaceTabGraphAtom,
        workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom
    ) {
        self.workspaceTabGraphAtom = workspaceTabGraphAtom
        self.workspaceArrangementCursorAtom = workspaceArrangementCursorAtom
    }

    func apply(_ transition: WorkspaceLayoutResizeTransition) -> WorkspaceLayoutResizeApplyResult {
        switch preflight(transition) {
        case .ready(let preparation):
            apply(preparation)
            return .applied
        case .rejected(let rejection):
            return .rejected(rejection)
        }
    }

    func preflight(_ transition: WorkspaceLayoutResizeTransition) -> WorkspaceLayoutResizePreflightResult {
        let actualTab = workspaceTabGraphAtom.tabState(transition.tabID)
        guard actualTab == transition.previousTabGraph else {
            return .rejected(
                .staleTabGraph(
                    tabID: transition.tabID,
                    expected: transition.previousTabGraph,
                    actual: actualTab.map(WorkspaceTabGraphStateWitness.present) ?? .missing
                )
            )
        }
        let actualArrangement =
            workspaceArrangementCursorAtom.activeArrangementId(forTab: transition.tabID)
            .map(WorkspaceActiveArrangementSelection.selected) ?? .missing
        guard actualArrangement == transition.expectedActiveArrangement else {
            return .rejected(
                .staleActiveArrangement(
                    tabID: transition.tabID,
                    expected: transition.expectedActiveArrangement,
                    actual: actualArrangement
                )
            )
        }
        return .ready(.init(transition: transition))
    }

    func apply(_ preparation: WorkspacePreparedLayoutResizeApplication) {
        switch preflight(preparation.transition) {
        case .ready:
            workspaceTabGraphAtom.replaceTabStatePreservingIdentity(
                preparation.transition.replacementTabGraph
            )
        case .rejected(let rejection):
            preconditionFailure("prepared layout resize is stale: \(rejection)")
        }
    }
}
