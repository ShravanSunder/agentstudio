import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Cross-tab pane move transition applier")
struct WorkspaceCrossTabPaneMoveTransitionApplierTests {
    @Test("apply transfers one owner and preserves 256 unrelated indexed tabs")
    func applyIsStrictAndTargetKeyed() throws {
        // Arrange
        let fixture = makeCrossTabApplierFixture()
        let unrelated = (0..<256).map { makeApplierTab(seed: $0) }
        let atoms = makeCrossTabApplierAtoms(fixture: fixture, unrelated: unrelated)
        let paneBefore = atoms.panes.paneState(fixture.movedPaneID)

        // Act
        let result = atoms.applier.apply(fixture.transition)

        // Assert
        #expect(result == .applied)
        #expect(atoms.panes.paneState(fixture.movedPaneID) == paneBefore)
        #expect(atoms.tabs.tabState(fixture.source.tabId) == fixture.transition.replacementSourceTab)
        #expect(atoms.tabs.tabState(fixture.destination.tabId) == fixture.transition.replacementDestinationTab)
        #expect(atoms.tabs.tabID(containingPane: fixture.movedPaneID) == fixture.destination.tabId)
        #expect(atoms.tabs.tabID(containingPane: fixture.sourceFallbackID) == fixture.source.tabId)
        #expect(atoms.tabs.tabID(containingPane: fixture.targetPaneID) == fixture.destination.tabId)
        #expect(atoms.tabs.tabID(containingArrangement: fixture.sourceActiveID) == fixture.source.tabId)
        #expect(
            atoms.tabs.tabID(containingArrangement: fixture.destinationActiveID)
                == fixture.destination.tabId
        )
        #expect(atoms.cursors.activePaneId(forArrangement: fixture.sourceActiveID) == fixture.sourceFallbackID)
        #expect(atoms.cursors.activePaneId(forArrangement: fixture.destinationActiveID) == fixture.movedPaneID)
        #expect(atoms.cursors.activePaneId(forArrangement: fixture.sourceOtherID) == fixture.sourceFallbackID)
        #expect(
            atoms.cursors.activePaneId(forArrangement: fixture.destinationOtherID)
                == fixture.destinationOtherPaneID
        )
        #expect(atoms.cursors.activeArrangementId(forTab: fixture.source.tabId) == fixture.sourceActiveID)
        #expect(
            atoms.cursors.activeArrangementId(forTab: fixture.destination.tabId)
                == fixture.destinationActiveID
        )
        #expect(atoms.tabCursor.activeTabId == fixture.destination.tabId)
        #expect(atoms.presentation.zoomedPaneId(forTab: fixture.source.tabId) == nil)
        #expect(atoms.presentation.zoomedPaneId(forTab: fixture.destination.tabId) == nil)
        #expect(Array(atoms.tabs.tabStates.prefix(256)) == unrelated)
        for tab in unrelated {
            #expect(atoms.tabs.tabState(tab.tabId) == tab)
            for paneID in tab.allPaneIds {
                #expect(atoms.tabs.tabID(containingPane: paneID) == tab.tabId)
            }
            for arrangement in tab.arrangements {
                #expect(atoms.tabs.tabID(containingArrangement: arrangement.id) == tab.tabId)
            }
        }
    }

    @Test("stale graph and arrangement witnesses reject without further mutation")
    func staleGraphWitnessesRejectAtomically() throws {
        // Arrange / Act / Assert
        try assertCrossTabStale(
            mutate: { fixture, atoms in
                _ = atoms.panes.removeCanonicalPaneState(for: fixture.movedPaneID)
            },
            expected: { fixture in
                .stalePane(
                    paneID: fixture.movedPaneID,
                    expected: .present(fixture.pane),
                    actual: .missing
                )
            }
        )
        try assertCrossTabStale(
            mutate: { fixture, atoms in
                atoms.tabs.replaceTabStatesTransferringPaneOwnership(
                    source: fixture.transition.replacementSourceTab,
                    destination: fixture.transition.replacementDestinationTab
                )
            },
            expected: { fixture in
                .staleOwnership(
                    paneID: fixture.movedPaneID,
                    expected: .owned(tabID: fixture.source.tabId),
                    actual: .owned(tabID: fixture.destination.tabId)
                )
            }
        )
        try assertCrossTabStale(
            mutate: { fixture, atoms in
                var changed = fixture.source
                changed.arrangements[0].name = "stale"
                atoms.tabs.replaceTabStatePreservingIdentity(changed)
            },
            expected: { fixture in
                var changed = fixture.source
                changed.arrangements[0].name = "stale"
                return .staleSourceTab(
                    tabID: fixture.source.tabId,
                    expected: fixture.source,
                    actual: .present(changed)
                )
            }
        )
        try assertCrossTabStale(
            mutate: { fixture, atoms in
                var changed = fixture.destination
                changed.arrangements[0].name = "stale"
                atoms.tabs.replaceTabStatePreservingIdentity(changed)
            },
            expected: { fixture in
                var changed = fixture.destination
                changed.arrangements[0].name = "stale"
                return .staleDestinationTab(
                    tabID: fixture.destination.tabId,
                    expected: fixture.destination,
                    actual: .present(changed)
                )
            }
        )
        try assertCrossTabStale(
            mutate: { fixture, atoms in
                atoms.cursors.setActiveArrangementId(fixture.sourceOtherID, forTab: fixture.source.tabId)
            },
            expected: { fixture in
                .staleActiveArrangement(
                    tabID: fixture.source.tabId,
                    expected: .selected(fixture.sourceActiveID),
                    actual: .selected(fixture.sourceOtherID)
                )
            }
        )
        try assertCrossTabStale(
            mutate: { fixture, atoms in
                atoms.cursors.setActiveArrangementId(
                    fixture.destinationOtherID,
                    forTab: fixture.destination.tabId
                )
            },
            expected: { fixture in
                .staleActiveArrangement(
                    tabID: fixture.destination.tabId,
                    expected: .selected(fixture.destinationActiveID),
                    actual: .selected(fixture.destinationOtherID)
                )
            }
        )
    }

    @Test("stale pane cursor and presentation witnesses reject without further mutation")
    func stalePresentationWitnessesRejectAtomically() throws {
        // Arrange / Act / Assert
        try assertCrossTabStale(
            mutate: { fixture, atoms in
                atoms.cursors.setPaneCursor(
                    .init(activePaneId: fixture.sourceFallbackID),
                    forArrangement: fixture.sourceActiveID
                )
            },
            expected: { fixture in
                .staleActivePane(
                    arrangementID: fixture.sourceActiveID,
                    expected: .present(.selected(fixture.movedPaneID)),
                    actual: .present(.selected(fixture.sourceFallbackID))
                )
            }
        )
        try assertCrossTabStale(
            mutate: { fixture, atoms in
                atoms.cursors.setPaneCursor(
                    .init(activePaneId: fixture.destinationOtherPaneID),
                    forArrangement: fixture.destinationActiveID
                )
            },
            expected: { fixture in
                .staleActivePane(
                    arrangementID: fixture.destinationActiveID,
                    expected: .present(.selected(fixture.targetPaneID)),
                    actual: .present(.selected(fixture.destinationOtherPaneID))
                )
            }
        )
        try assertCrossTabStale(
            mutate: { _, atoms in atoms.tabCursor.replaceActiveTab(nil) },
            expected: { fixture in
                .staleActiveTab(
                    expected: .selected(fixture.source.tabId),
                    actual: .noSelection
                )
            }
        )
        try assertCrossTabStale(
            mutate: { fixture, atoms in
                atoms.presentation.setZoomedPaneId(nil, forTab: fixture.source.tabId)
            },
            expected: { fixture in
                .staleZoom(
                    tabID: fixture.source.tabId,
                    expected: .zoomed(fixture.movedPaneID),
                    actual: .notZoomed
                )
            }
        )
        try assertCrossTabStale(
            mutate: { fixture, atoms in
                atoms.presentation.setZoomedPaneId(nil, forTab: fixture.destination.tabId)
            },
            expected: { fixture in
                .staleZoom(
                    tabID: fixture.destination.tabId,
                    expected: .zoomed(fixture.targetPaneID),
                    actual: .notZoomed
                )
            }
        )
    }

}

private struct CrossTabApplierFixture {
    let movedPaneID: UUID
    let sourceFallbackID: UUID
    let targetPaneID: UUID
    let destinationOtherPaneID: UUID
    let sourceActiveID: UUID
    let sourceOtherID: UUID
    let destinationActiveID: UUID
    let destinationOtherID: UUID
    let pane: PaneGraphState
    let source: TabGraphState
    let destination: TabGraphState
    let sourceCursors: [WorkspaceCrossTabPaneCursorWitness]
    let destinationCursors: [WorkspaceCrossTabPaneCursorWitness]
    let transition: WorkspaceCrossTabPaneMoveTransition
}

private struct CrossTabApplierAtoms {
    let panes: WorkspacePaneGraphAtom
    let tabs: WorkspaceTabGraphAtom
    let cursors: WorkspaceArrangementCursorAtom
    let tabCursor: WorkspaceTabCursorAtom
    let presentation: WorkspacePanePresentationAtom
    let applier: WorkspaceCrossTabPaneMoveTransitionApplier
}

private struct CrossTabOwnerSnapshot: Equatable {
    let pane: PaneGraphState?
    let tabs: [TabGraphState]
    let activeArrangements: [UUID: UUID]
    let paneCursors: [UUID: ArrangementPaneCursorState]
    let activeTabID: UUID?
    let zooms: [UUID: UUID]
}

@MainActor
private func makeCrossTabApplierFixture() -> CrossTabApplierFixture {
    let moved = UUIDv7.generate()
    let fallback = UUIDv7.generate()
    let target = UUIDv7.generate()
    let destinationOtherPane = UUIDv7.generate()
    let sourceActive = UUIDv7.generate()
    let sourceOther = UUIDv7.generate()
    let destinationActive = UUIDv7.generate()
    let destinationOther = UUIDv7.generate()
    let source = TabGraphState(
        tabId: UUIDv7.generate(),
        allPaneIds: [moved, fallback],
        arrangements: [
            makeApplierArrangement(id: sourceActive, isDefault: true, paneIDs: [moved, fallback]),
            makeApplierArrangement(id: sourceOther, isDefault: false, paneIDs: [moved, fallback]),
        ]
    )
    let destination = TabGraphState(
        tabId: UUIDv7.generate(),
        allPaneIds: [target, destinationOtherPane],
        arrangements: [
            makeApplierArrangement(
                id: destinationActive,
                isDefault: true,
                paneIDs: [target, destinationOtherPane]
            ),
            makeApplierArrangement(
                id: destinationOther,
                isDefault: false,
                paneIDs: [destinationOtherPane, target]
            ),
        ]
    )
    let pane = PaneGraphState(
        pane: Pane(
            id: moved,
            content: .terminal(
                TerminalState(provider: .ghostty, lifetime: .temporary, zmxSessionID: .generateUUIDv7())
            ),
            metadata: PaneMetadata(title: "Moved"),
            kind: .layout(drawer: Drawer(drawerId: UUIDv7.generate(), parentPaneId: moved))
        )
    )
    let sourceCursors = [
        WorkspaceCrossTabPaneCursorWitness(
            arrangementID: sourceActive,
            cursor: .present(.selected(moved))
        ),
        WorkspaceCrossTabPaneCursorWitness(
            arrangementID: sourceOther,
            cursor: .present(.selected(fallback))
        ),
    ]
    let destinationCursors = [
        WorkspaceCrossTabPaneCursorWitness(
            arrangementID: destinationActive,
            cursor: .present(.selected(target))
        ),
        WorkspaceCrossTabPaneCursorWitness(
            arrangementID: destinationOther,
            cursor: .present(.selected(destinationOtherPane))
        ),
    ]
    let transition = planCrossTabApplierTransition(
        .init(
            pane: pane,
            source: source,
            destination: destination,
            sourceActiveID: sourceActive,
            destinationActiveID: destinationActive,
            sourceCursors: sourceCursors,
            destinationCursors: destinationCursors,
            movedPaneID: moved,
            targetPaneID: target
        )
    )
    return .init(
        movedPaneID: moved,
        sourceFallbackID: fallback,
        targetPaneID: target,
        destinationOtherPaneID: destinationOtherPane,
        sourceActiveID: sourceActive,
        sourceOtherID: sourceOther,
        destinationActiveID: destinationActive,
        destinationOtherID: destinationOther,
        pane: pane,
        source: source,
        destination: destination,
        sourceCursors: sourceCursors,
        destinationCursors: destinationCursors,
        transition: transition
    )
}

private struct CrossTabTransitionInput {
    let pane: PaneGraphState
    let source: TabGraphState
    let destination: TabGraphState
    let sourceActiveID: UUID
    let destinationActiveID: UUID
    let sourceCursors: [WorkspaceCrossTabPaneCursorWitness]
    let destinationCursors: [WorkspaceCrossTabPaneCursorWitness]
    let movedPaneID: UUID
    let targetPaneID: UUID
}

private func planCrossTabApplierTransition(
    _ input: CrossTabTransitionInput
) -> WorkspaceCrossTabPaneMoveTransition {
    let decision = WorkspaceCrossTabPaneMoveTransitionPlanner.plan(
        .init(
            paneId: input.movedPaneID,
            sourceTabId: input.source.tabId,
            destTabId: input.destination.tabId,
            targetPaneId: input.targetPaneID,
            direction: .vertical,
            position: .after
        ),
        context: .init(
            pane: .present(input.pane),
            ownership: .owned(tabID: input.source.tabId),
            sourceTab: .present(input.source),
            destinationTab: .present(input.destination),
            sourceActiveArrangement: .selected(input.sourceActiveID),
            destinationActiveArrangement: .selected(input.destinationActiveID),
            sourcePaneCursors: input.sourceCursors,
            destinationPaneCursors: input.destinationCursors,
            activeTab: .selected(input.source.tabId),
            sourceZoom: .zoomed(input.movedPaneID),
            destinationZoom: .zoomed(input.targetPaneID)
        )
    )
    guard case .changed(let transition) = decision else {
        preconditionFailure("applier fixture requires a valid cross-tab transition")
    }
    return transition
}

@MainActor
private func makeCrossTabApplierAtoms(
    fixture: CrossTabApplierFixture,
    unrelated: [TabGraphState] = []
) -> CrossTabApplierAtoms {
    let panes = WorkspacePaneGraphAtom()
    let tabs = WorkspaceTabGraphAtom()
    let cursors = WorkspaceArrangementCursorAtom()
    let tabCursor = WorkspaceTabCursorAtom(activeTabId: fixture.source.tabId)
    let presentation = WorkspacePanePresentationAtom()
    panes.setCanonicalPaneState(fixture.pane)
    tabs.replaceTabStates(unrelated + [fixture.source, fixture.destination])
    let witnesses = fixture.sourceCursors + fixture.destinationCursors
    cursors.replaceCursors(
        activeArrangementIdsByTabId: [
            fixture.source.tabId: fixture.sourceActiveID,
            fixture.destination.tabId: fixture.destinationActiveID,
        ],
        paneCursorsByArrangementId: Dictionary(
            uniqueKeysWithValues: witnesses.map { ($0.arrangementID, cursorState($0.cursor)) }
        ),
        drawerCursorsByKey: [:]
    )
    presentation.setZoomedPaneId(fixture.movedPaneID, forTab: fixture.source.tabId)
    presentation.setZoomedPaneId(fixture.targetPaneID, forTab: fixture.destination.tabId)
    return .init(
        panes: panes,
        tabs: tabs,
        cursors: cursors,
        tabCursor: tabCursor,
        presentation: presentation,
        applier: .init(
            workspacePaneGraphAtom: panes,
            workspaceTabGraphAtom: tabs,
            workspaceArrangementCursorAtom: cursors,
            workspaceTabCursorAtom: tabCursor,
            workspacePanePresentationAtom: presentation
        )
    )
}

@MainActor
private func assertCrossTabStale(
    mutate: (CrossTabApplierFixture, CrossTabApplierAtoms) -> Void,
    expected: (CrossTabApplierFixture) -> WorkspaceCrossTabPaneMoveApplyRejection
) throws {
    let fixture = makeCrossTabApplierFixture()
    let atoms = makeCrossTabApplierAtoms(fixture: fixture)
    mutate(fixture, atoms)
    let before = crossTabOwnerSnapshot(fixture: fixture, atoms: atoms)

    let result = atoms.applier.apply(fixture.transition)

    #expect(result == .rejected(expected(fixture)))
    #expect(crossTabOwnerSnapshot(fixture: fixture, atoms: atoms) == before)
}

@MainActor
private func crossTabOwnerSnapshot(
    fixture: CrossTabApplierFixture,
    atoms: CrossTabApplierAtoms
) -> CrossTabOwnerSnapshot {
    .init(
        pane: atoms.panes.paneState(fixture.movedPaneID),
        tabs: atoms.tabs.tabStates,
        activeArrangements: atoms.cursors.activeArrangementIdsByTabId,
        paneCursors: atoms.cursors.paneCursorsByArrangementId,
        activeTabID: atoms.tabCursor.activeTabId,
        zooms: atoms.presentation.zoomedPaneIdsByTabId
    )
}

private func cursorState(_ witness: WorkspaceActivePaneCursorWitness) -> ArrangementPaneCursorState {
    switch witness {
    case .missing, .present(.noSelection): .init(activePaneId: nil)
    case .present(.selected(let paneID)): .init(activePaneId: paneID)
    }
}

private func makeApplierArrangement(
    id: UUID,
    isDefault: Bool,
    paneIDs: [UUID]
) -> PaneArrangementGraphState {
    .init(
        id: id,
        name: isDefault ? "Default" : "Other",
        isDefault: isDefault,
        layout: .autoTiled(paneIDs),
        minimizedPaneIds: [],
        showsMinimizedPanes: false,
        drawerViews: [:]
    )
}

private func makeApplierTab(seed: Int) -> TabGraphState {
    let paneID = UUIDv7.generate()
    return .init(
        tabId: UUIDv7.generate(),
        allPaneIds: [paneID],
        arrangements: [
            makeApplierArrangement(id: UUIDv7.generate(), isDefault: true, paneIDs: [paneID])
        ]
    )
}
