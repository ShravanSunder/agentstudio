import Foundation

func layoutRemovingPane(_ paneID: UUID, from layout: Layout) -> Layout? {
    guard layout.contains(paneID) else { return nil }
    if layout.paneIds.count == 1 { return Layout() }
    return layout.removing(paneId: paneID, sizingMode: .halveTarget)
}

func terminalReactivateDecision(
    for pane: PaneGraphState,
    familyPaneIDs: [UUID],
    ownershipByPaneID: [UUID: WorkspacePaneResidencyTabOwnershipWitness]
) -> WorkspaceReactivatePaneTransitionDecision? {
    guard pane.residency != .backgrounded else { return nil }
    guard pane.residency == .active else {
        return .rejected(.invalidPaneResidency(paneID: pane.id, actual: pane.residency))
    }
    if case .owned(let owner) = validateOwnedPaneFamily(
        paneIDs: familyPaneIDs,
        ownershipByPaneID: ownershipByPaneID
    ), owner.state.arrangements.allSatisfy({ $0.layout.contains(pane.id) }) {
        return .unchanged
    }
    if let rejection = validateAbsentPaneFamily(
        paneIDs: familyPaneIDs,
        ownershipByPaneID: ownershipByPaneID
    ) {
        return .rejected(rejection)
    }
    return .rejected(.paneNotOwnedByTab(pane.id))
}

func validateChildren(
    parent: PaneGraphState,
    drawer: DrawerGraphState,
    statesByID: [UUID: PaneGraphState],
    expectedResidency: SessionResidency
) -> [PaneGraphState]? {
    var result: [PaneGraphState] = []
    for childID in drawer.paneIds {
        guard let child = statesByID[childID], child.id == childID,
            child.parentPaneId == parent.id, child.residency == expectedResidency
        else { return nil }
        result.append(child)
    }
    return result
}

func firstChildRejection(
    parent: PaneGraphState,
    drawer: DrawerGraphState,
    statesByID: [UUID: PaneGraphState],
    expectedResidency: SessionResidency
) -> WorkspacePaneResidencyLifecycleRejection {
    for childID in drawer.paneIds {
        guard let child = statesByID[childID] else { return .childMissing(childID) }
        guard child.id == childID else { return .childIdentityMismatch(expected: childID, actual: child.id) }
        guard child.parentPaneId == parent.id else {
            return .childParentMismatch(
                childID: childID,
                expectedParentID: parent.id,
                actualParentID: child.parentPaneId
            )
        }
        guard child.residency == expectedResidency else {
            return .childResidencyMismatch(
                childID: childID,
                expected: expectedResidency,
                actual: child.residency
            )
        }
    }
    preconditionFailure("child validation rejection must identify a failed invariant")
}

func ownershipRejection(
    paneID: UUID,
    ownership: WorkspacePaneResidencyTabOwnershipWitness
) -> WorkspacePaneResidencyLifecycleRejection {
    switch ownership {
    case .absent: return .paneNotOwnedByTab(paneID)
    case .owned(let owner): return .paneAlreadyOwnedByTab(paneID: paneID, tabID: owner.state.tabId)
    case .multiple(let tabIDs): return .paneOwnedByMultipleTabs(paneID: paneID, tabIDs: tabIDs)
    }
}

enum WorkspaceOwnedPaneFamilyResolution {
    case owned(WorkspaceIndexedTabGraphState)
    case rejected(WorkspacePaneResidencyLifecycleRejection)
}

func validateOwnedPaneFamily(
    paneIDs: [UUID],
    ownershipByPaneID: [UUID: WorkspacePaneResidencyTabOwnershipWitness]
) -> WorkspaceOwnedPaneFamilyResolution {
    guard let parentPaneID = paneIDs.first else {
        preconditionFailure("a pane family must contain its parent")
    }
    guard let parentOwnership = ownershipByPaneID[parentPaneID] else {
        return .rejected(.paneOwnershipWitnessMissing(parentPaneID))
    }
    guard case .owned(let sourceTab) = parentOwnership else {
        return .rejected(ownershipRejection(paneID: parentPaneID, ownership: parentOwnership))
    }
    for paneID in paneIDs {
        guard let ownership = ownershipByPaneID[paneID] else {
            return .rejected(.paneOwnershipWitnessMissing(paneID))
        }
        guard case .owned(let owner) = ownership else {
            return .rejected(ownershipRejection(paneID: paneID, ownership: ownership))
        }
        guard owner == sourceTab, owner.state.allPaneIds.contains(paneID) else {
            return .rejected(
                .paneOwnerMismatch(
                    paneID: paneID,
                    expectedTabID: sourceTab.state.tabId,
                    actualTabID: owner.state.tabId
                )
            )
        }
    }
    return .owned(sourceTab)
}

func validateAbsentPaneFamily(
    paneIDs: [UUID],
    ownershipByPaneID: [UUID: WorkspacePaneResidencyTabOwnershipWitness]
) -> WorkspacePaneResidencyLifecycleRejection? {
    for paneID in paneIDs {
        guard let ownership = ownershipByPaneID[paneID] else {
            return .paneOwnershipWitnessMissing(paneID)
        }
        guard case .absent = ownership else {
            return ownershipRejection(paneID: paneID, ownership: ownership)
        }
    }
    return nil
}

func familyOwnershipWitnesses(
    paneIDs: [UUID],
    ownershipByPaneID: [UUID: WorkspacePaneResidencyTabOwnershipWitness]
) -> [WorkspacePaneResidencyFamilyOwnershipWitness] {
    paneIDs.map { paneID in
        guard let ownership = ownershipByPaneID[paneID] else {
            preconditionFailure("validated pane-family ownership must remain complete")
        }
        return .init(paneID: paneID, expected: ownership)
    }
}

func drawerViewActiveChildID(
    _ witness: WorkspacePaneResidencyDrawerCursorWitness
) -> UUID? {
    guard case .present(.selected(let childID)) = witness else { return nil }
    return childID
}

func restoredDrawerView(
    arrangementID: UUID,
    drawer: DrawerGraphState,
    payload: WorkspaceRetainedDrawerPayloadWitness
) -> DrawerView {
    if case .present(let retained) = payload,
        retained.drawerID == drawer.drawerId,
        let view = retained.viewsByArrangementID[arrangementID],
        Set(view.layout.paneIds) == Set(drawer.paneIds)
    {
        return view
    }
    return DrawerView(
        layout: DrawerGridLayout(topRow: Layout.autoTiled(drawer.paneIds)),
        activeChildId: drawer.paneIds.first
    )
}

func validateRetainedDrawerPayload(
    _ payload: WorkspaceRetainedDrawerPayloadWitness,
    drawer: DrawerGraphState
) -> WorkspacePaneResidencyLifecycleRejection? {
    guard case .present(let retained) = payload else { return nil }
    guard retained.drawerID == drawer.drawerId else {
        return .retainedDrawerPayloadMismatch(
            expectedDrawerID: drawer.drawerId,
            actualDrawerID: retained.drawerID
        )
    }
    for (arrangementID, view) in retained.viewsByArrangementID {
        let actualPaneIDs = view.layout.paneIds
        guard Set(actualPaneIDs).count == actualPaneIDs.count,
            Set(actualPaneIDs) == Set(drawer.paneIds)
        else {
            return .retainedDrawerPayloadInvalidMembership(
                arrangementID: arrangementID,
                expected: drawer.paneIds,
                actual: actualPaneIDs
            )
        }
        let invalidMinimized = view.minimizedPaneIds.subtracting(actualPaneIDs)
        guard invalidMinimized.isEmpty else {
            return .retainedDrawerPayloadInvalidMinimized(
                arrangementID: arrangementID,
                invalidPaneIDs: invalidMinimized
            )
        }
        if actualPaneIDs.isEmpty {
            guard view.activeChildId == nil else {
                return .retainedDrawerPayloadInvalidActiveChild(
                    arrangementID: arrangementID,
                    activeChildID: view.activeChildId
                )
            }
        } else {
            guard let activeChildID = view.activeChildId, actualPaneIDs.contains(activeChildID) else {
                return .retainedDrawerPayloadInvalidActiveChild(
                    arrangementID: arrangementID,
                    activeChildID: view.activeChildId
                )
            }
        }
    }
    return nil
}

func isValidActivePaneWitness(
    _ witness: WorkspaceActivePaneCursorWitness,
    for layout: Layout
) -> Bool {
    guard case .present(let selection) = witness else { return false }
    switch selection {
    case .selected(let paneID): return layout.contains(paneID)
    case .noSelection: return layout.isEmpty
    }
}

func activeTabAfterRemoving(
    _ removedTabID: UUID,
    activeTab: WorkspaceTabCursorSelection,
    remainingShells: [TabShell]
) -> WorkspaceTabCursorSelection? {
    switch activeTab {
    case .selected(let selectedID) where selectedID == removedTabID:
        return remainingShells.last.map { .selected($0.id) } ?? .noSelection
    case .selected(let selectedID) where remainingShells.contains(where: { $0.id == selectedID }):
        return activeTab
    case .noSelection where remainingShells.isEmpty:
        return .noSelection
    default:
        return nil
    }
}

func isValidDrawerCursorWitness(
    _ witness: WorkspacePaneResidencyDrawerCursorWitness,
    for layout: DrawerGridLayout
) -> Bool {
    guard case .present(let selection) = witness else { return false }
    switch selection {
    case .selected(let paneID): return layout.contains(paneID)
    case .noSelection: return layout.isEmpty
    }
}

func zoomMutation(
    tabID: UUID,
    paneID: UUID?,
    current: WorkspaceZoomSelection
) -> WorkspacePaneResidencyZoomMutation {
    switch current {
    case .zoomed(let currentPaneID) where paneID == nil || paneID == currentPaneID:
        return .clear(tabID: tabID, previous: currentPaneID)
    default:
        return .witness(tabID: tabID, expected: current)
    }
}
