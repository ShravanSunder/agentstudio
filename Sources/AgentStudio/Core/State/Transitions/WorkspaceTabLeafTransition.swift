import Foundation

struct WorkspaceTabLeafPlanningContext: Equatable, Sendable {
    let tabShells: [TabShell]
    let activeTab: WorkspaceTabCursorSelection
}

struct WorkspaceSelectTabRequest: Equatable, Sendable {
    let tabID: UUID
}

struct WorkspaceRenameTabRequest: Equatable, Sendable {
    let tabID: UUID
    let name: String
}

struct WorkspaceMoveTabByDeltaRequest: Equatable, Sendable {
    let tabID: UUID
    let delta: Int
}

struct WorkspaceReorderAndSelectTabRequest: Equatable, Sendable {
    let tabID: UUID
    let toIndex: Int
}

enum WorkspaceTabLeafTransitionRejection: Equatable, Sendable {
    case duplicateTab(UUID)
    case emptyTabName(UUID)
    case invalidActiveTab(UUID)
    case invalidReorderIndex(Int)
    case missingTab(UUID)
}

struct WorkspaceIndexedTabShell: Equatable, Sendable {
    let index: Int
    let shell: TabShell
}

struct WorkspaceIndexedTabShellReplacement: Equatable, Sendable {
    let previous: WorkspaceIndexedTabShell
    let replacement: WorkspaceIndexedTabShell
}

struct WorkspaceTabShellCollectionTransition: Equatable, Sendable {
    let replacementTabShells: [TabShell]
    let affectedShells: [WorkspaceIndexedTabShellReplacement]

    fileprivate init(
        replacementTabShells: [TabShell],
        affectedShells: [WorkspaceIndexedTabShellReplacement]
    ) {
        precondition(!affectedShells.isEmpty, "a changed tab-shell transition requires affected shells")
        self.replacementTabShells = replacementTabShells
        self.affectedShells = affectedShells
    }
}

struct WorkspaceTabCursorReplacement: Equatable, Sendable {
    let previous: WorkspaceTabCursorSelection
    let replacement: WorkspaceTabCursorSelection

    init(
        previous: WorkspaceTabCursorSelection,
        replacement: WorkspaceTabCursorSelection
    ) {
        precondition(previous != replacement, "a changed tab-cursor transition requires distinct selections")
        self.previous = previous
        self.replacement = replacement
    }
}

enum WorkspaceSelectTabTransitionDecision: Equatable, Sendable {
    case changed(WorkspaceTabCursorReplacement)
    case unchanged
    case rejected(WorkspaceTabLeafTransitionRejection)
}

enum WorkspaceRenameTabTransitionDecision: Equatable, Sendable {
    case changed(WorkspaceTabShellCollectionTransition)
    case unchanged
    case rejected(WorkspaceTabLeafTransitionRejection)
}

enum WorkspaceMoveTabByDeltaTransitionDecision: Equatable, Sendable {
    case changed(WorkspaceTabShellCollectionTransition)
    case unchanged
    case rejected(WorkspaceTabLeafTransitionRejection)
}

enum WorkspaceReorderAndSelectTabTransition: Equatable, Sendable {
    case shellOnly(WorkspaceTabShellCollectionTransition)
    case cursorOnly(WorkspaceTabCursorReplacement)
    case shellAndCursor(WorkspaceTabShellCollectionTransition, WorkspaceTabCursorReplacement)
}

enum WorkspaceReorderAndSelectTabTransitionDecision: Equatable, Sendable {
    case changed(WorkspaceReorderAndSelectTabTransition)
    case unchanged
    case rejected(WorkspaceTabLeafTransitionRejection)
}

enum WorkspaceSelectTabTransitionPlanner {
    static func plan(
        _ request: WorkspaceSelectTabRequest,
        context: WorkspaceTabLeafPlanningContext
    ) -> WorkspaceSelectTabTransitionDecision {
        if let rejection = WorkspaceTabLeafContextValidator.validate(context) {
            return .rejected(rejection)
        }
        guard context.tabShells.contains(where: { $0.id == request.tabID }) else {
            return .rejected(.missingTab(request.tabID))
        }
        let requestedSelection = WorkspaceTabCursorSelection.selected(request.tabID)
        guard context.activeTab != requestedSelection else { return .unchanged }
        return .changed(
            WorkspaceTabCursorReplacement(
                previous: context.activeTab,
                replacement: requestedSelection
            )
        )
    }
}

enum WorkspaceRenameTabTransitionPlanner {
    static func plan(
        _ request: WorkspaceRenameTabRequest,
        context: WorkspaceTabLeafPlanningContext
    ) -> WorkspaceRenameTabTransitionDecision {
        if let rejection = WorkspaceTabLeafContextValidator.validate(context) {
            return .rejected(rejection)
        }
        guard let tabIndex = context.tabShells.firstIndex(where: { $0.id == request.tabID }) else {
            return .rejected(.missingTab(request.tabID))
        }
        let normalizedName = Tab.normalizedName(request.name)
        guard !normalizedName.isEmpty else { return .rejected(.emptyTabName(request.tabID)) }
        let previousShell = context.tabShells[tabIndex]
        guard previousShell.name != normalizedName else { return .unchanged }

        var replacementShell = previousShell
        replacementShell.rename(to: normalizedName)
        var replacementTabShells = context.tabShells
        replacementTabShells[tabIndex] = replacementShell
        return .changed(
            WorkspaceTabShellCollectionTransition(
                replacementTabShells: replacementTabShells,
                affectedShells: [
                    WorkspaceIndexedTabShellReplacement(
                        previous: WorkspaceIndexedTabShell(index: tabIndex, shell: previousShell),
                        replacement: WorkspaceIndexedTabShell(index: tabIndex, shell: replacementShell)
                    )
                ]
            )
        )
    }
}

enum WorkspaceMoveTabByDeltaTransitionPlanner {
    static func plan(
        _ request: WorkspaceMoveTabByDeltaRequest,
        context: WorkspaceTabLeafPlanningContext
    ) -> WorkspaceMoveTabByDeltaTransitionDecision {
        if let rejection = WorkspaceTabLeafContextValidator.validate(context) {
            return .rejected(rejection)
        }
        guard let currentIndex = context.tabShells.firstIndex(where: { $0.id == request.tabID }) else {
            return .rejected(.missingTab(request.tabID))
        }
        guard context.tabShells.count > 1 else { return .unchanged }

        let finalIndex: Int
        if request.delta < 0 {
            let magnitude = request.delta == Int.min ? Int.max : -request.delta
            finalIndex = currentIndex - min(currentIndex, magnitude)
        } else {
            let remainingCount = context.tabShells.count - 1 - currentIndex
            finalIndex = currentIndex + min(remainingCount, request.delta)
        }
        guard finalIndex != currentIndex else { return .unchanged }
        return .changed(
            WorkspaceTabShellMovementPlanner.transition(
                tabShells: context.tabShells,
                fromIndex: currentIndex,
                toFinalIndex: finalIndex
            )
        )
    }
}

enum WorkspaceReorderAndSelectTabTransitionPlanner {
    static func plan(
        _ request: WorkspaceReorderAndSelectTabRequest,
        context: WorkspaceTabLeafPlanningContext
    ) -> WorkspaceReorderAndSelectTabTransitionDecision {
        if let rejection = WorkspaceTabLeafContextValidator.validate(context) {
            return .rejected(rejection)
        }
        guard let currentIndex = context.tabShells.firstIndex(where: { $0.id == request.tabID }) else {
            return .rejected(.missingTab(request.tabID))
        }
        guard context.tabShells.indices.contains(request.toIndex) else {
            return .rejected(.invalidReorderIndex(request.toIndex))
        }

        let adjustedIndex = request.toIndex > currentIndex ? request.toIndex - 1 : request.toIndex
        let requestedSelection = WorkspaceTabCursorSelection.selected(request.tabID)
        let cursorChanged = context.activeTab != requestedSelection
        let shellsChanged = adjustedIndex != currentIndex

        switch (shellsChanged, cursorChanged) {
        case (false, false):
            return .unchanged
        case (false, true):
            return .changed(
                .cursorOnly(
                    WorkspaceTabCursorReplacement(
                        previous: context.activeTab,
                        replacement: requestedSelection
                    )
                )
            )
        case (true, false):
            return .changed(
                .shellOnly(
                    WorkspaceTabShellMovementPlanner.transition(
                        tabShells: context.tabShells,
                        fromIndex: currentIndex,
                        toFinalIndex: adjustedIndex
                    )
                )
            )
        case (true, true):
            return .changed(
                .shellAndCursor(
                    WorkspaceTabShellMovementPlanner.transition(
                        tabShells: context.tabShells,
                        fromIndex: currentIndex,
                        toFinalIndex: adjustedIndex
                    ),
                    WorkspaceTabCursorReplacement(
                        previous: context.activeTab,
                        replacement: requestedSelection
                    )
                )
            )
        }
    }
}

private enum WorkspaceTabLeafContextValidator {
    static func validate(
        _ context: WorkspaceTabLeafPlanningContext
    ) -> WorkspaceTabLeafTransitionRejection? {
        var seenTabIDs: Set<UUID> = []
        for shell in context.tabShells where !seenTabIDs.insert(shell.id).inserted {
            return .duplicateTab(shell.id)
        }
        if case .selected(let activeTabID) = context.activeTab,
            !seenTabIDs.contains(activeTabID)
        {
            return .invalidActiveTab(activeTabID)
        }
        return nil
    }
}

private enum WorkspaceTabShellMovementPlanner {
    static func transition(
        tabShells: [TabShell],
        fromIndex: Int,
        toFinalIndex: Int
    ) -> WorkspaceTabShellCollectionTransition {
        var replacementTabShells = tabShells
        let movedShell = replacementTabShells.remove(at: fromIndex)
        replacementTabShells.insert(movedShell, at: toFinalIndex)

        let affectedIndexRange = min(fromIndex, toFinalIndex)...max(fromIndex, toFinalIndex)
        let replacementIndexByTabID = Dictionary(
            uniqueKeysWithValues: replacementTabShells.enumerated().map { ($0.element.id, $0.offset) }
        )
        let affectedShells = affectedIndexRange.map { previousIndex in
            let shell = tabShells[previousIndex]
            guard let replacementIndex = replacementIndexByTabID[shell.id] else {
                preconditionFailure("moved tab shell must remain in the replacement collection")
            }
            return WorkspaceIndexedTabShellReplacement(
                previous: WorkspaceIndexedTabShell(index: previousIndex, shell: shell),
                replacement: WorkspaceIndexedTabShell(index: replacementIndex, shell: shell)
            )
        }
        return WorkspaceTabShellCollectionTransition(
            replacementTabShells: replacementTabShells,
            affectedShells: affectedShells
        )
    }
}
