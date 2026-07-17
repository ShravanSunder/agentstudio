import Foundation

enum WorkspaceBackgroundPaneTransitionPlanner {
    static func plan(
        _ request: WorkspaceBackgroundPaneRequest,
        context: WorkspaceBackgroundPanePlanningContext
    ) -> WorkspaceBackgroundPaneTransitionDecision {
        guard case .present(let pane) = context.pane else {
            return .rejected(.paneMissing(request.paneID))
        }
        guard pane.id == request.paneID else {
            return .rejected(.paneIdentityMismatch(expected: request.paneID, actual: pane.id))
        }
        guard case .layout(let drawer) = pane.kind else {
            return .rejected(.drawerChildPane(request.paneID))
        }
        guard
            let validatedChildren = validateChildren(
                parent: pane,
                drawer: drawer,
                statesByID: context.declaredDrawerChildrenByID,
                expectedResidency: pane.residency
            )
        else {
            return .rejected(
                firstChildRejection(
                    parent: pane,
                    drawer: drawer,
                    statesByID: context.declaredDrawerChildrenByID,
                    expectedResidency: pane.residency
                ))
        }

        let familyPaneIDs = [pane.id] + drawer.paneIds
        if pane.residency == .backgrounded {
            if let rejection = validateAbsentPaneFamily(
                paneIDs: familyPaneIDs,
                ownershipByPaneID: context.ownershipByPaneID
            ) {
                return .rejected(rejection)
            }
            return .unchanged
        }
        guard pane.residency == .active else {
            return .rejected(.invalidPaneResidency(paneID: pane.id, actual: pane.residency))
        }
        let indexedTab: WorkspaceIndexedTabGraphState
        switch validateOwnedPaneFamily(
            paneIDs: familyPaneIDs,
            ownershipByPaneID: context.ownershipByPaneID
        ) {
        case .owned(let owner): indexedTab = owner
        case .rejected(let rejection): return .rejected(rejection)
        }

        let activeArrangementID: UUID
        switch context.tabCursors.activeArrangement {
        case .missing:
            return .rejected(.activeArrangementMissing(indexedTab.state.tabId))
        case .selected(let arrangementID):
            activeArrangementID = arrangementID
        }
        guard indexedTab.state.arrangements.contains(where: { $0.id == activeArrangementID }) else {
            return .rejected(
                .activeArrangementNotInTab(tabID: indexedTab.state.tabId, arrangementID: activeArrangementID)
            )
        }

        switch backgroundGraphProjection(
            pane: pane,
            drawer: drawer,
            indexedTab: indexedTab,
            cursors: context.tabCursors
        ) {
        case .rejected(let rejection):
            return .rejected(rejection)
        case .projected(let projection):
            return makeBackgroundDecision(
                source: .init(
                    pane: pane,
                    drawer: drawer,
                    children: validatedChildren,
                    indexedTab: indexedTab,
                    activeArrangementID: activeArrangementID
                ),
                projection: projection,
                context: context
            )
        }
    }
}

private struct WorkspaceBackgroundGraphProjection {
    let replacementTab: TabGraphState
    let activePanes: [WorkspacePaneResidencyActivePaneMutation]
    let activeDrawers: [WorkspacePaneResidencyActiveDrawerMutation]
    let capturedViews: [UUID: DrawerView]
}

private enum WorkspaceBackgroundGraphProjectionResult {
    case projected(WorkspaceBackgroundGraphProjection)
    case rejected(WorkspacePaneResidencyLifecycleRejection)
}

private func backgroundGraphProjection(
    pane: PaneGraphState,
    drawer: DrawerGraphState,
    indexedTab: WorkspaceIndexedTabGraphState,
    cursors: WorkspacePaneResidencyTabCursorSnapshot
) -> WorkspaceBackgroundGraphProjectionResult {
    let removedPaneIDs = Set([pane.id] + drawer.paneIds)
    var replacementTab = indexedTab.state
    var activePanes: [WorkspacePaneResidencyActivePaneMutation] = []
    var activeDrawers: [WorkspacePaneResidencyActiveDrawerMutation] = []
    var capturedViews: [UUID: DrawerView] = [:]

    for arrangementIndex in replacementTab.arrangements.indices {
        let previousArrangement = indexedTab.state.arrangements[arrangementIndex]
        guard let replacementLayout = layoutRemovingPane(pane.id, from: previousArrangement.layout) else {
            return .rejected(.paneNotOwnedByTab(pane.id))
        }
        replacementTab.arrangements[arrangementIndex].layout = replacementLayout
        replacementTab.arrangements[arrangementIndex].minimizedPaneIds.remove(pane.id)
        replacementTab.arrangements[arrangementIndex].drawerViews.removeValue(forKey: drawer.drawerId)

        let paneWitness = cursors.activePanesByArrangementID[previousArrangement.id] ?? .missing
        guard
            let paneMutation = backgroundActivePaneMutation(
                paneID: pane.id,
                arrangementID: previousArrangement.id,
                replacementLayout: replacementLayout,
                witness: paneWitness
            )
        else {
            return .rejected(.paneSelectionInvalid(arrangementID: previousArrangement.id))
        }
        activePanes.append(paneMutation)

        guard let drawerView = previousArrangement.drawerViews[drawer.drawerId] else { continue }
        let key = ArrangementDrawerCursorKey(
            arrangementId: previousArrangement.id,
            drawerId: drawer.drawerId
        )
        let cursorWitness = cursors.activeDrawerChildrenByKey[key] ?? .missing
        guard case .present = cursorWitness else { return .rejected(.drawerCursorMissing(key)) }
        guard isValidDrawerCursorWitness(cursorWitness, for: drawerView.layout) else {
            return .rejected(.drawerCursorSelectionInvalid(key))
        }
        let cursorChildID = drawerViewActiveChildID(cursorWitness)
        if let cursorChildID, !drawerView.layout.paneIds.contains(cursorChildID) {
            return .rejected(.drawerCursorSelectionInvalid(key))
        }
        capturedViews[previousArrangement.id] = DrawerView(
            layout: drawerView.layout,
            activeChildId: cursorChildID,
            minimizedPaneIds: drawerView.minimizedPaneIds
        )
        activeDrawers.append(.remove(key: key, previous: cursorWitness))
    }
    replacementTab.allPaneIds.removeAll { removedPaneIDs.contains($0) }
    return .projected(
        .init(
            replacementTab: replacementTab,
            activePanes: activePanes,
            activeDrawers: activeDrawers,
            capturedViews: capturedViews
        )
    )
}

private func backgroundActivePaneMutation(
    paneID: UUID,
    arrangementID: UUID,
    replacementLayout: Layout,
    witness: WorkspaceActivePaneCursorWitness
) -> WorkspacePaneResidencyActivePaneMutation? {
    guard case .present(let selection) = witness else { return nil }
    switch selection {
    case .selected(let selectedPaneID) where selectedPaneID == paneID:
        let replacement = replacementLayout.paneIds.first.map(WorkspacePaneSelection.selected) ?? .noSelection
        return .replace(arrangementID: arrangementID, previous: witness, replacement: replacement)
    case .selected(let selectedPaneID) where replacementLayout.contains(selectedPaneID):
        return .witness(arrangementID: arrangementID, expected: witness)
    case .noSelection where replacementLayout.isEmpty:
        return .witness(arrangementID: arrangementID, expected: witness)
    default:
        return nil
    }
}

private struct WorkspaceBackgroundResolvedSource {
    let pane: PaneGraphState
    let drawer: DrawerGraphState
    let children: [PaneGraphState]
    let indexedTab: WorkspaceIndexedTabGraphState
    let activeArrangementID: UUID
}

private func makeBackgroundDecision(
    source: WorkspaceBackgroundResolvedSource,
    projection: WorkspaceBackgroundGraphProjection,
    context: WorkspaceBackgroundPanePlanningContext
) -> WorkspaceBackgroundPaneTransitionDecision {
    let common = backgroundCommonTransitionParts(
        pane: source.pane,
        drawer: source.drawer,
        children: source.children,
        indexedTab: source.indexedTab,
        projection: projection,
        context: context
    )
    if !projection.replacementTab.allPaneIds.isEmpty {
        guard case .notRequired = context.tabRemoval else {
            return .rejected(.tabRemovalContextUnexpected(source.indexedTab.state.tabId))
        }
        return .changed(
            .background(
                .init(
                    paneReplacements: common.panes,
                    familyOwnership: familyOwnershipWitnesses(
                        paneIDs: [source.pane.id] + source.drawer.paneIds,
                        ownershipByPaneID: context.ownershipByPaneID
                    ),
                    tabGraph: .replace(
                        previous: source.indexedTab,
                        replacement: .init(index: source.indexedTab.index, state: projection.replacementTab)
                    ),
                    tabShell: .notRead,
                    tabCursor: .notRead,
                    activeArrangements: [
                        .witness(tabID: source.indexedTab.state.tabId, expected: context.tabCursors.activeArrangement)
                    ],
                    activePanes: projection.activePanes,
                    activeDrawerChildren: projection.activeDrawers,
                    zoom: common.zoom,
                    runtimePayload: common.runtimePayload
                )
            )
        )
    }
    return makeEmptyTabBackgroundDecision(
        indexedTab: source.indexedTab,
        activeArrangementID: source.activeArrangementID,
        projection: projection,
        common: common,
        context: context
    )
}

private struct WorkspaceBackgroundCommonTransitionParts {
    let panes: [WorkspacePaneResidencyPaneReplacement]
    let zoom: WorkspacePaneResidencyZoomMutation
    let runtimePayload: WorkspacePaneResidencyRuntimePayloadTransition
}

private func backgroundCommonTransitionParts(
    pane: PaneGraphState,
    drawer: DrawerGraphState,
    children: [PaneGraphState],
    indexedTab: WorkspaceIndexedTabGraphState,
    projection: WorkspaceBackgroundGraphProjection,
    context: WorkspaceBackgroundPanePlanningContext
) -> WorkspaceBackgroundCommonTransitionParts {
    let paneReplacements = ([pane] + children).map { previous -> WorkspacePaneResidencyPaneReplacement in
        var replacement = previous
        replacement.residency = .backgrounded
        return .init(paneID: previous.id, previous: previous, replacement: replacement)
    }
    let capturedPayload: WorkspaceRetainedDrawerPayloadWitness =
        drawer.paneIds.isEmpty
        ? .absent
        : .present(.init(drawerID: drawer.drawerId, viewsByArrangementID: projection.capturedViews))
    return .init(
        panes: paneReplacements,
        zoom: zoomMutation(tabID: indexedTab.state.tabId, paneID: pane.id, current: context.tabCursors.zoom),
        runtimePayload: .init(
            expected: context.retainedDrawerPayload,
            effect: .replaceRetainedDrawerPayload(paneID: pane.id, replacement: capturedPayload)
        )
    )
}

private func makeEmptyTabBackgroundDecision(
    indexedTab: WorkspaceIndexedTabGraphState,
    activeArrangementID: UUID,
    projection: WorkspaceBackgroundGraphProjection,
    common: WorkspaceBackgroundCommonTransitionParts,
    context: WorkspaceBackgroundPanePlanningContext
) -> WorkspaceBackgroundPaneTransitionDecision {
    guard case .current(let tabShells, let activeTab) = context.tabRemoval else {
        return .rejected(.tabRemovalContextMissing(indexedTab.state.tabId))
    }
    guard let removedShellIndex = tabShells.firstIndex(where: { $0.id == indexedTab.state.tabId }) else {
        return .rejected(.tabShellMissing(indexedTab.state.tabId))
    }
    var replacementShells = tabShells
    replacementShells.remove(at: removedShellIndex)
    guard
        let replacementActiveTab = activeTabAfterRemoving(
            indexedTab.state.tabId,
            activeTab: activeTab,
            remainingShells: replacementShells
        )
    else {
        return .rejected(.tabCursorInvalid(indexedTab.state.tabId))
    }
    let tabCursor: WorkspacePaneResidencyTabCursorMutation =
        replacementActiveTab == activeTab
        ? .witness(activeTab)
        : .replace(.init(previous: activeTab, replacement: replacementActiveTab))
    let removedPaneCursors = indexedTab.state.arrangements.map { arrangement in
        WorkspacePaneResidencyActivePaneMutation.remove(
            arrangementID: arrangement.id,
            previous: context.tabCursors.activePanesByArrangementID[arrangement.id] ?? .missing
        )
    }
    return .changed(
        .background(
            .init(
                paneReplacements: common.panes,
                familyOwnership: familyOwnershipWitnesses(
                    paneIDs: [common.panes[0].paneID] + common.panes.dropFirst().map(\.paneID),
                    ownershipByPaneID: context.ownershipByPaneID
                ),
                tabGraph: .remove(indexedTab),
                tabShell: .remove(
                    removed: .init(index: removedShellIndex, shell: tabShells[removedShellIndex]),
                    shiftedSuffix: tabShells.enumerated().dropFirst(removedShellIndex + 1).map {
                        .init(index: $0.offset, shell: $0.element)
                    }
                ),
                tabCursor: tabCursor,
                activeArrangements: [.remove(tabID: indexedTab.state.tabId, previous: activeArrangementID)],
                activePanes: removedPaneCursors,
                activeDrawerChildren: projection.activeDrawers,
                zoom: common.zoom,
                runtimePayload: common.runtimePayload
            )
        )
    )
}

enum WorkspaceReactivatePaneTransitionPlanner {
    static func plan(
        _ request: WorkspaceReactivatePaneRequest,
        context: WorkspaceReactivatePanePlanningContext
    ) -> WorkspaceReactivatePaneTransitionDecision {
        guard case .present(let pane) = context.pane else { return .rejected(.paneMissing(request.paneID)) }
        guard pane.id == request.paneID else {
            return .rejected(.paneIdentityMismatch(expected: request.paneID, actual: pane.id))
        }
        guard case .layout(let drawer) = pane.kind else { return .rejected(.drawerChildPane(pane.id)) }
        let familyPaneIDs = [pane.id] + drawer.paneIds
        let terminalDecision = terminalReactivateDecision(
            for: pane,
            familyPaneIDs: familyPaneIDs,
            ownershipByPaneID: context.ownershipByPaneID
        )
        if let terminalDecision { return terminalDecision }
        if let rejection = validateAbsentPaneFamily(
            paneIDs: familyPaneIDs,
            ownershipByPaneID: context.ownershipByPaneID
        ) {
            return .rejected(rejection)
        }
        guard
            let validatedChildren = validateChildren(
                parent: pane,
                drawer: drawer,
                statesByID: context.declaredDrawerChildrenByID,
                expectedResidency: .backgrounded
            )
        else {
            return .rejected(
                firstChildRejection(
                    parent: pane,
                    drawer: drawer,
                    statesByID: context.declaredDrawerChildrenByID,
                    expectedResidency: .backgrounded
                ))
        }
        if let rejection = validateRetainedDrawerPayload(context.retainedDrawerPayload, drawer: drawer) {
            return .rejected(rejection)
        }
        guard case .present(let indexedTab) = context.targetTab else {
            return .rejected(.targetTabMissing(request.targetTabID))
        }
        guard indexedTab.state.tabId == request.targetTabID else {
            return .rejected(.targetTabMissing(request.targetTabID))
        }
        if let duplicatePaneID = familyPaneIDs.first(where: { indexedTab.state.allPaneIds.contains($0) }) {
            return .rejected(
                .paneAlreadyOwnedByTab(paneID: duplicatePaneID, tabID: indexedTab.state.tabId)
            )
        }
        guard indexedTab.state.arrangements.allSatisfy({ !$0.layout.contains(pane.id) }) else {
            return .rejected(.paneAlreadyOwnedByTab(paneID: pane.id, tabID: indexedTab.state.tabId))
        }
        let activeArrangementID: UUID
        switch context.targetTabCursors.activeArrangement {
        case .missing: return .rejected(.activeArrangementMissing(request.targetTabID))
        case .selected(let id): activeArrangementID = id
        }
        guard
            let activeArrangementIndex = indexedTab.state.arrangements.firstIndex(where: {
                $0.id == activeArrangementID
            })
        else {
            return .rejected(.activeArrangementNotInTab(tabID: request.targetTabID, arrangementID: activeArrangementID))
        }
        guard indexedTab.state.arrangements[activeArrangementIndex].layout.contains(request.targetPaneID) else {
            return .rejected(.targetPaneMissing(tabID: request.targetTabID, paneID: request.targetPaneID))
        }
        guard
            let insertedActiveLayout = indexedTab.state.arrangements[activeArrangementIndex].layout.inserting(
                paneId: pane.id,
                at: request.targetPaneID,
                direction: request.direction,
                position: request.position,
                sizingMode: request.sizingMode
            )
        else {
            return .rejected(.layoutInsertionRejected(tabID: request.targetTabID, targetPaneID: request.targetPaneID))
        }

        switch reactivationGraphProjection(
            source: .init(
                pane: pane,
                drawer: drawer,
                indexedTab: indexedTab,
                activeArrangementIndex: activeArrangementIndex,
                insertedActiveLayout: insertedActiveLayout
            ),
            context: context,
            request: request
        ) {
        case .rejected(let rejection):
            return .rejected(rejection)
        case .projected(let projection):
            return makeReactivateDecision(
                pane: pane,
                children: validatedChildren,
                indexedTab: indexedTab,
                projection: projection,
                request: request,
                context: context
            )
        }
    }
}

private struct WorkspaceReactivationGraphProjection {
    let replacementTab: TabGraphState
    let activePanes: [WorkspacePaneResidencyActivePaneMutation]
    let activeDrawers: [WorkspacePaneResidencyActiveDrawerMutation]
}

private enum WorkspaceReactivationGraphProjectionResult {
    case projected(WorkspaceReactivationGraphProjection)
    case rejected(WorkspacePaneResidencyLifecycleRejection)
}

private struct WorkspaceReactivationResolvedSource {
    let pane: PaneGraphState
    let drawer: DrawerGraphState
    let indexedTab: WorkspaceIndexedTabGraphState
    let activeArrangementIndex: Int
    let insertedActiveLayout: Layout
}

private func reactivationGraphProjection(
    source: WorkspaceReactivationResolvedSource,
    context: WorkspaceReactivatePanePlanningContext,
    request: WorkspaceReactivatePaneRequest
) -> WorkspaceReactivationGraphProjectionResult {
    var replacementTab = source.indexedTab.state
    replacementTab.allPaneIds.append(contentsOf: [source.pane.id] + source.drawer.paneIds)
    var activePanes: [WorkspacePaneResidencyActivePaneMutation] = []
    var activeDrawers: [WorkspacePaneResidencyActiveDrawerMutation] = []
    for arrangementIndex in replacementTab.arrangements.indices {
        let previousArrangement = source.indexedTab.state.arrangements[arrangementIndex]
        let paneWitness = context.targetTabCursors.activePanesByArrangementID[previousArrangement.id] ?? .missing
        guard isValidActivePaneWitness(paneWitness, for: previousArrangement.layout) else {
            return .rejected(.paneSelectionInvalid(arrangementID: previousArrangement.id))
        }
        if arrangementIndex == source.activeArrangementIndex {
            replacementTab.arrangements[arrangementIndex].layout = source.insertedActiveLayout
            activePanes.append(
                .replace(
                    arrangementID: previousArrangement.id,
                    previous: paneWitness,
                    replacement: .selected(source.pane.id)
                )
            )
        } else {
            guard let appended = layoutAppendingPane(source.pane.id, to: previousArrangement.layout) else {
                return .rejected(
                    .layoutInsertionRejected(tabID: request.targetTabID, targetPaneID: request.targetPaneID)
                )
            }
            replacementTab.arrangements[arrangementIndex].layout = appended
            activePanes.append(.witness(arrangementID: previousArrangement.id, expected: paneWitness))
        }
        replacementTab.arrangements[arrangementIndex].minimizedPaneIds.remove(source.pane.id)
        guard !source.drawer.paneIds.isEmpty else { continue }
        let restoredView = restoredDrawerView(
            arrangementID: previousArrangement.id,
            drawer: source.drawer,
            payload: context.retainedDrawerPayload
        )
        replacementTab.arrangements[arrangementIndex].drawerViews[source.drawer.drawerId] = DrawerViewGraphState(
            restoredView)
        let key = ArrangementDrawerCursorKey(
            arrangementId: previousArrangement.id,
            drawerId: source.drawer.drawerId
        )
        let expected = context.targetTabCursors.activeDrawerChildrenByKey[key] ?? .missing
        guard expected == .missing else { return .rejected(.drawerCursorSelectionInvalid(key)) }
        activeDrawers.append(
            .insert(
                key: key,
                expected: expected,
                replacement: restoredView.activeChildId.map(WorkspacePaneResidencyDrawerSelection.selected)
                    ?? .noSelection
            )
        )
    }
    return .projected(
        .init(replacementTab: replacementTab, activePanes: activePanes, activeDrawers: activeDrawers)
    )
}

private func layoutAppendingPane(_ paneID: UUID, to layout: Layout) -> Layout? {
    guard let anchor = layout.paneIds.last else { return nil }
    return layout.inserting(
        paneId: paneID,
        at: anchor,
        direction: .horizontal,
        position: .after,
        sizingMode: .proportional
    )
}

private func makeReactivateDecision(
    pane: PaneGraphState,
    children: [PaneGraphState],
    indexedTab: WorkspaceIndexedTabGraphState,
    projection: WorkspaceReactivationGraphProjection,
    request: WorkspaceReactivatePaneRequest,
    context: WorkspaceReactivatePanePlanningContext
) -> WorkspaceReactivatePaneTransitionDecision {
    let paneReplacements = ([pane] + children).map { previous -> WorkspacePaneResidencyPaneReplacement in
        var replacement = previous
        replacement.residency = .active
        return .init(paneID: previous.id, previous: previous, replacement: replacement)
    }
    return .changed(
        .reactivate(
            .init(
                paneReplacements: paneReplacements,
                familyOwnership: familyOwnershipWitnesses(
                    paneIDs: [pane.id] + children.map(\.id),
                    ownershipByPaneID: context.ownershipByPaneID
                ),
                tabGraph: .replace(
                    previous: indexedTab,
                    replacement: .init(index: indexedTab.index, state: projection.replacementTab)
                ),
                activeArrangements: [
                    .witness(tabID: request.targetTabID, expected: context.targetTabCursors.activeArrangement)
                ],
                activePanes: projection.activePanes,
                activeDrawerChildren: projection.activeDrawers,
                zoom: zoomMutation(tabID: request.targetTabID, paneID: nil, current: context.targetTabCursors.zoom),
                runtimePayload: .init(
                    expected: context.retainedDrawerPayload,
                    effect: .consumeRetainedDrawerPayloadAndMount(paneID: pane.id)
                )
            )
        )
    )
}
