import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace arrangement lifecycle transition applier")
struct ArrangementLifecycleApplierTests {
    @Test("stale create preflight rejects atomically")
    func staleCreatePreflightRejectsAtomically() {
        // Arrange
        let fixture = makeArrangementLifecycleFixture()
        let newID = preparedArrangementID()
        guard
            case .changed(let transition) = WorkspaceArrangementLifecycleTransitionPlanner.planCreate(
                .init(tabID: fixture.tab.tabId, arrangementID: newID, name: "Created"),
                context: fixture.createContext(newID: newID)
            )
        else {
            Issue.record("expected create transition")
            return
        }
        let owners = makeArrangementLifecycleOwners(fixture: fixture)
        let applier = WorkspaceArrangementLifecycleTransitionApplier(
            workspaceTabGraphAtom: owners.graph,
            workspaceArrangementCursorAtom: owners.cursors
        )
        owners.cursors.setPaneCursor(
            .init(activePaneId: fixture.mainPaneIDs[1]),
            forArrangement: fixture.activeArrangement.id
        )
        let graphBefore = owners.graph.tabStates

        // Act
        owners.cursors.setPaneCursor(
            .init(activePaneId: nil),
            forArrangement: fixture.activeArrangement.id
        )
        let result = applier.preflight(transition)

        // Assert
        guard case .rejected(.stalePaneCursor) = result else {
            Issue.record("expected stale pane cursor rejection")
            return
        }
        #expect(owners.graph.tabStates == graphBefore)
        #expect(owners.graph.tabID(containingArrangement: newID.rawValue) == nil)
        #expect(owners.cursors.hasPaneCursor(arrangementID: newID.rawValue) == false)
    }

    @Test("create and remove update reverse indexes while preserving a 256-tab fleet")
    func createAndRemovePreserveFleetAndIndexes() {
        // Arrange
        let fixture = makeArrangementLifecycleFixture()
        let unrelated = (0..<256).map { _ in makeArrangementLifecycleFixture().tab }
        let newID = preparedArrangementID()
        guard
            case .changed(let create) = WorkspaceArrangementLifecycleTransitionPlanner.planCreate(
                .init(tabID: fixture.tab.tabId, arrangementID: newID, name: "Created"),
                context: fixture.createContext(newID: newID)
            )
        else {
            Issue.record("expected create transition")
            return
        }
        let owners = makeArrangementLifecycleOwners(fixture: fixture, unrelated: unrelated)
        let applier = WorkspaceArrangementLifecycleTransitionApplier(
            workspaceTabGraphAtom: owners.graph,
            workspaceArrangementCursorAtom: owners.cursors
        )

        // Act
        let createResult = applier.apply(create)
        let createdTab = owners.graph.tabState(fixture.tab.tabId)!
        let createdArrangementOwner = owners.graph.tabID(containingArrangement: newID.rawValue)
        let unrelatedOwnersAfterCreate = unrelated.flatMap { tab in
            tab.arrangements.map { arrangement in
                owners.graph.tabID(containingArrangement: arrangement.id)
            }
        }
        let removeContext = WorkspaceRemoveArrangementPlanningContext.selectedActiveArrangement(
            .init(
                tab: createdTab,
                arrangementID: fixture.activeArrangement.id,
                targetPaneCursor: .present(.selected(fixture.mainPaneIDs[1])),
                targetDrawerCursors: [
                    .init(drawerID: fixture.drawerID, cursor: .present(.selected(fixture.drawerPaneIDs[0])))
                ],
                defaultArrangement: .selected(fixture.defaultArrangement.id)
            )
        )
        guard
            case .changed(let remove) = WorkspaceArrangementLifecycleTransitionPlanner.planRemove(
                .init(tabID: fixture.tab.tabId, arrangementID: newID.rawValue),
                context: .selectedActiveArrangement(
                    .init(
                        tab: createdTab,
                        arrangementID: fixture.activeArrangement.id,
                        targetPaneCursor: .present(.selected(fixture.mainPaneIDs[1])),
                        targetDrawerCursors: [
                            .init(
                                drawerID: fixture.drawerID,
                                cursor: .present(.selected(fixture.drawerPaneIDs[0]))
                            )
                        ],
                        defaultArrangement: .selected(fixture.defaultArrangement.id)
                    )
                )
            )
        else {
            _ = removeContext
            Issue.record("expected remove transition")
            return
        }
        let removeResult = applier.apply(remove)

        // Assert
        #expect(createResult == .applied)
        #expect(removeResult == .applied)
        #expect(createdArrangementOwner == fixture.tab.tabId)
        #expect(owners.graph.tabID(containingArrangement: newID.rawValue) == nil)
        #expect(owners.cursors.hasPaneCursor(arrangementID: newID.rawValue) == false)
        #expect(Array(owners.graph.tabStates.prefix(256)) == unrelated)
        #expect(unrelatedOwnersAfterCreate == unrelated.flatMap { tab in tab.arrangements.map { _ in tab.tabId } })
        for tab in unrelated {
            for arrangement in tab.arrangements {
                #expect(owners.graph.tabID(containingArrangement: arrangement.id) == tab.tabId)
            }
        }
    }

    @Test("active removal selects default without mutating default cursors")
    func activeRemovalPreservesDefaultCursors() {
        // Arrange
        let fixture = makeArrangementLifecycleFixture()
        guard
            case .changed(let transition) = WorkspaceArrangementLifecycleTransitionPlanner.planRemove(
                .init(tabID: fixture.tab.tabId, arrangementID: fixture.activeArrangement.id),
                context: fixture.removeContext(targetArrangementID: fixture.activeArrangement.id)
            )
        else {
            Issue.record("expected active removal transition")
            return
        }
        let owners = makeArrangementLifecycleOwners(fixture: fixture)
        let defaultPaneBefore = owners.cursors.activePaneId(forArrangement: fixture.defaultArrangement.id)
        let defaultDrawerBefore = owners.cursors.activeChildId(
            forArrangement: fixture.defaultArrangement.id,
            drawerId: fixture.drawerID
        )
        let applier = WorkspaceArrangementLifecycleTransitionApplier(
            workspaceTabGraphAtom: owners.graph,
            workspaceArrangementCursorAtom: owners.cursors
        )

        // Act
        let result = applier.apply(transition)

        // Assert
        #expect(result == .applied)
        #expect(
            owners.cursors.activeArrangementId(forTab: fixture.tab.tabId)
                == fixture.defaultArrangement.id
        )
        #expect(owners.cursors.activePaneId(forArrangement: fixture.defaultArrangement.id) == defaultPaneBefore)
        #expect(
            owners.cursors.activeChildId(
                forArrangement: fixture.defaultArrangement.id,
                drawerId: fixture.drawerID
            ) == defaultDrawerBefore
        )
    }
}

@MainActor
private func makeArrangementLifecycleOwners(
    fixture: ArrangementLifecycleFixture,
    unrelated: [TabGraphState] = []
) -> (graph: WorkspaceTabGraphAtom, cursors: WorkspaceArrangementCursorAtom) {
    let graph = WorkspaceTabGraphAtom()
    graph.replaceTabStates(unrelated + [fixture.tab])
    let cursors = WorkspaceArrangementCursorAtom()
    var activeArrangements = [fixture.tab.tabId: fixture.activeArrangement.id]
    var paneCursors: [UUID: ArrangementPaneCursorState] = [:]
    var drawerCursors: [ArrangementDrawerCursorKey: ArrangementDrawerCursorState] = [:]
    for unrelatedTab in unrelated {
        let arrangement = unrelatedTab.arrangements[0]
        activeArrangements[unrelatedTab.tabId] = arrangement.id
        paneCursors[arrangement.id] = .init(activePaneId: arrangement.layout.paneIds.first)
        for (drawerID, drawer) in arrangement.drawerViews {
            drawerCursors[.init(arrangementId: arrangement.id, drawerId: drawerID)] = .init(
                activeChildId: drawer.layout.paneIds.first
            )
        }
    }
    for arrangement in fixture.tab.arrangements {
        paneCursors[arrangement.id] = .init(activePaneId: fixture.mainPaneIDs[1])
        drawerCursors[.init(arrangementId: arrangement.id, drawerId: fixture.drawerID)] = .init(
            activeChildId: fixture.drawerPaneIDs[0]
        )
    }
    cursors.replaceCursors(
        activeArrangementIdsByTabId: activeArrangements,
        paneCursorsByArrangementId: paneCursors,
        drawerCursorsByKey: drawerCursors
    )
    return (graph, cursors)
}
