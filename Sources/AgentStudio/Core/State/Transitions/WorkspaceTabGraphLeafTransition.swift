import Foundation

enum WorkspaceActiveArrangementSelection: Equatable, Sendable {
    case missing
    case selected(UUID)
}

struct WorkspaceEqualizePanesRequest: Equatable, Sendable {
    let tabID: UUID
}

struct WorkspaceRenameArrangementRequest: Equatable, Sendable {
    let tabID: UUID
    let arrangementID: UUID
    let name: String
}

enum WorkspaceTabGraphLeafTransitionRejection: Equatable, Sendable {
    case defaultArrangementCannotBeRenamed(tabID: UUID, arrangementID: UUID)
    case emptyArrangementName(UUID)
    case missingActiveArrangement(UUID)
    case missingArrangement(tabID: UUID, arrangementID: UUID)
    case missingTab(UUID)
    case tabNotSplit(UUID)
}

enum WorkspaceTabGraphLeafReadWitness: Equatable, Sendable {
    case graphOnly
    case activeArrangement(tabID: UUID, expected: WorkspaceActiveArrangementSelection)
}

struct WorkspaceIndexedTabGraphState: Equatable, Sendable {
    let index: Int
    let state: TabGraphState
}

struct WorkspaceIndexedTabGraphReplacement: Equatable, Sendable {
    let previous: WorkspaceIndexedTabGraphState
    let replacement: WorkspaceIndexedTabGraphState
}

struct WorkspaceTabGraphLeafTransition: Equatable, Sendable {
    let replacementTabStates: [TabGraphState]
    let affectedTab: WorkspaceIndexedTabGraphReplacement
    let readWitness: WorkspaceTabGraphLeafReadWitness

    fileprivate init(
        replacementTabStates: [TabGraphState],
        affectedTab: WorkspaceIndexedTabGraphReplacement,
        readWitness: WorkspaceTabGraphLeafReadWitness
    ) {
        precondition(
            affectedTab.previous.state.tabId == affectedTab.replacement.state.tabId,
            "a tab-graph leaf transition must preserve tab identity"
        )
        precondition(
            affectedTab.previous.index == affectedTab.replacement.index,
            "a tab-graph leaf transition must preserve tab order"
        )
        precondition(
            affectedTab.previous.state != affectedTab.replacement.state,
            "a changed tab-graph leaf transition requires distinct states"
        )
        self.replacementTabStates = replacementTabStates
        self.affectedTab = affectedTab
        self.readWitness = readWitness
    }
}

enum WorkspaceEqualizePanesTransitionDecision: Equatable, Sendable {
    case changed(WorkspaceTabGraphLeafTransition)
    case unchanged
    case rejected(WorkspaceTabGraphLeafTransitionRejection)
}

enum WorkspaceRenameArrangementTransitionDecision: Equatable, Sendable {
    case changed(WorkspaceTabGraphLeafTransition)
    case unchanged
    case rejected(WorkspaceTabGraphLeafTransitionRejection)
}

enum WorkspaceEqualizePanesTransitionPlanner {
    static func plan(
        _ request: WorkspaceEqualizePanesRequest,
        tabStates: [TabGraphState],
        activeArrangement: WorkspaceActiveArrangementSelection
    ) -> WorkspaceEqualizePanesTransitionDecision {
        guard let tabIndex = tabStates.firstIndex(where: { $0.tabId == request.tabID }) else {
            return .rejected(.missingTab(request.tabID))
        }
        let activeArrangementID: UUID
        switch activeArrangement {
        case .missing:
            return .rejected(.missingActiveArrangement(request.tabID))
        case .selected(let arrangementID):
            activeArrangementID = arrangementID
        }
        guard
            let arrangementIndex = tabStates[tabIndex].arrangements.firstIndex(where: {
                $0.id == activeArrangementID
            })
        else {
            return .rejected(
                .missingArrangement(
                    tabID: request.tabID,
                    arrangementID: activeArrangementID
                )
            )
        }
        let previousState = tabStates[tabIndex]
        let previousLayout = previousState.arrangements[arrangementIndex].layout
        guard previousLayout.isSplit else {
            return .rejected(.tabNotSplit(request.tabID))
        }
        let replacementLayout = previousLayout.equalized()
        guard replacementLayout != previousLayout else { return .unchanged }

        var replacementState = previousState
        replacementState.arrangements[arrangementIndex].layout = replacementLayout
        return .changed(
            makeTabGraphLeafTransition(
                tabStates: tabStates,
                tabIndex: tabIndex,
                replacementState: replacementState,
                readWitness: .activeArrangement(
                    tabID: request.tabID,
                    expected: activeArrangement
                )
            )
        )
    }
}

enum WorkspaceRenameArrangementTransitionPlanner {
    static func plan(
        _ request: WorkspaceRenameArrangementRequest,
        tabStates: [TabGraphState]
    ) -> WorkspaceRenameArrangementTransitionDecision {
        guard let tabIndex = tabStates.firstIndex(where: { $0.tabId == request.tabID }) else {
            return .rejected(.missingTab(request.tabID))
        }
        guard
            let arrangementIndex = tabStates[tabIndex].arrangements.firstIndex(where: {
                $0.id == request.arrangementID
            })
        else {
            return .rejected(
                .missingArrangement(
                    tabID: request.tabID,
                    arrangementID: request.arrangementID
                )
            )
        }
        let previousState = tabStates[tabIndex]
        guard !previousState.arrangements[arrangementIndex].isDefault else {
            return .rejected(
                .defaultArrangementCannotBeRenamed(
                    tabID: request.tabID,
                    arrangementID: request.arrangementID
                )
            )
        }
        let normalizedName = Tab.normalizedName(request.name)
        guard !normalizedName.isEmpty else {
            return .rejected(.emptyArrangementName(request.arrangementID))
        }
        guard previousState.arrangements[arrangementIndex].name != normalizedName else {
            return .unchanged
        }

        var replacementState = previousState
        replacementState.arrangements[arrangementIndex].name = normalizedName
        return .changed(
            makeTabGraphLeafTransition(
                tabStates: tabStates,
                tabIndex: tabIndex,
                replacementState: replacementState,
                readWitness: .graphOnly
            )
        )
    }
}

private func makeTabGraphLeafTransition(
    tabStates: [TabGraphState],
    tabIndex: Int,
    replacementState: TabGraphState,
    readWitness: WorkspaceTabGraphLeafReadWitness
) -> WorkspaceTabGraphLeafTransition {
    let previousState = tabStates[tabIndex]
    var replacementTabStates = tabStates
    replacementTabStates[tabIndex] = replacementState
    return WorkspaceTabGraphLeafTransition(
        replacementTabStates: replacementTabStates,
        affectedTab: WorkspaceIndexedTabGraphReplacement(
            previous: WorkspaceIndexedTabGraphState(index: tabIndex, state: previousState),
            replacement: WorkspaceIndexedTabGraphState(index: tabIndex, state: replacementState)
        ),
        readWitness: readWitness
    )
}
