import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace pane residency lifecycle transition applier")
struct WorkspacePaneResidencyApplierTests {
    @Test("applies background transition across exact owners and returns runtime effect")
    func appliesBackgroundTransition() throws {
        // Arrange
        let fixture = makeResidencyFixture()
        let transition = try requireBackgroundTransitionForApplier(fixture)
        let atoms = try makeResidencyAtoms(fixture, graph: fixture.tabState)
        let applier = makeResidencyApplier(atoms)

        // Act
        let result = applier.apply(.background(transition), retainedDrawerPayload: .absent)

        // Assert
        guard case .applied(.replaceRetainedDrawerPayload(let paneID, let payload)) = result else {
            Issue.record("expected applied retained-payload effect")
            return
        }
        #expect(paneID == fixture.parent.id)
        guard case .present = payload else {
            Issue.record("expected retained payload")
            return
        }
        #expect(atoms.panes.paneState(fixture.parent.id)?.residency == .backgrounded)
        #expect(atoms.graph.tabState(fixture.tabID)?.allPaneIds == [fixture.otherPane.id])
        #expect(atoms.cursors.activeArrangementId(forTab: fixture.tabID) == fixture.arrangementIDs[0])
        #expect(atoms.cursors.activePaneId(forArrangement: fixture.arrangementIDs[0]) == fixture.otherPane.id)
        #expect(atoms.presentation.zoomedPaneId(forTab: fixture.tabID) == nil)
    }

    @Test("rejects stale pane before mutating graph cursor or presentation")
    func rejectsStalePaneAtomically() throws {
        // Arrange
        let fixture = makeResidencyFixture()
        let transition = try requireBackgroundTransitionForApplier(fixture)
        let atoms = try makeResidencyAtoms(fixture, graph: fixture.tabState)
        let applier = makeResidencyApplier(atoms)
        atoms.panes.setResidency(.backgrounded, for: fixture.parent.id)

        // Act
        let result = applier.apply(.background(transition), retainedDrawerPayload: .absent)

        // Assert
        guard case .rejected(.stalePane(let paneID, _, _)) = result else {
            Issue.record("expected stale pane rejection")
            return
        }
        #expect(paneID == fixture.parent.id)
        #expect(atoms.graph.tabState(fixture.tabID) == fixture.tabState)
        #expect(atoms.cursors.activePaneId(forArrangement: fixture.arrangementIDs[0]) == fixture.parent.id)
        #expect(atoms.presentation.zoomedPaneId(forTab: fixture.tabID) == fixture.parent.id)
    }

    @Test("rejects stale runtime payload after preflighting all state owners")
    func rejectsStaleRuntimePayloadAtomically() throws {
        // Arrange
        let fixture = makeResidencyFixture()
        let transition = try requireBackgroundTransitionForApplier(fixture)
        let atoms = try makeResidencyAtoms(fixture, graph: fixture.tabState)
        let applier = makeResidencyApplier(atoms)
        let stalePayload = WorkspaceRetainedDrawerPayloadWitness.present(
            .init(drawerID: fixture.drawerID, viewsByArrangementID: [:])
        )

        // Act
        let result = applier.apply(
            .background(transition),
            retainedDrawerPayload: stalePayload
        )

        // Assert
        #expect(result == .rejected(.staleRetainedDrawerPayload(expected: .absent, actual: stalePayload)))
        #expect(atoms.panes.paneState(fixture.parent.id)?.residency == .active)
        #expect(atoms.graph.tabState(fixture.tabID) == fixture.tabState)
    }

    @Test("unrelated pane tab and cursor state survives keyed background application")
    func preservesUnrelatedState() throws {
        // Arrange
        let fixture = makeResidencyFixture()
        let unrelatedPane = makeResidencyUnrelatedPane()
        let unrelatedTabID = UUIDv7.generate()
        let unrelatedArrangementID = UUIDv7.generate()
        let unrelatedGraph = TabGraphState(
            tabId: unrelatedTabID,
            allPaneIds: [unrelatedPane.id],
            arrangements: [
                .init(
                    id: unrelatedArrangementID,
                    name: "Unrelated",
                    isDefault: true,
                    layout: Layout(paneId: unrelatedPane.id),
                    minimizedPaneIds: [],
                    showsMinimizedPanes: true,
                    drawerViews: [:]
                )
            ]
        )
        let transition = try requireBackgroundTransitionForApplier(fixture)
        let atoms = try makeResidencyAtoms(
            fixture,
            graph: fixture.tabState,
            extraPane: unrelatedPane,
            extraGraph: unrelatedGraph
        )
        atoms.cursors.setActiveArrangementId(unrelatedArrangementID, forTab: unrelatedTabID)
        atoms.cursors.setPaneCursor(.init(activePaneId: unrelatedPane.id), forArrangement: unrelatedArrangementID)
        let applier = makeResidencyApplier(atoms)

        // Act
        let result = applier.apply(.background(transition), retainedDrawerPayload: .absent)

        // Assert
        guard case .applied = result else {
            Issue.record("expected applied transition")
            return
        }
        #expect(atoms.panes.paneState(unrelatedPane.id) == unrelatedPane)
        #expect(atoms.graph.tabState(unrelatedTabID) == unrelatedGraph)
        #expect(atoms.cursors.activeArrangementId(forTab: unrelatedTabID) == unrelatedArrangementID)
        #expect(atoms.cursors.activePaneId(forArrangement: unrelatedArrangementID) == unrelatedPane.id)
    }

    @Test("last-tab background removes shell without hidden cursor cascade")
    func lastTabRemovalUsesExplicitCursorTransition() throws {
        // Arrange
        let fixture = makeResidencyFixture(includeOtherPane: false)
        var context = fixture.backgroundContext()
        context = .init(
            pane: context.pane,
            declaredDrawerChildrenByID: context.declaredDrawerChildrenByID,
            ownershipByPaneID: context.ownershipByPaneID,
            tabCursors: context.tabCursors,
            tabRemoval: .current(
                tabShells: [TabShell(id: fixture.tabID, name: "Target")],
                activeTab: .selected(fixture.tabID)
            ),
            retainedDrawerPayload: .absent
        )
        let transition = try requireBackgroundTransitionForApplier(fixture, context: context)
        let atoms = try makeResidencyAtoms(fixture, graph: fixture.tabState)
        let applier = makeResidencyApplier(atoms)

        // Act
        let result = applier.apply(.background(transition), retainedDrawerPayload: .absent)

        // Assert
        guard case .applied = result else {
            Issue.record("expected applied transition")
            return
        }
        #expect(atoms.shells.tabShells.isEmpty)
        #expect(atoms.tabCursor.activeTabId == nil)
        #expect(atoms.graph.tabState(fixture.tabID) == nil)
        #expect(atoms.cursors.activeArrangementId(forTab: fixture.tabID) == nil)
        #expect(fixture.arrangementIDs.allSatisfy { !atoms.cursors.hasPaneCursor(arrangementID: $0) })
    }

    @Test("applies reactivation and returns payload consumption effect")
    func appliesReactivation() throws {
        // Arrange
        let fixture = makeResidencyFixture(parentResidency: .backgrounded)
        let targetGraph = fixture.targetGraphForReactivation()
        let transition = try requireReactivateTransitionForApplier(fixture)
        let atoms = try makeResidencyAtoms(fixture, graph: targetGraph, useReactivationCursors: true)
        let applier = makeResidencyApplier(atoms)

        // Act
        let result = applier.apply(.reactivate(transition), retainedDrawerPayload: .absent)

        // Assert
        #expect(result == .applied(.consumeRetainedDrawerPayloadAndMount(paneID: fixture.parent.id)))
        #expect(atoms.panes.paneState(fixture.parent.id)?.residency == .active)
        #expect(atoms.graph.tabState(fixture.tabID)?.allPaneIds.contains(fixture.parent.id) == true)
        #expect(atoms.cursors.activePaneId(forArrangement: fixture.arrangementIDs[0]) == fixture.parent.id)
        #expect(atoms.presentation.zoomedPaneId(forTab: fixture.tabID) == nil)
    }
}

struct PaneResidencyAtoms {
    let panes: WorkspacePaneGraphAtom
    let shells: WorkspaceTabShellAtom
    let tabCursor: WorkspaceTabCursorAtom
    let graph: WorkspaceTabGraphAtom
    let cursors: WorkspaceArrangementCursorAtom
    let presentation: WorkspacePanePresentationAtom
}

@MainActor
func makeResidencyAtoms(
    _ fixture: PaneResidencyFixture,
    graph: TabGraphState,
    extraPane: PaneGraphState? = nil,
    extraGraph: TabGraphState? = nil,
    useReactivationCursors: Bool = false
) throws -> PaneResidencyAtoms {
    let panes = WorkspacePaneGraphAtom()
    var paneStates = [fixture.parent.id: fixture.parent, fixture.otherPane.id: fixture.otherPane]
    for child in fixture.children { paneStates[child.id] = child }
    if let extraPane { paneStates[extraPane.id] = extraPane }
    guard case .success(let replacement) = WorkspacePaneGraphReplacement.prepare(paneStates) else {
        throw PaneResidencyApplierTestError.invalidPaneGraph
    }
    panes.replacePaneStates(replacement)

    let tabCursor = WorkspaceTabCursorAtom(activeTabId: fixture.tabID)
    let shells = WorkspaceTabShellAtom(cursorAtom: tabCursor)
    var tabShells = [TabShell(id: fixture.tabID, name: "Target")]
    if let extraGraph { tabShells.append(TabShell(id: extraGraph.tabId, name: "Unrelated")) }
    shells.replaceTabShells(tabShells)

    let graphAtom = WorkspaceTabGraphAtom()
    graphAtom.replaceTabStates([graph] + [extraGraph].compactMap { $0 })

    let cursors = WorkspaceArrangementCursorAtom()
    let snapshot = useReactivationCursors ? fixture.targetCursorsForReactivation() : fixture.cursors
    var drawerCursorStates: [ArrangementDrawerCursorKey: ArrangementDrawerCursorState] = [:]
    for (key, witness) in snapshot.activeDrawerChildrenByKey {
        guard case .present(let selection) = witness else { continue }
        let selectedID: UUID?
        switch selection {
        case .noSelection: selectedID = nil
        case .selected(let childID): selectedID = childID
        }
        drawerCursorStates[key] = .init(activeChildId: selectedID)
    }
    cursors.replaceCursors(
        activeArrangementIdsByTabId: [fixture.tabID: fixture.arrangementIDs[0]],
        paneCursorsByArrangementId: snapshot.activePanesByArrangementID.mapValues { witness in
            guard case .present(let selection) = witness else { return .init(activePaneId: nil) }
            switch selection {
            case .noSelection: return .init(activePaneId: nil)
            case .selected(let paneID): return .init(activePaneId: paneID)
            }
        },
        drawerCursorsByKey: drawerCursorStates
    )
    let presentation = WorkspacePanePresentationAtom()
    switch snapshot.zoom {
    case .notZoomed: break
    case .zoomed(let paneID): presentation.setZoomedPaneId(paneID, forTab: fixture.tabID)
    }
    return .init(
        panes: panes,
        shells: shells,
        tabCursor: tabCursor,
        graph: graphAtom,
        cursors: cursors,
        presentation: presentation
    )
}

@MainActor
func makeResidencyApplier(
    _ atoms: PaneResidencyAtoms
) -> WorkspacePaneResidencyLifecycleTransitionApplier {
    .init(
        workspacePaneGraphAtom: atoms.panes,
        workspaceTabShellAtom: atoms.shells,
        workspaceTabCursorAtom: atoms.tabCursor,
        workspaceTabGraphAtom: atoms.graph,
        workspaceArrangementCursorAtom: atoms.cursors,
        workspacePanePresentationAtom: atoms.presentation
    )
}

func requireBackgroundTransitionForApplier(
    _ fixture: PaneResidencyFixture,
    context: WorkspaceBackgroundPanePlanningContext? = nil
) throws -> WorkspaceBackgroundPaneTransition {
    guard
        case .changed(.background(let transition)) = WorkspaceBackgroundPaneTransitionPlanner.plan(
            .init(paneID: fixture.parent.id), context: context ?? fixture.backgroundContext()
        )
    else {
        throw PaneResidencyApplierTestError.expectedTransition
    }
    return transition
}

func requireReactivateTransitionForApplier(
    _ fixture: PaneResidencyFixture
) throws -> WorkspaceReactivatePaneTransition {
    guard
        case .changed(.reactivate(let transition)) = WorkspaceReactivatePaneTransitionPlanner.plan(
            fixture.reactivateRequest(), context: fixture.reactivateContext()
        )
    else {
        throw PaneResidencyApplierTestError.expectedTransition
    }
    return transition
}

private func makeResidencyUnrelatedPane() -> PaneGraphState {
    let id = UUIDv7.generate()
    return PaneGraphState(
        pane: Pane(
            id: id,
            content: .terminal(
                TerminalState(provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7())
            ),
            metadata: PaneMetadata(title: "Unrelated")
        )
    )
}

private enum PaneResidencyApplierTestError: Error {
    case expectedTransition
    case invalidPaneGraph
}
