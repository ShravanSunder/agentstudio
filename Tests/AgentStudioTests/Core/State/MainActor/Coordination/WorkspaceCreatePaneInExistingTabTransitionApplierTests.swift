import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Create pane in existing tab transition applier")
struct ExistingTabPaneCreationApplierTests {
    @Test("apply changes only the target owners and preserves 256 unrelated tab indexes")
    func applyIsTargetKeyed() throws {
        // Arrange
        let fixture = try makeCreatePaneFixture()
        let unrelated = try (0..<256).map { _ in try makeCreatePaneFixture() }
        let atoms = makeCreatePaneApplierAtoms(
            fixture: fixture,
            unrelatedTabs: unrelated.map(\.tab),
            zoom: .zoomed(fixture.targetPaneID)
        )
        let transition = try plannedCreatePaneTransition(
            fixture: fixture,
            context: fixture.context(zoom: .zoomed(fixture.targetPaneID))
        )

        // Act
        let result = atoms.applier.apply(transition)

        // Assert
        #expect(result == .applied)
        #expect(atoms.panes.paneState(transition.paneInsertion.id) == transition.paneInsertion)
        #expect(atoms.tabs.tabState(fixture.tab.tabId) == transition.replacementTab)
        #expect(atoms.tabs.tabID(containingPane: transition.paneInsertion.id) == fixture.tab.tabId)
        #expect(
            atoms.cursors.activePaneId(forArrangement: fixture.activeArrangementID)
                == transition.paneInsertion.id
        )
        #expect(atoms.presentation.zoomedPaneId(forTab: fixture.tab.tabId) == nil)
        #expect(Array(atoms.tabs.tabStates.prefix(256)) == unrelated.map(\.tab))
        for unrelatedFixture in unrelated {
            #expect(atoms.tabs.tabState(unrelatedFixture.tab.tabId) == unrelatedFixture.tab)
            for paneID in unrelatedFixture.tab.allPaneIds {
                #expect(atoms.tabs.tabID(containingPane: paneID) == unrelatedFixture.tab.tabId)
            }
            for arrangement in unrelatedFixture.tab.arrangements {
                #expect(atoms.tabs.tabID(containingArrangement: arrangement.id) == unrelatedFixture.tab.tabId)
            }
        }
    }

    @Test("pane and drawer identity races reject before every owner mutation")
    func identityRacesRejectAtomically() throws {
        // Arrange
        let paneFixture = try makeCreatePaneFixture()
        let paneAtoms = makeCreatePaneApplierAtoms(fixture: paneFixture)
        let paneTransition = try plannedCreatePaneTransition(fixture: paneFixture)
        paneAtoms.panes.setCanonicalPaneState(paneTransition.paneInsertion)

        let drawerFixture = try makeCreatePaneFixture()
        let drawerAtoms = makeCreatePaneApplierAtoms(fixture: drawerFixture)
        let drawerTransition = try plannedCreatePaneTransition(fixture: drawerFixture)
        let occupyingPaneID = UUIDv7.generate()
        let occupyingPane = Pane(
            id: occupyingPaneID,
            content: .webview(WebviewState(url: URL(string: "https://example.com")!)),
            metadata: PaneMetadata(title: "Occupying"),
            kind: .layout(
                drawer: Drawer(
                    drawerId: drawerFixture.identities.drawerID,
                    parentPaneId: occupyingPaneID
                )
            )
        )
        drawerAtoms.panes.setCanonicalPaneState(.init(pane: occupyingPane))

        // Act
        let paneResult = paneAtoms.applier.apply(paneTransition)
        let drawerResult = drawerAtoms.applier.apply(drawerTransition)

        // Assert
        #expect(
            paneResult
                == .rejected(
                    .stalePaneIdentity(
                        paneID: paneTransition.paneInsertion.id,
                        expected: .vacant,
                        actual: .paneGraphOccupied
                    )
                )
        )
        #expect(
            drawerResult
                == .rejected(
                    .staleDrawerIdentity(
                        drawerID: drawerFixture.identities.drawerID,
                        expected: .vacant,
                        actual: .owned(parentPaneID: occupyingPaneID)
                    )
                )
        )
        #expect(paneAtoms.tabs.tabState(paneFixture.tab.tabId) == paneFixture.tab)
        #expect(drawerAtoms.tabs.tabState(drawerFixture.tab.tabId) == drawerFixture.tab)
        #expect(drawerAtoms.panes.paneState(drawerTransition.paneInsertion.id) == nil)
    }

    @Test("missing target and stale cursor reject before pane insertion")
    func missingTargetAndStaleCursorReject() throws {
        // Arrange
        let missingFixture = try makeCreatePaneFixture()
        let missingAtoms = makeCreatePaneApplierAtoms(fixture: missingFixture)
        let missingTransition = try plannedCreatePaneTransition(fixture: missingFixture)
        missingAtoms.tabs.replaceTabStates([])

        let cursorFixture = try makeCreatePaneFixture()
        let cursorAtoms = makeCreatePaneApplierAtoms(fixture: cursorFixture)
        let cursorTransition = try plannedCreatePaneTransition(fixture: cursorFixture)
        cursorAtoms.cursors.setPaneCursor(
            .init(activePaneId: cursorFixture.otherPaneID),
            forArrangement: cursorFixture.activeArrangementID
        )

        // Act
        let missingResult = missingAtoms.applier.apply(missingTransition)
        let cursorResult = cursorAtoms.applier.apply(cursorTransition)

        // Assert
        #expect(
            missingResult
                == .rejected(
                    .staleTabGraph(
                        tabID: missingFixture.tab.tabId,
                        expected: missingFixture.tab,
                        actual: .missing
                    )
                )
        )
        #expect(
            cursorResult
                == .rejected(
                    .staleActivePane(
                        arrangementID: cursorFixture.activeArrangementID,
                        expected: .present(.selected(cursorFixture.targetPaneID)),
                        actual: .present(.selected(cursorFixture.otherPaneID))
                    )
                )
        )
        #expect(missingAtoms.panes.paneState(missingTransition.paneInsertion.id) == nil)
        #expect(cursorAtoms.panes.paneState(cursorTransition.paneInsertion.id) == nil)
    }

    @Test("stale active arrangement and zoom reject before pane insertion")
    func selectionAndZoomRacesReject() throws {
        // Arrange
        let arrangementFixture = try makeCreatePaneFixture()
        let arrangementAtoms = makeCreatePaneApplierAtoms(fixture: arrangementFixture)
        let arrangementTransition = try plannedCreatePaneTransition(fixture: arrangementFixture)
        arrangementAtoms.cursors.setActiveArrangementId(
            arrangementFixture.inactiveArrangementID,
            forTab: arrangementFixture.tab.tabId
        )

        let zoomFixture = try makeCreatePaneFixture()
        let zoomAtoms = makeCreatePaneApplierAtoms(fixture: zoomFixture)
        let zoomTransition = try plannedCreatePaneTransition(fixture: zoomFixture)
        zoomAtoms.presentation.setZoomedPaneId(zoomFixture.targetPaneID, forTab: zoomFixture.tab.tabId)

        // Act
        let arrangementResult = arrangementAtoms.applier.apply(arrangementTransition)
        let zoomResult = zoomAtoms.applier.apply(zoomTransition)

        // Assert
        #expect(
            arrangementResult
                == .rejected(
                    .staleActiveArrangement(
                        tabID: arrangementFixture.tab.tabId,
                        expected: .selected(arrangementFixture.activeArrangementID),
                        actual: .selected(arrangementFixture.inactiveArrangementID)
                    )
                )
        )
        #expect(
            zoomResult
                == .rejected(
                    .staleZoom(
                        tabID: zoomFixture.tab.tabId,
                        expected: .notZoomed,
                        actual: .zoomed(zoomFixture.targetPaneID)
                    )
                )
        )
        #expect(arrangementAtoms.panes.paneState(arrangementTransition.paneInsertion.id) == nil)
        #expect(zoomAtoms.panes.paneState(zoomTransition.paneInsertion.id) == nil)
    }
}

private struct CreatePaneApplierAtoms {
    let panes: WorkspacePaneGraphAtom
    let tabs: WorkspaceTabGraphAtom
    let cursors: WorkspaceArrangementCursorAtom
    let presentation: WorkspacePanePresentationAtom
    let applier: WorkspaceCreatePaneInExistingTabTransitionApplier
}

@MainActor
private func makeCreatePaneApplierAtoms(
    fixture: CreatePaneInExistingTabFixture,
    unrelatedTabs: [TabGraphState] = [],
    zoom: WorkspaceZoomSelection = .notZoomed
) -> CreatePaneApplierAtoms {
    let panes = WorkspacePaneGraphAtom()
    let tabs = WorkspaceTabGraphAtom()
    let cursors = WorkspaceArrangementCursorAtom()
    let presentation = WorkspacePanePresentationAtom()
    tabs.replaceTabStates(unrelatedTabs + [fixture.tab])
    cursors.replaceCursors(
        activeArrangementIdsByTabId: [fixture.tab.tabId: fixture.activeArrangementID],
        paneCursorsByArrangementId: Dictionary(
            uniqueKeysWithValues: fixture.cursorWitnesses.map { witness in
                let paneID: UUID?
                switch witness.cursor {
                case .missing: paneID = nil
                case .present(.noSelection): paneID = nil
                case .present(.selected(let selectedPaneID)): paneID = selectedPaneID
                }
                return (witness.arrangementID, ArrangementPaneCursorState(activePaneId: paneID))
            }
        ),
        drawerCursorsByKey: [:]
    )
    if case .zoomed(let paneID) = zoom {
        presentation.setZoomedPaneId(paneID, forTab: fixture.tab.tabId)
    }
    return .init(
        panes: panes,
        tabs: tabs,
        cursors: cursors,
        presentation: presentation,
        applier: .init(
            workspacePaneGraphAtom: panes,
            workspaceTabGraphAtom: tabs,
            workspaceArrangementCursorAtom: cursors,
            workspacePanePresentationAtom: presentation
        )
    )
}

private func plannedCreatePaneTransition(
    fixture: CreatePaneInExistingTabFixture,
    context: WorkspaceCreatePaneInExistingTabPlanningContext? = nil
) throws -> WorkspaceCreatePaneInExistingTabTransition {
    let decision = WorkspaceCreatePaneInExistingTabTransitionPlanner.plan(
        fixture.request(),
        context: context ?? fixture.context()
    )
    guard case .changed(let transition) = decision else {
        throw CreatePaneApplierTestError.expectedTransition
    }
    return transition
}

private enum CreatePaneApplierTestError: Error {
    case expectedTransition
}
