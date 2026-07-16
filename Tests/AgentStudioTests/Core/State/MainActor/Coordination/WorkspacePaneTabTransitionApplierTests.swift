import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace pane-tab transition applier")
struct WorkspacePaneTabTransitionApplierTests {
    @Test("one synchronous apply exposes the pane and every tab owner")
    func appliesPaneAndTabOwnersSynchronously() throws {
        // Arrange
        let existingFleet = makeExistingTabFleet(count: 1)
        let fixture = try makePaneTabFixture(existingFleet: existingFleet)
        let owners = makeTabOwners(existingFleet: existingFleet)
        let paneGraphAtom = WorkspacePaneGraphAtom()
        let applier = makePaneTabApplier(paneGraphAtom: paneGraphAtom, owners: owners)

        // Act
        let preflight = applier.preflight(
            paneState: fixture.paneState,
            tabTransition: fixture.tabTransition
        )
        let preparation = try requireReadyPreparation(preflight)
        applier.apply(preparation)

        // Assert
        #expect(paneGraphAtom.paneState(fixture.paneState.id) == fixture.paneState)
        #expect(owners.shellAtom.tabShell(fixture.tab.id) == fixture.expectedShell)
        #expect(owners.graphAtom.tabState(fixture.tab.id) == fixture.expectedGraph)
        #expect(
            owners.arrangementCursorAtom.activeArrangementId(forTab: fixture.tab.id)
                == fixture.arrangementID
        )
        #expect(
            owners.arrangementCursorAtom.paneCursorsByArrangementId[fixture.arrangementID]
                == ArrangementPaneCursorState(activePaneId: nil)
        )
        #expect(owners.shellCursorAtom.activeTabId == fixture.tab.id)
    }

    @Test("occupied pane preflight rejects without mutating any owner")
    func occupiedPaneRejectsAtomically() throws {
        // Arrange
        let existingFleet = makeExistingTabFleet(count: 1)
        let fixture = try makePaneTabFixture(existingFleet: existingFleet)
        let owners = makeTabOwners(existingFleet: existingFleet)
        let paneGraphAtom = WorkspacePaneGraphAtom()
        paneGraphAtom.setCanonicalPaneState(fixture.paneState)
        let originalOwners = captureOwnerState(paneGraphAtom: paneGraphAtom, owners: owners)
        let applier = makePaneTabApplier(paneGraphAtom: paneGraphAtom, owners: owners)

        // Act
        let preflight = applier.preflight(
            paneState: fixture.paneState,
            tabTransition: fixture.tabTransition
        )

        // Assert
        #expect(preflight == .rejected(.paneAlreadyExists(fixture.paneState.id)))
        #expect(captureOwnerState(paneGraphAtom: paneGraphAtom, owners: owners) == originalOwners)
    }

    @Test("occupied tab preflight rejects without inserting the pane")
    func occupiedTabRejectsAtomically() throws {
        // Arrange
        let existingFleet = makeExistingTabFleet(count: 1)
        let fixture = try makePaneTabFixture(existingFleet: existingFleet)
        let owners = makeTabOwners(existingFleet: existingFleet)
        owners.shellAtom.replaceTabShells([fixture.expectedShell])
        let paneGraphAtom = WorkspacePaneGraphAtom()
        let originalOwners = captureOwnerState(paneGraphAtom: paneGraphAtom, owners: owners)
        let applier = makePaneTabApplier(paneGraphAtom: paneGraphAtom, owners: owners)

        // Act
        let preflight = applier.preflight(
            paneState: fixture.paneState,
            tabTransition: fixture.tabTransition
        )

        // Assert
        #expect(
            preflight
                == .rejected(
                    .tabTransitionRejected(.tabShellAlreadyExists(fixture.tab.id))
                )
        )
        #expect(captureOwnerState(paneGraphAtom: paneGraphAtom, owners: owners) == originalOwners)
    }

    @Test("occupied cursor preflight rejects without inserting the pane or tab")
    func occupiedCursorRejectsAtomically() throws {
        // Arrange
        let existingFleet = makeExistingTabFleet(count: 1)
        let fixture = try makePaneTabFixture(existingFleet: existingFleet)
        let owners = makeTabOwners(existingFleet: existingFleet)
        owners.arrangementCursorAtom.replaceCursors(
            activeArrangementIdsByTabId: existingFleet.activeArrangementIDsByTabID,
            paneCursorsByArrangementId: existingFleet.paneCursorsByArrangementID.merging(
                [fixture.arrangementID: .init(activePaneId: fixture.paneState.id)],
                uniquingKeysWith: { original, _ in original }
            ),
            drawerCursorsByKey: existingFleet.drawerCursorsByKey
        )
        let paneGraphAtom = WorkspacePaneGraphAtom()
        let originalOwners = captureOwnerState(paneGraphAtom: paneGraphAtom, owners: owners)
        let applier = makePaneTabApplier(paneGraphAtom: paneGraphAtom, owners: owners)

        // Act
        let preflight = applier.preflight(
            paneState: fixture.paneState,
            tabTransition: fixture.tabTransition
        )

        // Assert
        #expect(
            preflight
                == .rejected(
                    .tabTransitionRejected(
                        .activePaneCursorAlreadyExists(fixture.arrangementID)
                    )
                )
        )
        #expect(captureOwnerState(paneGraphAtom: paneGraphAtom, owners: owners) == originalOwners)
    }

    @Test("fixed-size apply preserves 300 unrelated panes and tabs")
    func preservesUnrelatedPaneAndTabFleet() throws {
        // Arrange
        let existingFleet = makeExistingTabFleet(count: 300)
        let fixture = try makePaneTabFixture(existingFleet: existingFleet)
        let owners = makeTabOwners(existingFleet: existingFleet)
        let paneGraphAtom = WorkspacePaneGraphAtom()
        let existingPaneStates = existingFleet.graphs.map { graph in
            makePaneState(
                id: graph.allPaneIds[0],
                title: "Existing \(graph.tabId.uuidString)"
            )
        }
        for paneState in existingPaneStates {
            paneGraphAtom.setCanonicalPaneState(paneState)
        }
        let originalPaneStates = paneGraphAtom.paneStates
        let originalShells = owners.shellAtom.tabShells
        let originalGraphs = owners.graphAtom.tabStates
        let applier = makePaneTabApplier(paneGraphAtom: paneGraphAtom, owners: owners)

        // Act
        let preparation = try requireReadyPreparation(
            applier.preflight(
                paneState: fixture.paneState,
                tabTransition: fixture.tabTransition
            )
        )
        applier.apply(preparation)

        // Assert
        #expect(
            originalPaneStates.allSatisfy {
                paneGraphAtom.paneState($0.key) == $0.value
            }
        )
        #expect(paneGraphAtom.paneStates.count == 301)
        #expect(Array(owners.shellAtom.tabShells.prefix(300)) == originalShells)
        #expect(Array(owners.graphAtom.tabStates.prefix(300)) == originalGraphs)
        #expect(owners.shellAtom.tabShells.count == 301)
        #expect(owners.graphAtom.tabStates.count == 301)
        #expect(
            owners.arrangementCursorAtom.paneCursorsByArrangementId[fixture.arrangementID]
                == ArrangementPaneCursorState(activePaneId: nil)
        )
    }
}

private struct PaneTabFixture {
    let paneState: PaneGraphState
    let tab: Tab
    let arrangementID: UUID
    let tabTransition: WorkspaceTabTransition

    var expectedShell: TabShell {
        TabShell(id: tab.id, name: tab.name, colorHex: tab.colorHex)
    }

    var expectedGraph: TabGraphState {
        TabGraphState(
            tabId: tab.id,
            allPaneIds: tab.allPaneIds,
            arrangements: tab.arrangements.map(PaneArrangementGraphState.init)
        )
    }
}

private struct PaneTabOwnerState: Equatable {
    let paneStates: [UUID: PaneGraphState]
    let shells: [TabShell]
    let graphs: [TabGraphState]
    let activeTabID: UUID?
    let activeArrangements: [UUID: UUID]
    let paneCursors: [UUID: ArrangementPaneCursorState]
    let drawerCursors: [ArrangementDrawerCursorKey: ArrangementDrawerCursorState]
}

@MainActor
private func makePaneTabApplier(
    paneGraphAtom: WorkspacePaneGraphAtom,
    owners: TabOwners
) -> WorkspacePaneTabTransitionApplier {
    WorkspacePaneTabTransitionApplier(
        workspacePaneGraphAtom: paneGraphAtom,
        workspaceTabTransitionApplier: WorkspaceTabTransitionApplier(
            workspaceTabShellAtom: owners.shellAtom,
            workspaceTabGraphAtom: owners.graphAtom,
            workspaceArrangementCursorAtom: owners.arrangementCursorAtom
        )
    )
}

private func makePaneTabFixture(existingFleet: ExistingTabFleet) throws -> PaneTabFixture {
    let paneID = UUIDv7.generate()
    let arrangementID = UUIDv7.generate()
    let paneState = makePaneState(id: paneID, title: "Prospective")
    var arrangement = PaneArrangement(
        id: arrangementID,
        name: "Default",
        isDefault: true,
        layout: Layout(paneId: paneID),
        activePaneId: paneID
    )
    arrangement.activePaneId = nil
    let tab = Tab(
        id: UUIDv7.generate(),
        name: "Prospective tab",
        allPaneIds: [paneID],
        arrangements: [arrangement],
        activeArrangementId: arrangementID
    )
    let alignedTabOwners: WorkspaceAlignedTabOwnerIndex
    switch WorkspaceAlignedTabOwnerIndex.prepare(
        shellTabIDs: existingFleet.shells.map(\.id),
        graphTabIDs: existingFleet.graphs.map(\.tabId)
    ) {
    case .validated(let index):
        alignedTabOwners = index
    case .rejected:
        throw PaneTabFixtureError.invalidExistingFleet
    }
    let panePlacements: WorkspacePanePlacementIndex
    switch WorkspacePanePlacementIndex.prepare([.mainLayout(paneID: paneID)]) {
    case .validated(let index):
        panePlacements = index
    case .rejected:
        throw PaneTabFixtureError.invalidPanePlacement
    }
    let context = WorkspaceAppendTabContext(
        activeTab: existingFleet.shells.last.map { .selected($0.id) } ?? .noSelection,
        alignedTabOwners: alignedTabOwners,
        panePlacements: panePlacements,
        paneOwnerByPaneID: Dictionary(
            uniqueKeysWithValues: existingFleet.graphs.flatMap { graph in
                graph.allPaneIds.map { ($0, graph.tabId) }
            }
        ),
        existingArrangementIDs: Set(existingFleet.graphs.flatMap { $0.arrangements.map(\.id) }),
        existingActiveArrangementTabIDs: Set(existingFleet.activeArrangementIDsByTabID.keys),
        existingActivePaneArrangementIDs: Set(existingFleet.paneCursorsByArrangementID.keys),
        existingActiveDrawerChildKeys: Set(existingFleet.drawerCursorsByKey.keys)
    )
    let tabTransition: WorkspaceTabTransition
    switch WorkspaceAppendTabTransitionDecider.decide(tab: tab, context: context) {
    case .changed(let transition):
        tabTransition = transition
    case .unchanged, .rejected:
        throw PaneTabFixtureError.appendTransitionUnavailable
    }
    return PaneTabFixture(
        paneState: paneState,
        tab: tab,
        arrangementID: arrangementID,
        tabTransition: tabTransition
    )
}

private func makePaneState(id: UUID, title: String) -> PaneGraphState {
    PaneGraphState(
        pane: Pane(
            id: id,
            content: .terminal(.init(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(title: title)
        )
    )
}

@MainActor
private func captureOwnerState(
    paneGraphAtom: WorkspacePaneGraphAtom,
    owners: TabOwners
) -> PaneTabOwnerState {
    PaneTabOwnerState(
        paneStates: paneGraphAtom.paneStates,
        shells: owners.shellAtom.tabShells,
        graphs: owners.graphAtom.tabStates,
        activeTabID: owners.shellCursorAtom.activeTabId,
        activeArrangements: owners.arrangementCursorAtom.activeArrangementIdsByTabId,
        paneCursors: owners.arrangementCursorAtom.paneCursorsByArrangementId,
        drawerCursors: owners.arrangementCursorAtom.drawerCursorsByKey
    )
}

private func requireReadyPreparation(
    _ result: WorkspacePaneTabTransitionPreflightResult
) throws -> WorkspacePreparedPaneTabTransitionApplication {
    switch result {
    case .ready(let preparation):
        preparation
    case .rejected(let rejection):
        Issue.record("expected ready aggregate preparation, got \(rejection)")
        throw PaneTabFixtureError.aggregatePreflightRejected
    }
}

private enum PaneTabFixtureError: Error {
    case invalidExistingFleet
    case invalidPanePlacement
    case appendTransitionUnavailable
    case aggregatePreflightRejected
}
