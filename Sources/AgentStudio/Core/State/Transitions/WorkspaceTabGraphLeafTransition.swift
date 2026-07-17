import Foundation

enum WorkspaceActiveArrangementSelection: Equatable, Sendable {
    case missing
    case selected(UUID)
}

struct WorkspaceEqualizePanesRequest: Equatable, Sendable {
    let tabID: UUID
}

struct WorkspaceEqualizeDrawerPanesRequest: Equatable, Sendable {
    let tabID: UUID
    let drawerID: UUID
}

struct WorkspaceRenameArrangementRequest: Equatable, Sendable {
    let tabID: UUID
    let arrangementID: UUID
    let name: String
}

enum WorkspaceTabGraphLeafPlanningContext: Equatable, Sendable {
    case missingTab
    case present(TabGraphState)
}

enum WorkspaceTabGraphLeafTransitionRejection: Error, Equatable, Sendable {
    case defaultArrangementCannotBeRenamed(tabID: UUID, arrangementID: UUID)
    case drawerNotSplit(tabID: UUID, arrangementID: UUID, drawerID: UUID)
    case emptyArrangementName(UUID)
    case missingActiveArrangement(UUID)
    case missingArrangement(tabID: UUID, arrangementID: UUID)
    case missingDrawer(tabID: UUID, arrangementID: UUID, drawerID: UUID)
    case missingTab(UUID)
    case tabIdentityMismatch(requested: UUID, actual: UUID)
    case tabNotSplit(UUID)
}

enum WorkspaceTabGraphLeafReadWitness: Equatable, Sendable {
    case graphOnly
    case activeArrangement(tabID: UUID, expected: WorkspaceActiveArrangementSelection)
}

// Pane-residency lifecycle transitions retain tab order while removing or
// restoring whole tab ownership. The leaf family below intentionally does not
// use this ordering witness.
struct WorkspaceIndexedTabGraphState: Equatable, Sendable {
    let index: Int
    let state: TabGraphState
}

struct WorkspaceTabGraphLeafTransition: Equatable, Sendable {
    let previousTab: TabGraphState
    let replacementTab: TabGraphState
    let readWitness: WorkspaceTabGraphLeafReadWitness

    fileprivate init(
        previousTab: TabGraphState,
        replacementTab: TabGraphState,
        readWitness: WorkspaceTabGraphLeafReadWitness
    ) {
        precondition(
            previousTab.tabId == replacementTab.tabId,
            "a tab-graph leaf transition must preserve tab identity"
        )
        precondition(
            previousTab != replacementTab,
            "a changed tab-graph leaf transition requires distinct states"
        )
        self.previousTab = previousTab
        self.replacementTab = replacementTab
        self.readWitness = readWitness
    }
}

enum WorkspaceEqualizePanesTransitionDecision: Equatable, Sendable {
    case changed(WorkspaceTabGraphLeafTransition)
    case unchanged
    case rejected(WorkspaceTabGraphLeafTransitionRejection)
}

enum WorkspaceEqualizeDrawerPanesTransitionDecision: Equatable, Sendable {
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
        context: WorkspaceTabGraphLeafPlanningContext,
        activeArrangement: WorkspaceActiveArrangementSelection
    ) -> WorkspaceEqualizePanesTransitionDecision {
        let tab: TabGraphState
        switch resolveTab(requestedTabID: request.tabID, context: context) {
        case .success(let resolved): tab = resolved
        case .failure(let rejection): return .rejected(rejection)
        }
        let arrangementIndex: Int
        switch resolveActiveArrangement(tab: tab, selection: activeArrangement) {
        case .success(let resolved): arrangementIndex = resolved
        case .failure(let rejection): return .rejected(rejection)
        }
        let previousLayout = tab.arrangements[arrangementIndex].layout
        guard previousLayout.isSplit else {
            return .rejected(.tabNotSplit(request.tabID))
        }
        let replacementLayout = previousLayout.equalized()
        guard replacementLayout != previousLayout else { return .unchanged }

        var replacement = tab
        replacement.arrangements[arrangementIndex].layout = replacementLayout
        return .changed(
            makeTabGraphLeafTransition(
                previousTab: tab,
                replacementTab: replacement,
                readWitness: .activeArrangement(tabID: request.tabID, expected: activeArrangement)
            )
        )
    }
}

enum WorkspaceEqualizeDrawerPanesTransitionPlanner {
    static func plan(
        _ request: WorkspaceEqualizeDrawerPanesRequest,
        context: WorkspaceTabGraphLeafPlanningContext,
        activeArrangement: WorkspaceActiveArrangementSelection
    ) -> WorkspaceEqualizeDrawerPanesTransitionDecision {
        let tab: TabGraphState
        switch resolveTab(requestedTabID: request.tabID, context: context) {
        case .success(let resolved): tab = resolved
        case .failure(let rejection): return .rejected(rejection)
        }
        let arrangementIndex: Int
        switch resolveActiveArrangement(tab: tab, selection: activeArrangement) {
        case .success(let resolved): arrangementIndex = resolved
        case .failure(let rejection): return .rejected(rejection)
        }
        let arrangementID = tab.arrangements[arrangementIndex].id
        guard let drawer = tab.arrangements[arrangementIndex].drawerViews[request.drawerID] else {
            return .rejected(
                .missingDrawer(
                    tabID: request.tabID,
                    arrangementID: arrangementID,
                    drawerID: request.drawerID
                )
            )
        }
        guard drawer.layout.paneIds.count > 1 else {
            return .rejected(
                .drawerNotSplit(
                    tabID: request.tabID,
                    arrangementID: arrangementID,
                    drawerID: request.drawerID
                )
            )
        }
        let replacementLayout = drawer.layout.equalized()
        guard replacementLayout != drawer.layout else { return .unchanged }

        var replacementDrawer = drawer
        replacementDrawer.layout = replacementLayout
        var replacement = tab
        replacement.arrangements[arrangementIndex].drawerViews[request.drawerID] = replacementDrawer
        return .changed(
            makeTabGraphLeafTransition(
                previousTab: tab,
                replacementTab: replacement,
                readWitness: .activeArrangement(tabID: request.tabID, expected: activeArrangement)
            )
        )
    }
}

enum WorkspaceRenameArrangementTransitionPlanner {
    static func plan(
        _ request: WorkspaceRenameArrangementRequest,
        context: WorkspaceTabGraphLeafPlanningContext
    ) -> WorkspaceRenameArrangementTransitionDecision {
        let tab: TabGraphState
        switch resolveTab(requestedTabID: request.tabID, context: context) {
        case .success(let resolved): tab = resolved
        case .failure(let rejection): return .rejected(rejection)
        }
        guard let arrangementIndex = tab.arrangements.firstIndex(where: { $0.id == request.arrangementID }) else {
            return .rejected(
                .missingArrangement(tabID: request.tabID, arrangementID: request.arrangementID)
            )
        }
        guard !tab.arrangements[arrangementIndex].isDefault else {
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
        guard tab.arrangements[arrangementIndex].name != normalizedName else {
            return .unchanged
        }

        var replacement = tab
        replacement.arrangements[arrangementIndex].name = normalizedName
        return .changed(
            makeTabGraphLeafTransition(
                previousTab: tab,
                replacementTab: replacement,
                readWitness: .graphOnly
            )
        )
    }
}

private func resolveTab(
    requestedTabID: UUID,
    context: WorkspaceTabGraphLeafPlanningContext
) -> Result<TabGraphState, WorkspaceTabGraphLeafTransitionRejection> {
    switch context {
    case .missingTab:
        return .failure(.missingTab(requestedTabID))
    case .present(let tab):
        guard tab.tabId == requestedTabID else {
            return .failure(.tabIdentityMismatch(requested: requestedTabID, actual: tab.tabId))
        }
        return .success(tab)
    }
}

private func resolveActiveArrangement(
    tab: TabGraphState,
    selection: WorkspaceActiveArrangementSelection
) -> Result<Int, WorkspaceTabGraphLeafTransitionRejection> {
    let arrangementID: UUID
    switch selection {
    case .missing:
        return .failure(.missingActiveArrangement(tab.tabId))
    case .selected(let selectedArrangementID):
        arrangementID = selectedArrangementID
    }
    guard let index = tab.arrangements.firstIndex(where: { $0.id == arrangementID }) else {
        return .failure(.missingArrangement(tabID: tab.tabId, arrangementID: arrangementID))
    }
    return .success(index)
}

private func makeTabGraphLeafTransition(
    previousTab: TabGraphState,
    replacementTab: TabGraphState,
    readWitness: WorkspaceTabGraphLeafReadWitness
) -> WorkspaceTabGraphLeafTransition {
    WorkspaceTabGraphLeafTransition(
        previousTab: previousTab,
        replacementTab: replacementTab,
        readWitness: readWitness
    )
}
