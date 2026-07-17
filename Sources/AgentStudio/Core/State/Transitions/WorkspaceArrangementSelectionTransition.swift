import Foundation

struct WorkspaceSetActivePaneRequest: Equatable, Sendable {
    let tabID: UUID
    let selection: WorkspacePaneSelection
}

struct WorkspaceSetActiveDrawerChildRequest: Equatable, Sendable {
    let tabID: UUID
    let drawerID: UUID
    let childPaneID: UUID
}

enum WorkspaceDrawerChildSelection: Equatable, Sendable {
    case noSelection
    case selected(UUID)
}

enum WorkspaceActiveDrawerChildCursorWitness: Equatable, Sendable {
    case missing
    case present(WorkspaceDrawerChildSelection)
}

enum WorkspaceActivePaneSelectionPlanningContext: Equatable, Sendable {
    case missingTab
    case missingActiveArrangement(tab: TabGraphState)
    case selectedActiveArrangement(
        tab: TabGraphState,
        arrangementID: UUID,
        cursor: WorkspaceActivePaneCursorWitness
    )
}

enum WorkspaceActiveDrawerChildSelectionPlanningContext: Equatable, Sendable {
    case missingTab
    case missingActiveArrangement(tab: TabGraphState)
    case selectedActiveArrangement(
        tab: TabGraphState,
        arrangementID: UUID,
        cursor: WorkspaceActiveDrawerChildCursorWitness
    )
}

enum WorkspaceActivePaneSelectionMutation: Equatable, Sendable {
    case insert(
        arrangementID: UUID,
        expected: WorkspaceActivePaneCursorWitness,
        replacement: UUID
    )
    case replace(arrangementID: UUID, previous: UUID, replacement: UUID)
    case remove(arrangementID: UUID, previous: UUID)
}

enum WorkspaceActiveDrawerChildSelectionMutation: Equatable, Sendable {
    case insert(
        key: ArrangementDrawerCursorKey,
        expected: WorkspaceActiveDrawerChildCursorWitness,
        replacement: UUID
    )
    case replace(
        key: ArrangementDrawerCursorKey,
        previous: UUID,
        replacement: UUID
    )
}

struct WorkspaceActivePaneSelectionTransition: Equatable, Sendable {
    let tabID: UUID
    let expectedTabGraph: TabGraphState
    let expectedActiveArrangement: WorkspaceActiveArrangementSelection
    let expectedCursor: WorkspaceActivePaneCursorWitness
    let mutation: WorkspaceActivePaneSelectionMutation
}

struct WorkspaceActiveDrawerChildSelectionTransition: Equatable, Sendable {
    let tabID: UUID
    let expectedTabGraph: TabGraphState
    let expectedActiveArrangement: WorkspaceActiveArrangementSelection
    let expectedCursor: WorkspaceActiveDrawerChildCursorWitness
    let mutation: WorkspaceActiveDrawerChildSelectionMutation
}

enum WorkspaceArrangementSelectionTransition: Equatable, Sendable {
    case activePane(WorkspaceActivePaneSelectionTransition)
    case activeDrawerChild(WorkspaceActiveDrawerChildSelectionTransition)
}

enum WorkspaceArrangementSelectionRejection: Equatable, Sendable {
    case missingTab(UUID)
    case missingActiveArrangement(UUID)
    case missingArrangement(tabID: UUID, arrangementID: UUID)
    case paneNotOwnedByTab(tabID: UUID, paneID: UUID)
    case paneNotInActiveMainLayout(tabID: UUID, arrangementID: UUID, paneID: UUID)
    case paneIsMinimizedInActiveMainLayout(tabID: UUID, arrangementID: UUID, paneID: UUID)
    case missingDrawer(tabID: UUID, arrangementID: UUID, drawerID: UUID)
    case drawerChildNotInActiveDrawer(
        tabID: UUID,
        arrangementID: UUID,
        drawerID: UUID,
        paneID: UUID
    )
    case drawerChildIsMinimizedInActiveDrawer(
        tabID: UUID,
        arrangementID: UUID,
        drawerID: UUID,
        paneID: UUID
    )
}

enum WorkspaceArrangementSelectionDecision: Equatable, Sendable {
    case changed(WorkspaceArrangementSelectionTransition)
    case unchanged
    case rejected(WorkspaceArrangementSelectionRejection)
}

enum WorkspaceSetActivePaneTransitionPlanner {
    static func plan(
        _ request: WorkspaceSetActivePaneRequest,
        context: WorkspaceActivePaneSelectionPlanningContext
    ) -> WorkspaceArrangementSelectionDecision {
        switch resolveActiveArrangement(tabID: request.tabID, context: context) {
        case .rejected(let rejection):
            return .rejected(rejection)
        case .resolved(let source):
            if case .selected(let paneID) = request.selection {
                guard source.tabState.allPaneIds.contains(paneID) else {
                    return .rejected(.paneNotOwnedByTab(tabID: request.tabID, paneID: paneID))
                }
                guard source.arrangement.layout.contains(paneID) else {
                    return .rejected(
                        .paneNotInActiveMainLayout(
                            tabID: request.tabID,
                            arrangementID: source.arrangement.id,
                            paneID: paneID
                        )
                    )
                }
                guard !source.arrangement.minimizedPaneIds.contains(paneID) else {
                    return .rejected(
                        .paneIsMinimizedInActiveMainLayout(
                            tabID: request.tabID,
                            arrangementID: source.arrangement.id,
                            paneID: paneID
                        )
                    )
                }
            }

            let current = source.cursor
            guard !current.matches(request.selection) else { return .unchanged }
            guard
                let mutation = activePaneMutation(
                    arrangementID: source.arrangement.id,
                    current: current,
                    replacement: request.selection
                )
            else { return .unchanged }
            return .changed(
                .activePane(
                    WorkspaceActivePaneSelectionTransition(
                        tabID: request.tabID,
                        expectedTabGraph: source.tabState,
                        expectedActiveArrangement: .selected(source.arrangement.id),
                        expectedCursor: current,
                        mutation: mutation
                    )
                )
            )
        }
    }
}

enum WorkspaceSetActiveDrawerChildTransitionPlanner {
    static func plan(
        _ request: WorkspaceSetActiveDrawerChildRequest,
        context: WorkspaceActiveDrawerChildSelectionPlanningContext
    ) -> WorkspaceArrangementSelectionDecision {
        switch resolveActiveArrangement(tabID: request.tabID, context: context) {
        case .rejected(let rejection):
            return .rejected(rejection)
        case .resolved(let source):
            guard let drawer = source.arrangement.drawerViews[request.drawerID] else {
                return .rejected(
                    .missingDrawer(
                        tabID: request.tabID,
                        arrangementID: source.arrangement.id,
                        drawerID: request.drawerID
                    )
                )
            }
            guard drawer.layout.contains(request.childPaneID) else {
                return .rejected(
                    .drawerChildNotInActiveDrawer(
                        tabID: request.tabID,
                        arrangementID: source.arrangement.id,
                        drawerID: request.drawerID,
                        paneID: request.childPaneID
                    )
                )
            }
            guard !drawer.minimizedPaneIds.contains(request.childPaneID) else {
                return .rejected(
                    .drawerChildIsMinimizedInActiveDrawer(
                        tabID: request.tabID,
                        arrangementID: source.arrangement.id,
                        drawerID: request.drawerID,
                        paneID: request.childPaneID
                    )
                )
            }

            let key = ArrangementDrawerCursorKey(
                arrangementId: source.arrangement.id,
                drawerId: request.drawerID
            )
            let current = source.cursor
            guard current != .present(.selected(request.childPaneID)) else { return .unchanged }
            let mutation: WorkspaceActiveDrawerChildSelectionMutation
            switch current {
            case .missing, .present(.noSelection):
                mutation = .insert(
                    key: key,
                    expected: current,
                    replacement: request.childPaneID
                )
            case .present(.selected(let previous)):
                mutation = .replace(
                    key: key,
                    previous: previous,
                    replacement: request.childPaneID
                )
            }
            return .changed(
                .activeDrawerChild(
                    WorkspaceActiveDrawerChildSelectionTransition(
                        tabID: request.tabID,
                        expectedTabGraph: source.tabState,
                        expectedActiveArrangement: .selected(source.arrangement.id),
                        expectedCursor: current,
                        mutation: mutation
                    )
                )
            )
        }
    }
}

private struct WorkspaceResolvedActivePaneSelectionArrangement {
    let tabState: TabGraphState
    let arrangement: PaneArrangementGraphState
    let cursor: WorkspaceActivePaneCursorWitness
}

private enum WorkspaceActivePaneSelectionArrangementResolution {
    case resolved(WorkspaceResolvedActivePaneSelectionArrangement)
    case rejected(WorkspaceArrangementSelectionRejection)
}

private func resolveActiveArrangement(
    tabID: UUID,
    context: WorkspaceActivePaneSelectionPlanningContext
) -> WorkspaceActivePaneSelectionArrangementResolution {
    let tabState: TabGraphState
    let arrangementID: UUID
    let cursor: WorkspaceActivePaneCursorWitness
    switch context {
    case .missingTab:
        return .rejected(.missingTab(tabID))
    case .missingActiveArrangement(let tab):
        return .rejected(.missingActiveArrangement(tab.tabId))
    case .selectedActiveArrangement(let tab, let selectedArrangementID, let selectedCursor):
        tabState = tab
        arrangementID = selectedArrangementID
        cursor = selectedCursor
    }
    guard tabState.tabId == tabID else {
        return .rejected(.missingTab(tabID))
    }
    guard let arrangement = tabState.arrangements.first(where: { $0.id == arrangementID }) else {
        return .rejected(.missingArrangement(tabID: tabID, arrangementID: arrangementID))
    }
    return .resolved(.init(tabState: tabState, arrangement: arrangement, cursor: cursor))
}

private struct ResolvedDrawerSelectionArrangement {
    let tabState: TabGraphState
    let arrangement: PaneArrangementGraphState
    let cursor: WorkspaceActiveDrawerChildCursorWitness
}

private enum DrawerSelectionArrangementResolution {
    case resolved(ResolvedDrawerSelectionArrangement)
    case rejected(WorkspaceArrangementSelectionRejection)
}

private func resolveActiveArrangement(
    tabID: UUID,
    context: WorkspaceActiveDrawerChildSelectionPlanningContext
) -> DrawerSelectionArrangementResolution {
    let tabState: TabGraphState
    let arrangementID: UUID
    let cursor: WorkspaceActiveDrawerChildCursorWitness
    switch context {
    case .missingTab:
        return .rejected(.missingTab(tabID))
    case .missingActiveArrangement(let tab):
        return .rejected(.missingActiveArrangement(tab.tabId))
    case .selectedActiveArrangement(let tab, let selectedArrangementID, let selectedCursor):
        tabState = tab
        arrangementID = selectedArrangementID
        cursor = selectedCursor
    }
    guard tabState.tabId == tabID else {
        return .rejected(.missingTab(tabID))
    }
    guard let arrangement = tabState.arrangements.first(where: { $0.id == arrangementID }) else {
        return .rejected(.missingArrangement(tabID: tabID, arrangementID: arrangementID))
    }
    return .resolved(
        .init(
            tabState: tabState,
            arrangement: arrangement,
            cursor: cursor
        )
    )
}

private func activePaneMutation(
    arrangementID: UUID,
    current: WorkspaceActivePaneCursorWitness,
    replacement: WorkspacePaneSelection
) -> WorkspaceActivePaneSelectionMutation? {
    switch (current, replacement) {
    case (.missing, .noSelection), (.present(.noSelection), .noSelection):
        nil
    case (.missing, .selected(let paneID)), (.present(.noSelection), .selected(let paneID)):
        .insert(arrangementID: arrangementID, expected: current, replacement: paneID)
    case (.present(.selected(let previous)), .selected(let replacement)):
        .replace(arrangementID: arrangementID, previous: previous, replacement: replacement)
    case (.present(.selected(let previous)), .noSelection):
        .remove(arrangementID: arrangementID, previous: previous)
    }
}

extension WorkspaceActivePaneCursorWitness {
    fileprivate func matches(_ selection: WorkspacePaneSelection) -> Bool {
        switch (self, selection) {
        case (.missing, .noSelection), (.present(.noSelection), .noSelection):
            true
        case (.present(.selected(let current)), .selected(let requested)):
            current == requested
        default:
            false
        }
    }
}
