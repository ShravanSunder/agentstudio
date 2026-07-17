import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Close pane in retained tab transition applier")
struct RetainedTabPaneCloseApplierTests {
    @Test("apply removes one pane and preserves 256 unrelated indexed tabs")
    func applyIsStrictAndTargetKeyed() throws {
        // Arrange
        let fixture = makeRetainedTabCloseFixture()
        let unrelated = (0..<256).map { makeRetainedTabCloseUnrelatedTab(seed: $0) }
        let atoms = makeRetainedTabCloseApplierAtoms(fixture: fixture, unrelated: unrelated)
        let transition = try plannedRetainedTabCloseTransition(fixture, zoom: .zoomed(fixture.closedPaneID))

        // Act
        let result = atoms.applier.apply(transition)

        // Assert
        #expect(result == .applied)
        #expect(atoms.panes.paneState(fixture.closedPaneID) == nil)
        #expect(atoms.tabs.tabState(fixture.tab.tabId) == transition.replacementTab)
        #expect(atoms.tabs.tabID(containingPane: fixture.closedPaneID) == nil)
        #expect(atoms.tabs.tabID(containingPane: fixture.fallbackPaneID) == fixture.tab.tabId)
        #expect(
            atoms.cursors.activeArrangementId(forTab: fixture.tab.tabId)
                == fixture.defaultArrangementID
        )
        #expect(atoms.cursors.activePaneId(forArrangement: fixture.selectedArrangementID) == nil)
        #expect(
            atoms.cursors.activePaneId(forArrangement: fixture.defaultArrangementID)
                == fixture.fallbackPaneID
        )
        #expect(atoms.presentation.zoomedPaneId(forTab: fixture.tab.tabId) == nil)
        #expect(Array(atoms.tabs.tabStates.prefix(256)) == unrelated)
        for tab in unrelated {
            #expect(atoms.tabs.tabState(tab.tabId) == tab)
            #expect(atoms.tabs.tabID(containingPane: tab.allPaneIds[0]) == tab.tabId)
            #expect(atoms.tabs.tabID(containingArrangement: tab.arrangements[0].id) == tab.tabId)
        }
    }

    @Test("stale pane ownership and tab reject with zero additional mutation")
    func staleGraphWitnessesRejectAtomically() throws {
        // Arrange / Act / Assert
        try assertRetainedTabCloseStale(
            mutate: { fixture, atoms in
                _ = atoms.panes.removeCanonicalPaneState(for: fixture.closedPaneID)
            },
            expected: { fixture in
                .stalePane(
                    paneID: fixture.closedPaneID,
                    expected: .present(fixture.pane),
                    actual: .missing
                )
            }
        )
        try assertRetainedTabCloseStale(
            mutate: { fixture, atoms in
                var replacement = fixture.tab
                replacement.allPaneIds.removeAll { $0 == fixture.closedPaneID }
                for index in replacement.arrangements.indices {
                    replacement.arrangements[index].layout = .autoTiled([fixture.fallbackPaneID])
                }
                atoms.tabs.replaceTabStateAndOwnership(replacement)
            },
            expected: { fixture in
                .staleOwnership(
                    paneID: fixture.closedPaneID,
                    expected: .owned(tabID: fixture.tab.tabId),
                    actual: .absent
                )
            }
        )
        try assertRetainedTabCloseStale(
            mutate: { fixture, atoms in
                var changed = fixture.tab
                changed.arrangements[0].name = "stale"
                atoms.tabs.replaceTabStatePreservingIdentity(changed)
            },
            expected: { fixture in
                var changed = fixture.tab
                changed.arrangements[0].name = "stale"
                return .staleTab(
                    tabID: fixture.tab.tabId,
                    expected: fixture.tab,
                    actual: .present(changed)
                )
            }
        )
    }

    @Test("stale arrangement cursor and zoom reject with zero additional mutation")
    func staleCursorAndZoomWitnessesRejectAtomically() throws {
        // Arrange / Act / Assert
        try assertRetainedTabCloseStale(
            mutate: { fixture, atoms in
                atoms.drawerCursor.expandDrawer(drawerId: fixture.pane.drawer!.drawerId)
            },
            expected: { fixture in
                .staleDrawerCursor(
                    expected: .collapsed,
                    actual: .expanded(drawerID: fixture.pane.drawer!.drawerId)
                )
            }
        )
        try assertRetainedTabCloseStale(
            mutate: { fixture, atoms in
                atoms.cursors.setActiveArrangementId(
                    fixture.defaultArrangementID,
                    forTab: fixture.tab.tabId
                )
            },
            expected: { fixture in
                .staleActiveArrangement(
                    tabID: fixture.tab.tabId,
                    expected: .selected(fixture.selectedArrangementID),
                    actual: .selected(fixture.defaultArrangementID)
                )
            }
        )
        try assertRetainedTabCloseStale(
            mutate: { fixture, atoms in
                atoms.cursors.setPaneCursor(
                    .init(activePaneId: fixture.fallbackPaneID),
                    forArrangement: fixture.selectedArrangementID
                )
            },
            expected: { fixture in
                .staleActivePane(
                    arrangementID: fixture.selectedArrangementID,
                    expected: .present(.selected(fixture.closedPaneID)),
                    actual: .present(.selected(fixture.fallbackPaneID))
                )
            }
        )
        try assertRetainedTabCloseStale(
            mutate: { fixture, atoms in
                atoms.presentation.setZoomedPaneId(nil, forTab: fixture.tab.tabId)
            },
            expected: { fixture in
                .staleZoom(
                    tabID: fixture.tab.tabId,
                    expected: .zoomed(fixture.closedPaneID),
                    actual: .notZoomed
                )
            }
        )
    }
}

private struct RetainedTabCloseApplierAtoms {
    let panes: WorkspacePaneGraphAtom
    let drawerCursor: WorkspaceDrawerCursorAtom
    let tabs: WorkspaceTabGraphAtom
    let cursors: WorkspaceArrangementCursorAtom
    let presentation: WorkspacePanePresentationAtom
    let applier: WorkspaceClosePaneInRetainedTabTransitionApplier
}

private struct RetainedTabCloseOwnerSnapshot: Equatable {
    let pane: PaneGraphState?
    let tabs: [TabGraphState]
    let activeArrangements: [UUID: UUID]
    let paneCursors: [UUID: ArrangementPaneCursorState]
    let zooms: [UUID: UUID]
}

@MainActor
private func makeRetainedTabCloseApplierAtoms(
    fixture: RetainedTabCloseFixture,
    unrelated: [TabGraphState] = []
) -> RetainedTabCloseApplierAtoms {
    let panes = WorkspacePaneGraphAtom()
    let drawerCursor = WorkspaceDrawerCursorAtom()
    let tabs = WorkspaceTabGraphAtom()
    let cursors = WorkspaceArrangementCursorAtom()
    let presentation = WorkspacePanePresentationAtom()
    panes.setCanonicalPaneState(fixture.pane)
    tabs.replaceTabStates(unrelated + [fixture.tab])
    cursors.replaceCursors(
        activeArrangementIdsByTabId: [fixture.tab.tabId: fixture.selectedArrangementID],
        paneCursorsByArrangementId: [
            fixture.selectedArrangementID: .init(activePaneId: fixture.closedPaneID),
            fixture.defaultArrangementID: .init(activePaneId: fixture.fallbackPaneID),
        ],
        drawerCursorsByKey: [:]
    )
    presentation.setZoomedPaneId(fixture.closedPaneID, forTab: fixture.tab.tabId)
    return .init(
        panes: panes,
        drawerCursor: drawerCursor,
        tabs: tabs,
        cursors: cursors,
        presentation: presentation,
        applier: .init(
            workspacePaneGraphAtom: panes,
            workspaceDrawerCursorAtom: drawerCursor,
            workspaceTabGraphAtom: tabs,
            workspaceArrangementCursorAtom: cursors,
            workspacePanePresentationAtom: presentation
        )
    )
}

private func plannedRetainedTabCloseTransition(
    _ fixture: RetainedTabCloseFixture,
    zoom: WorkspaceZoomSelection = .zoomed(UUIDv7.generate())
) throws -> WorkspaceClosePaneInRetainedTabTransition {
    try requireRetainedTabCloseTransition(
        WorkspaceClosePaneInRetainedTabTransitionPlanner.plan(
            fixture.request,
            context: fixture.context(zoom: zoom)
        )
    )
}

@MainActor
private func assertRetainedTabCloseStale(
    mutate: (RetainedTabCloseFixture, RetainedTabCloseApplierAtoms) -> Void,
    expected: (RetainedTabCloseFixture) -> WorkspaceClosePaneInRetainedTabApplyRejection
) throws {
    let fixture = makeRetainedTabCloseFixture()
    let atoms = makeRetainedTabCloseApplierAtoms(fixture: fixture)
    let transition = try plannedRetainedTabCloseTransition(
        fixture,
        zoom: .zoomed(fixture.closedPaneID)
    )
    mutate(fixture, atoms)
    let before = retainedTabCloseSnapshot(fixture: fixture, atoms: atoms)

    let result = atoms.applier.apply(transition)

    #expect(result == .rejected(expected(fixture)))
    #expect(retainedTabCloseSnapshot(fixture: fixture, atoms: atoms) == before)
}

@MainActor
private func retainedTabCloseSnapshot(
    fixture: RetainedTabCloseFixture,
    atoms: RetainedTabCloseApplierAtoms
) -> RetainedTabCloseOwnerSnapshot {
    .init(
        pane: atoms.panes.paneState(fixture.closedPaneID),
        tabs: atoms.tabs.tabStates,
        activeArrangements: atoms.cursors.activeArrangementIdsByTabId,
        paneCursors: atoms.cursors.paneCursorsByArrangementId,
        zooms: atoms.presentation.zoomedPaneIdsByTabId
    )
}

private func makeRetainedTabCloseUnrelatedTab(seed: Int) -> TabGraphState {
    let paneID = UUIDv7.generate()
    return .init(
        tabId: UUIDv7.generate(),
        allPaneIds: [paneID],
        arrangements: [
            makeRetainedTabCloseArrangement(
                id: UUIDv7.generate(),
                isDefault: true,
                paneIDs: [paneID]
            )
        ]
    )
}
