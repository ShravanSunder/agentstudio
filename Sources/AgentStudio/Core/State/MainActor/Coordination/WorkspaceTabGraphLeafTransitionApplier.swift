import Foundation

enum WorkspaceTabGraphLeafApplyRejection: Equatable, Sendable {
    case staleActiveArrangement(
        tabID: UUID,
        expected: WorkspaceActiveArrangementSelection,
        actual: WorkspaceActiveArrangementSelection
    )
    case staleTabGraphs(expected: [TabGraphState], actual: [TabGraphState])
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
        let expectedTabStates = transition.expectedPreviousTabStates
        guard workspaceTabGraphAtom.tabStates == expectedTabStates else {
            return .rejected(
                .staleTabGraphs(
                    expected: expectedTabStates,
                    actual: workspaceTabGraphAtom.tabStates
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
        return .ready(
            WorkspacePreparedTabGraphLeafApplication(transition: transition)
        )
    }

    func apply(_ preparation: WorkspacePreparedTabGraphLeafApplication) {
        preconditionPreparedApplicationIsFresh(preparation)
        workspaceTabGraphAtom.replaceTabStates(preparation.transition.replacementTabStates)
    }

    private func preconditionPreparedApplicationIsFresh(
        _ preparation: WorkspacePreparedTabGraphLeafApplication
    ) {
        switch preflight(preparation.transition) {
        case .ready:
            return
        case .rejected(let rejection):
            preconditionFailure("prepared tab-graph leaf transition is stale: \(rejection)")
        }
    }
}

extension WorkspaceTabGraphLeafTransition {
    fileprivate var expectedPreviousTabStates: [TabGraphState] {
        var expectedTabStates = replacementTabStates
        precondition(
            expectedTabStates.indices.contains(affectedTab.previous.index),
            "tab-graph leaf transition previous index must remain in collection bounds"
        )
        expectedTabStates[affectedTab.previous.index] = affectedTab.previous.state
        return expectedTabStates
    }
}
