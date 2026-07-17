import Foundation

enum WorkspaceTabGraphLeafApplyRejection: Equatable, Sendable {
    case staleActiveArrangement(
        tabID: UUID,
        expected: WorkspaceActiveArrangementSelection,
        actual: WorkspaceActiveArrangementSelection
    )
    case staleTabGraph(
        tabID: UUID,
        expected: TabGraphState,
        actual: WorkspaceTabGraphStateWitness
    )
}

enum WorkspaceTabGraphLeafApplyResult: Equatable, Sendable {
    case applied
    case rejected(WorkspaceTabGraphLeafApplyRejection)
}

enum WorkspaceTabGraphLeafPreflightResult: Equatable, Sendable {
    case ready(WorkspacePreparedTabGraphLeafApplication)
    case rejected(WorkspaceTabGraphLeafApplyRejection)
}

struct WorkspacePreparedTabGraphLeafApplication: Equatable, Sendable {
    fileprivate let transition: WorkspaceTabGraphLeafTransition
}

@MainActor
final class WorkspaceTabGraphLeafTransitionApplier {
    private let workspaceTabGraphAtom: WorkspaceTabGraphAtom
    private let workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom

    init(
        workspaceTabGraphAtom: WorkspaceTabGraphAtom,
        workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom
    ) {
        self.workspaceTabGraphAtom = workspaceTabGraphAtom
        self.workspaceArrangementCursorAtom = workspaceArrangementCursorAtom
    }

    func apply(
        _ transition: WorkspaceTabGraphLeafTransition
    ) -> WorkspaceTabGraphLeafApplyResult {
        switch preflight(transition) {
        case .ready(let preparation):
            apply(preparation)
            return .applied
        case .rejected(let rejection):
            return .rejected(rejection)
        }
    }

    func preflight(
        _ transition: WorkspaceTabGraphLeafTransition
    ) -> WorkspaceTabGraphLeafPreflightResult {
        let actualTab = workspaceTabGraphAtom.tabState(transition.previousTab.tabId)
        guard actualTab == transition.previousTab else {
            return .rejected(
                .staleTabGraph(
                    tabID: transition.previousTab.tabId,
                    expected: transition.previousTab,
                    actual: actualTab.map(WorkspaceTabGraphStateWitness.present) ?? .missing
                )
            )
        }
        switch transition.readWitness {
        case .graphOnly:
            break
        case .activeArrangement(let tabID, let expectedSelection):
            let actualSelection =
                workspaceArrangementCursorAtom.activeArrangementId(forTab: tabID)
                .map(WorkspaceActiveArrangementSelection.selected)
                ?? .missing
            guard actualSelection == expectedSelection else {
                return .rejected(
                    .staleActiveArrangement(
                        tabID: tabID,
                        expected: expectedSelection,
                        actual: actualSelection
                    )
                )
            }
        }
        return .ready(.init(transition: transition))
    }

    func apply(_ preparation: WorkspacePreparedTabGraphLeafApplication) {
        guard case .ready = preflight(preparation.transition) else {
            preconditionFailure("prepared tab-graph leaf transition became stale")
        }
        workspaceTabGraphAtom.replaceTabStatePreservingIdentity(
            preparation.transition.replacementTab
        )
    }
}
