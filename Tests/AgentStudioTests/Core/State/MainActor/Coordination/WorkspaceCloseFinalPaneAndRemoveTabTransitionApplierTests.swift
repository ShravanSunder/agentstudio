import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Close final pane and remove tab transition applier")
struct FinalPaneTabRemovalApplierTests {
    @Test("apply removes exact owners and preserves 256 unrelated prefix indexes")
    func applyIsAtomicAndTargetKeyed() throws {
        // Arrange
        let fixture = makeFinalPaneRemovalFixture()
        let unrelated = (0..<256).map { makeFinalPaneRemovalUnrelatedTab(seed: $0) }
        let shells = unrelated.map { TabShell(id: $0.tabId, name: "Unrelated") } + [fixture.shells[1]]
        let transition = try requireFinalPaneRemovalTransition(
            WorkspaceFinalPaneTabRemovalPlanner.plan(
                fixture.request,
                context: fixture.context(
                    tabIndex: unrelated.count,
                    shells: shells,
                    activeTab: .selected(fixture.tab.tabId)
                )
            )
        )
        let atoms = makeFinalPaneRemovalAtoms(
            fixture: fixture,
            tabs: unrelated + [fixture.tab],
            shells: shells,
            activeTabID: fixture.tab.tabId
        )

        // Act
        let result = atoms.applier.apply(transition)

        // Assert
        #expect(result == .applied)
        #expect(atoms.panes.paneState(fixture.pane.id) == nil)
        #expect(atoms.tabs.tabState(fixture.tab.tabId) == nil)
        #expect(atoms.shells.tabShell(fixture.tab.tabId) == nil)
        #expect(atoms.tabCursor.activeTabId == unrelated.last?.tabId)
        #expect(atoms.cursors.activeArrangementId(forTab: fixture.tab.tabId) == nil)
        for arrangementID in fixture.arrangementIDs {
            #expect(!atoms.cursors.hasPaneCursor(arrangementID: arrangementID))
        }
        #expect(atoms.presentation.zoomedPaneId(forTab: fixture.tab.tabId) == nil)
        #expect(atoms.tabs.tabStates == unrelated)
        for (index, tab) in unrelated.enumerated() {
            #expect(atoms.tabs.tabIndex(for: tab.tabId) == index)
            #expect(atoms.tabs.tabID(containingPane: tab.allPaneIds[0]) == tab.tabId)
            #expect(atoms.tabs.tabID(containingArrangement: tab.arrangements[0].id) == tab.tabId)
        }
    }

    @Test("every stale owner rejects with zero additional mutation")
    func staleOwnersRejectAtomically() throws {
        // Arrange / Act / Assert
        try assertFinalPaneRemovalStale(
            mutate: { fixture, atoms in
                _ = atoms.panes.removeCanonicalPaneState(for: fixture.pane.id)
            },
            matches: { rejection in
                if case .stalePane = rejection { true } else { false }
            }
        )
        try assertFinalPaneRemovalStale(
            mutate: { fixture, atoms in
                var targetWithoutOwnership = fixture.tab
                targetWithoutOwnership.allPaneIds = []
                atoms.tabs.replaceTabStates(
                    atoms.tabs.tabStates.map {
                        $0.tabId == fixture.tab.tabId ? targetWithoutOwnership : $0
                    }
                )
            },
            matches: { rejection in
                if case .staleOwnership = rejection { true } else { false }
            }
        )
        try assertFinalPaneRemovalStale(
            mutate: { fixture, atoms in
                atoms.tabs.replaceTabStates([
                    fixture.tab,
                    atoms.tabs.tabStates[0],
                    atoms.tabs.tabStates[2],
                ])
            },
            matches: { rejection in
                if case .staleTab = rejection { true } else { false }
            }
        )
        try assertFinalPaneRemovalStale(
            mutate: { fixture, atoms in
                atoms.shells.replaceTabShells([fixture.shells[0], fixture.shells[2], fixture.shells[1]])
            },
            matches: { rejection in
                if case .staleShellRemoval = rejection { true } else { false }
            }
        )
        try assertFinalPaneRemovalStale(
            mutate: { fixture, atoms in
                atoms.tabCursor.replaceActiveTab(fixture.shells[0].id)
            },
            matches: { rejection in
                if case .staleTabCursor = rejection { true } else { false }
            }
        )
        try assertFinalPaneRemovalStale(
            mutate: { fixture, atoms in
                atoms.cursors.setActiveArrangementId(fixture.arrangementIDs[1], forTab: fixture.tab.tabId)
            },
            matches: { rejection in
                if case .staleActiveArrangement = rejection { true } else { false }
            }
        )
        try assertFinalPaneRemovalStale(
            mutate: { fixture, atoms in
                atoms.cursors.setPaneCursor(
                    .init(activePaneId: nil),
                    forArrangement: fixture.arrangementIDs[0]
                )
            },
            matches: { rejection in
                if case .staleActivePane = rejection { true } else { false }
            }
        )
        try assertFinalPaneRemovalStale(
            mutate: { fixture, atoms in
                atoms.cursors.insertDrawerCursor(
                    .init(activeChildId: nil),
                    for: .init(
                        arrangementId: fixture.arrangementIDs[0],
                        drawerId: UUIDv7.generate()
                    )
                )
            },
            matches: { rejection in
                if case .staleArrangementDrawerCursor = rejection { true } else { false }
            }
        )
        try assertFinalPaneRemovalStale(
            mutate: { _, atoms in
                atoms.drawerCursor.expandDrawer(drawerId: UUIDv7.generate())
            },
            matches: { rejection in
                if case .staleDrawerCursor = rejection { true } else { false }
            }
        )
        try assertFinalPaneRemovalStale(
            mutate: { fixture, atoms in
                atoms.presentation.setZoomedPaneId(nil, forTab: fixture.tab.tabId)
            },
            matches: { rejection in
                if case .staleZoom = rejection { true } else { false }
            }
        )
    }
}

@MainActor
private struct FinalPaneRemovalAtoms {
    let panes: WorkspacePaneGraphAtom
    let shells: WorkspaceTabShellAtom
    let tabCursor: WorkspaceTabCursorAtom
    let tabs: WorkspaceTabGraphAtom
    let cursors: WorkspaceArrangementCursorAtom
    let drawerCursor: WorkspaceDrawerCursorAtom
    let presentation: WorkspacePanePresentationAtom
    let applier: WorkspaceFinalPaneTabRemovalApplier
}

private struct FinalPaneRemovalOwnerSnapshot: Equatable {
    let pane: PaneGraphState?
    let shells: [TabShell]
    let activeTab: UUID?
    let tabs: [TabGraphState]
    let activeArrangements: [UUID: UUID]
    let paneCursors: [UUID: ArrangementPaneCursorState]
    let arrangementDrawerCursors: [ArrangementDrawerCursorKey: ArrangementDrawerCursorState]
    let drawerCursor: UUID?
    let zooms: [UUID: UUID]
}

@MainActor
private func makeFinalPaneRemovalAtoms(
    fixture: FinalPaneRemovalFixture,
    tabs: [TabGraphState]? = nil,
    shells: [TabShell]? = nil,
    activeTabID: UUID? = nil
) -> FinalPaneRemovalAtoms {
    let panes = WorkspacePaneGraphAtom()
    let tabCursor = WorkspaceTabCursorAtom(activeTabId: activeTabID ?? fixture.tab.tabId)
    let shellAtom = WorkspaceTabShellAtom(cursorAtom: tabCursor)
    let tabAtom = WorkspaceTabGraphAtom()
    let cursors = WorkspaceArrangementCursorAtom()
    let drawerCursor = WorkspaceDrawerCursorAtom()
    let presentation = WorkspacePanePresentationAtom()
    panes.setCanonicalPaneState(fixture.pane)
    shellAtom.replaceTabShells(shells ?? fixture.shells)
    tabAtom.replaceTabStates(tabs ?? makeFinalPaneRemovalAlignedTabs(fixture))
    cursors.replaceCursors(
        activeArrangementIdsByTabId: [fixture.tab.tabId: fixture.arrangementIDs[0]],
        paneCursorsByArrangementId: [
            fixture.arrangementIDs[0]: .init(activePaneId: fixture.pane.id),
            fixture.arrangementIDs[1]: .init(activePaneId: nil),
        ],
        drawerCursorsByKey: [:]
    )
    presentation.setZoomedPaneId(fixture.pane.id, forTab: fixture.tab.tabId)
    return .init(
        panes: panes,
        shells: shellAtom,
        tabCursor: tabCursor,
        tabs: tabAtom,
        cursors: cursors,
        drawerCursor: drawerCursor,
        presentation: presentation,
        applier: .init(
            workspacePaneGraphAtom: panes,
            workspaceTabShellAtom: shellAtom,
            workspaceTabCursorAtom: tabCursor,
            workspaceTabGraphAtom: tabAtom,
            workspaceArrangementCursorAtom: cursors,
            workspaceDrawerCursorAtom: drawerCursor,
            workspacePanePresentationAtom: presentation
        )
    )
}

@MainActor
private func assertFinalPaneRemovalStale(
    mutate: (FinalPaneRemovalFixture, FinalPaneRemovalAtoms) -> Void,
    matches: (WorkspaceCloseFinalPaneAndRemoveTabApplyRejection) -> Bool
) throws {
    let fixture = makeFinalPaneRemovalFixture()
    let atoms = makeFinalPaneRemovalAtoms(fixture: fixture)
    let transition = try requireFinalPaneRemovalTransition(
        WorkspaceFinalPaneTabRemovalPlanner.plan(
            fixture.request,
            context: fixture.context(activeTab: .selected(fixture.tab.tabId))
        )
    )
    mutate(fixture, atoms)
    let before = finalPaneRemovalSnapshot(fixture: fixture, atoms: atoms)

    let result = atoms.applier.apply(transition)

    guard case .rejected(let rejection) = result else {
        Issue.record("expected stale final-pane removal rejection")
        return
    }
    #expect(matches(rejection))
    #expect(finalPaneRemovalSnapshot(fixture: fixture, atoms: atoms) == before)
}

@MainActor
private func finalPaneRemovalSnapshot(
    fixture: FinalPaneRemovalFixture,
    atoms: FinalPaneRemovalAtoms
) -> FinalPaneRemovalOwnerSnapshot {
    .init(
        pane: atoms.panes.paneState(fixture.pane.id),
        shells: atoms.shells.tabShells,
        activeTab: atoms.tabCursor.activeTabId,
        tabs: atoms.tabs.tabStates,
        activeArrangements: atoms.cursors.activeArrangementIdsByTabId,
        paneCursors: atoms.cursors.paneCursorsByArrangementId,
        arrangementDrawerCursors: atoms.cursors.drawerCursorsByKey,
        drawerCursor: atoms.drawerCursor.expandedDrawerId,
        zooms: atoms.presentation.zoomedPaneIdsByTabId
    )
}

func makeFinalPaneRemovalUnrelatedTab(seed _: Int) -> TabGraphState {
    let paneID = UUIDv7.generate()
    return .init(
        tabId: UUIDv7.generate(),
        allPaneIds: [paneID],
        arrangements: [
            .init(
                id: UUIDv7.generate(),
                name: "Unrelated",
                isDefault: true,
                layout: Layout(paneId: paneID),
                minimizedPaneIds: [],
                showsMinimizedPanes: false,
                drawerViews: [:]
            )
        ]
    )
}

private func makeFinalPaneRemovalAlignedTabs(_ fixture: FinalPaneRemovalFixture) -> [TabGraphState] {
    let prefix = makeFinalPaneRemovalUnrelatedTab(seed: 0)
    let suffix = makeFinalPaneRemovalUnrelatedTab(seed: 1)
    return [
        copyingFinalPaneRemovalTab(prefix, id: fixture.shells[0].id),
        fixture.tab,
        copyingFinalPaneRemovalTab(suffix, id: fixture.shells[2].id),
    ]
}

private func copyingFinalPaneRemovalTab(_ tab: TabGraphState, id: UUID) -> TabGraphState {
    .init(tabId: id, allPaneIds: tab.allPaneIds, arrangements: tab.arrangements)
}
