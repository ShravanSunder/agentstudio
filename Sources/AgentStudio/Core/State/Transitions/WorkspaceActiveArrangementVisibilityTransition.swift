import Foundation

struct WorkspaceSwitchArrangementRequest: Equatable, Sendable {
    let tabID: UUID
    let arrangementID: UUID
}

struct WorkspaceSetShowsMinimizedPanesRequest: Equatable, Sendable {
    let tabID: UUID
    let showsMinimizedPanes: Bool
}

struct WorkspaceMinimizePaneRequest: Equatable, Sendable {
    let tabID: UUID
    let paneID: UUID
}

struct WorkspaceExpandPaneRequest: Equatable, Sendable {
    let tabID: UUID
    let paneID: UUID
}

enum WorkspacePaneSelection: Equatable, Sendable {
    case noSelection
    case selected(UUID)
}

enum WorkspaceActivePaneCursorWitness: Equatable, Sendable {
    case missing
    case present(WorkspacePaneSelection)
}

enum WorkspaceZoomSelection: Equatable, Sendable {
    case notZoomed
    case zoomed(UUID)
}

enum WorkspaceTabGraphStateWitness: Equatable, Sendable {
    case missing
    case present(TabGraphState)
}

enum WorkspaceActiveArrangementPaneCursorWitness: Equatable, Sendable {
    case missing
    case selected(
        arrangementID: UUID,
        paneCursor: WorkspaceActivePaneCursorWitness
    )
}

struct WorkspaceSwitchArrangementPlanningContext: Equatable, Sendable {
    let tab: WorkspaceTabGraphStateWitness
    let activeArrangement: WorkspaceActiveArrangementSelection
    let targetPaneCursor: WorkspaceActivePaneCursorWitness
    let zoom: WorkspaceZoomSelection
}

struct WorkspaceSetShowsMinimizedPanesPlanningContext: Equatable, Sendable {
    let tab: WorkspaceTabGraphStateWitness
    let activeArrangement: WorkspaceActiveArrangementSelection
}

struct WorkspaceMinimizePanePlanningContext: Equatable, Sendable {
    let tab: WorkspaceTabGraphStateWitness
    let activeArrangementPaneCursor: WorkspaceActiveArrangementPaneCursorWitness
    let zoom: WorkspaceZoomSelection
}

struct WorkspaceExpandPanePlanningContext: Equatable, Sendable {
    let tab: WorkspaceTabGraphStateWitness
    let activeArrangementPaneCursor: WorkspaceActiveArrangementPaneCursorWitness
}

struct WorkspaceArrangementPresentationSnapshot: Equatable, Sendable {
    let layoutPaneIDs: [UUID]
    let minimizedPaneIDs: Set<UUID>
    let showsMinimizedPanes: Bool

    init(
        layoutPaneIDs: [UUID],
        minimizedPaneIDs: Set<UUID>,
        showsMinimizedPanes: Bool
    ) {
        self.layoutPaneIDs = layoutPaneIDs
        self.minimizedPaneIDs = minimizedPaneIDs
        self.showsMinimizedPanes = showsMinimizedPanes
    }

    init(_ arrangement: PaneArrangementGraphState) {
        self.init(
            layoutPaneIDs: arrangement.layout.paneIds,
            minimizedPaneIDs: arrangement.minimizedPaneIds,
            showsMinimizedPanes: arrangement.showsMinimizedPanes
        )
    }
}

enum WorkspaceActiveArrangementVisibilityEffect: Equatable, Sendable {
    case switchArrangement(
        previous: WorkspaceArrangementPresentationSnapshot,
        replacement: WorkspaceArrangementPresentationSnapshot
    )
    case setShowsMinimizedPanes(
        previous: WorkspaceArrangementPresentationSnapshot,
        replacement: WorkspaceArrangementPresentationSnapshot
    )
    case minimizePane(paneID: UUID)
    case expandPane(paneID: UUID)
}

enum WorkspaceVisibilityTabGraphTransition: Equatable, Sendable {
    case witness(tabID: UUID, expected: TabGraphState)
    case replace(tabID: UUID, previous: TabGraphState, replacement: TabGraphState)
}

enum WorkspaceVisibilityActiveArrangementTransition: Equatable, Sendable {
    case witness(tabID: UUID, expected: WorkspaceActiveArrangementSelection)
    case insert(tabID: UUID, replacement: UUID)
    case replace(tabID: UUID, previous: UUID, replacement: UUID)
}

enum WorkspaceVisibilityActivePaneTransition: Equatable, Sendable {
    case notRead
    case witness(arrangementID: UUID, expected: WorkspaceActivePaneCursorWitness)
    case insert(
        arrangementID: UUID,
        expected: WorkspaceActivePaneCursorWitness,
        replacement: UUID
    )
    case replace(arrangementID: UUID, previous: UUID, replacement: UUID)
    case remove(arrangementID: UUID, previous: UUID)
}

enum WorkspaceVisibilityZoomTransition: Equatable, Sendable {
    case notRead
    case witness(tabID: UUID, expected: WorkspaceZoomSelection)
    case clear(tabID: UUID, previous: UUID)
}

struct WorkspaceActiveArrangementVisibilityTransition: Equatable, Sendable {
    let tabGraph: WorkspaceVisibilityTabGraphTransition
    let activeArrangement: WorkspaceVisibilityActiveArrangementTransition
    let activePane: WorkspaceVisibilityActivePaneTransition
    let zoom: WorkspaceVisibilityZoomTransition
    let effect: WorkspaceActiveArrangementVisibilityEffect
}

enum WorkspaceActiveArrangementVisibilityRejection: Equatable, Sendable {
    case missingTab(UUID)
    case missingActiveArrangement(UUID)
    case missingArrangement(tabID: UUID, arrangementID: UUID)
    case paneNotOwnedByTab(tabID: UUID, paneID: UUID)
    case paneNotInActiveArrangement(tabID: UUID, arrangementID: UUID, paneID: UUID)
}

enum WorkspaceVisibilityTransitionDecision: Equatable, Sendable {
    case changed(WorkspaceActiveArrangementVisibilityTransition)
    case unchanged
    case rejected(WorkspaceActiveArrangementVisibilityRejection)
}

enum WorkspaceSwitchArrangementTransitionPlanner {
    static func plan(
        _ request: WorkspaceSwitchArrangementRequest,
        context: WorkspaceSwitchArrangementPlanningContext
    ) -> WorkspaceVisibilityTransitionDecision {
        guard case .present(let tabState) = context.tab, tabState.tabId == request.tabID else {
            return .rejected(.missingTab(request.tabID))
        }
        guard let targetArrangement = tabState.arrangements.first(where: { $0.id == request.arrangementID }) else {
            return .rejected(
                .missingArrangement(tabID: request.tabID, arrangementID: request.arrangementID)
            )
        }
        guard context.activeArrangement != .selected(request.arrangementID) else { return .unchanged }
        let previousArrangement = resolvedCurrentArrangement(
            tabState: tabState,
            activeArrangement: context.activeArrangement
        )
        let activeArrangementTransition: WorkspaceVisibilityActiveArrangementTransition
        switch context.activeArrangement {
        case .missing:
            activeArrangementTransition = .insert(
                tabID: request.tabID,
                replacement: request.arrangementID
            )
        case .selected(let previousArrangementID):
            activeArrangementTransition = .replace(
                tabID: request.tabID,
                previous: previousArrangementID,
                replacement: request.arrangementID
            )
        }
        let desiredPaneSelection = fallbackPaneSelection(
            current: context.targetPaneCursor,
            arrangement: targetArrangement
        )
        return .changed(
            WorkspaceActiveArrangementVisibilityTransition(
                tabGraph: .witness(tabID: request.tabID, expected: tabState),
                activeArrangement: activeArrangementTransition,
                activePane: activePaneTransition(
                    arrangementID: request.arrangementID,
                    current: context.targetPaneCursor,
                    desired: desiredPaneSelection
                ),
                zoom: zoomTransition(tabID: request.tabID, selection: context.zoom),
                effect: .switchArrangement(
                    previous: WorkspaceArrangementPresentationSnapshot(previousArrangement),
                    replacement: WorkspaceArrangementPresentationSnapshot(targetArrangement)
                )
            )
        )
    }
}

enum WorkspaceSetShowsMinimizedPanesTransitionPlanner {
    static func plan(
        _ request: WorkspaceSetShowsMinimizedPanesRequest,
        context: WorkspaceSetShowsMinimizedPanesPlanningContext
    ) -> WorkspaceVisibilityTransitionDecision {
        switch resolveActiveArrangement(
            tabID: request.tabID,
            tab: context.tab,
            activeArrangement: context.activeArrangement
        ) {
        case .rejected(let rejection):
            return .rejected(rejection)
        case .resolved(let source):
            guard source.arrangement.showsMinimizedPanes != request.showsMinimizedPanes else {
                return .unchanged
            }
            var replacementTab = source.tabState
            replacementTab.arrangements[source.arrangementIndex].showsMinimizedPanes =
                request.showsMinimizedPanes
            return .changed(
                WorkspaceActiveArrangementVisibilityTransition(
                    tabGraph: .replace(
                        tabID: request.tabID,
                        previous: source.tabState,
                        replacement: replacementTab
                    ),
                    activeArrangement: .witness(
                        tabID: request.tabID,
                        expected: .selected(source.arrangement.id)
                    ),
                    activePane: .notRead,
                    zoom: .notRead,
                    effect: .setShowsMinimizedPanes(
                        previous: WorkspaceArrangementPresentationSnapshot(source.arrangement),
                        replacement: WorkspaceArrangementPresentationSnapshot(
                            replacementTab.arrangements[source.arrangementIndex]
                        )
                    )
                )
            )
        }
    }
}

enum WorkspaceMinimizePaneTransitionPlanner {
    static func plan(
        _ request: WorkspaceMinimizePaneRequest,
        context: WorkspaceMinimizePanePlanningContext
    ) -> WorkspaceVisibilityTransitionDecision {
        switch resolvePaneInActiveArrangement(
            tabID: request.tabID,
            paneID: request.paneID,
            tab: context.tab,
            activeArrangementPaneCursor: context.activeArrangementPaneCursor
        ) {
        case .rejected(let rejection):
            return .rejected(rejection)
        case .resolved(let source):
            guard !source.arrangement.minimizedPaneIds.contains(request.paneID) else {
                return .unchanged
            }
            var replacementTab = source.tabState
            replacementTab.arrangements[source.arrangementIndex].minimizedPaneIds.insert(request.paneID)
            let currentPaneWitness = source.paneCursor
            let paneTransition: WorkspaceVisibilityActivePaneTransition
            if currentPaneWitness == .present(.selected(request.paneID)) {
                paneTransition = activePaneTransition(
                    arrangementID: source.arrangement.id,
                    current: currentPaneWitness,
                    desired: firstUnminimizedPaneSelection(
                        replacementTab.arrangements[source.arrangementIndex]
                    )
                )
            } else {
                paneTransition = .witness(
                    arrangementID: source.arrangement.id,
                    expected: currentPaneWitness
                )
            }
            return .changed(
                WorkspaceActiveArrangementVisibilityTransition(
                    tabGraph: .replace(
                        tabID: request.tabID,
                        previous: source.tabState,
                        replacement: replacementTab
                    ),
                    activeArrangement: .witness(
                        tabID: request.tabID,
                        expected: .selected(source.arrangement.id)
                    ),
                    activePane: paneTransition,
                    zoom: zoomTransition(
                        tabID: request.tabID,
                        clearingPaneID: request.paneID,
                        selection: context.zoom
                    ),
                    effect: .minimizePane(paneID: request.paneID)
                )
            )
        }
    }
}

enum WorkspaceExpandPaneTransitionPlanner {
    static func plan(
        _ request: WorkspaceExpandPaneRequest,
        context: WorkspaceExpandPanePlanningContext
    ) -> WorkspaceVisibilityTransitionDecision {
        switch resolvePaneInActiveArrangement(
            tabID: request.tabID,
            paneID: request.paneID,
            tab: context.tab,
            activeArrangementPaneCursor: context.activeArrangementPaneCursor
        ) {
        case .rejected(let rejection):
            return .rejected(rejection)
        case .resolved(let source):
            guard source.arrangement.minimizedPaneIds.contains(request.paneID) else {
                return .unchanged
            }
            var replacementTab = source.tabState
            replacementTab.arrangements[source.arrangementIndex].minimizedPaneIds.remove(request.paneID)
            let currentPaneWitness = source.paneCursor
            return .changed(
                WorkspaceActiveArrangementVisibilityTransition(
                    tabGraph: .replace(
                        tabID: request.tabID,
                        previous: source.tabState,
                        replacement: replacementTab
                    ),
                    activeArrangement: .witness(
                        tabID: request.tabID,
                        expected: .selected(source.arrangement.id)
                    ),
                    activePane: activePaneTransition(
                        arrangementID: source.arrangement.id,
                        current: currentPaneWitness,
                        desired: .selected(request.paneID)
                    ),
                    zoom: .notRead,
                    effect: .expandPane(paneID: request.paneID)
                )
            )
        }
    }
}

private struct ResolvedActiveArrangement {
    let tabState: TabGraphState
    let arrangementIndex: Int
    let arrangement: PaneArrangementGraphState
}

private struct ResolvedActiveArrangementWithPaneCursor {
    let source: ResolvedActiveArrangement
    let paneCursor: WorkspaceActivePaneCursorWitness

    var tabState: TabGraphState { source.tabState }
    var arrangementIndex: Int { source.arrangementIndex }
    var arrangement: PaneArrangementGraphState { source.arrangement }
}

private enum ActiveArrangementResolution {
    case resolved(ResolvedActiveArrangement)
    case rejected(WorkspaceActiveArrangementVisibilityRejection)
}

private enum ActiveArrangementWithPaneCursorResolution {
    case resolved(ResolvedActiveArrangementWithPaneCursor)
    case rejected(WorkspaceActiveArrangementVisibilityRejection)
}

private func resolveActiveArrangement(
    tabID: UUID,
    tab: WorkspaceTabGraphStateWitness,
    activeArrangement: WorkspaceActiveArrangementSelection
) -> ActiveArrangementResolution {
    guard case .present(let tabState) = tab, tabState.tabId == tabID else {
        return .rejected(.missingTab(tabID))
    }
    guard case .selected(let activeArrangementID) = activeArrangement else {
        return .rejected(.missingActiveArrangement(tabID))
    }
    guard let arrangementIndex = tabState.arrangements.firstIndex(where: { $0.id == activeArrangementID }) else {
        return .rejected(
            .missingArrangement(tabID: tabID, arrangementID: activeArrangementID)
        )
    }
    return .resolved(
        ResolvedActiveArrangement(
            tabState: tabState,
            arrangementIndex: arrangementIndex,
            arrangement: tabState.arrangements[arrangementIndex]
        )
    )
}

private func resolvePaneInActiveArrangement(
    tabID: UUID,
    paneID: UUID,
    tab: WorkspaceTabGraphStateWitness,
    activeArrangementPaneCursor: WorkspaceActiveArrangementPaneCursorWitness
) -> ActiveArrangementWithPaneCursorResolution {
    guard case .present(let tabState) = tab, tabState.tabId == tabID else {
        return .rejected(.missingTab(tabID))
    }
    guard tabState.allPaneIds.contains(paneID) else {
        return .rejected(.paneNotOwnedByTab(tabID: tabID, paneID: paneID))
    }
    guard
        case .selected(let activeArrangementID, let paneCursor) = activeArrangementPaneCursor
    else {
        return .rejected(.missingActiveArrangement(tabID))
    }
    switch resolveActiveArrangement(
        tabID: tabID,
        tab: tab,
        activeArrangement: .selected(activeArrangementID)
    ) {
    case .rejected(let rejection):
        return .rejected(rejection)
    case .resolved(let source):
        guard source.arrangement.layout.contains(paneID) else {
            return .rejected(
                .paneNotInActiveArrangement(
                    tabID: tabID,
                    arrangementID: source.arrangement.id,
                    paneID: paneID
                )
            )
        }
        return .resolved(
            ResolvedActiveArrangementWithPaneCursor(
                source: source,
                paneCursor: paneCursor
            )
        )
    }
}

private func resolvedCurrentArrangement(
    tabState: TabGraphState,
    activeArrangement: WorkspaceActiveArrangementSelection
) -> PaneArrangementGraphState {
    if case .selected(let activeArrangementID) = activeArrangement,
        let active = tabState.arrangements.first(where: { $0.id == activeArrangementID })
    {
        return active
    }
    guard let fallback = tabState.arrangements.first(where: \.isDefault) ?? tabState.arrangements.first else {
        preconditionFailure("a persisted tab graph must contain an arrangement")
    }
    return fallback
}

private func fallbackPaneSelection(
    current: WorkspaceActivePaneCursorWitness,
    arrangement: PaneArrangementGraphState
) -> WorkspacePaneSelection {
    if case .present(.selected(let paneID)) = current,
        arrangement.layout.contains(paneID),
        !arrangement.minimizedPaneIds.contains(paneID)
    {
        return .selected(paneID)
    }
    return firstUnminimizedPaneSelection(arrangement)
}

private func firstUnminimizedPaneSelection(
    _ arrangement: PaneArrangementGraphState
) -> WorkspacePaneSelection {
    arrangement.layout.paneIds.first(where: { !arrangement.minimizedPaneIds.contains($0) })
        .map(WorkspacePaneSelection.selected) ?? .noSelection
}

private func activePaneTransition(
    arrangementID: UUID,
    current: WorkspaceActivePaneCursorWitness,
    desired: WorkspacePaneSelection
) -> WorkspaceVisibilityActivePaneTransition {
    switch (current, desired) {
    case (.present(.selected(let previous)), .selected(let replacement)) where previous != replacement:
        return .replace(
            arrangementID: arrangementID,
            previous: previous,
            replacement: replacement
        )
    case (.present(.selected(let previous)), .noSelection):
        return .remove(arrangementID: arrangementID, previous: previous)
    case (.missing, .selected(let replacement)), (.present(.noSelection), .selected(let replacement)):
        return .insert(
            arrangementID: arrangementID,
            expected: current,
            replacement: replacement
        )
    default:
        return .witness(arrangementID: arrangementID, expected: current)
    }
}

private func zoomTransition(
    tabID: UUID,
    selection: WorkspaceZoomSelection
) -> WorkspaceVisibilityZoomTransition {
    switch selection {
    case .notZoomed:
        return .witness(tabID: tabID, expected: .notZoomed)
    case .zoomed(let paneID):
        return .clear(tabID: tabID, previous: paneID)
    }
}

private func zoomTransition(
    tabID: UUID,
    clearingPaneID: UUID,
    selection: WorkspaceZoomSelection
) -> WorkspaceVisibilityZoomTransition {
    guard case .zoomed(let zoomedPaneID) = selection else {
        return .witness(tabID: tabID, expected: .notZoomed)
    }
    guard zoomedPaneID == clearingPaneID else {
        return .witness(tabID: tabID, expected: .zoomed(zoomedPaneID))
    }
    return .clear(tabID: tabID, previous: zoomedPaneID)
}
