import Foundation
import Testing

@testable import AgentStudio

@Suite("Create pane in existing tab transition")
struct WorkspaceCreatePaneInExistingTabTransitionTests {
    @Test("new pane identities require two distinct UUIDv7 values")
    func newPaneIdentitiesAreStrict() {
        // Arrange
        let validPaneID = UUIDv7.generate()
        let validDrawerID = UUIDv7.generate()
        let duplicateIdentity = UUIDv7.generate()
        let nonV7Identity = UUID()

        // Act / Assert
        #expect(
            WorkspaceNewPaneIDs.prepare(paneID: validPaneID, drawerID: validDrawerID)
                == .validated(try! #require(validatedNewPaneIDs(paneID: validPaneID, drawerID: validDrawerID)))
        )
        #expect(
            WorkspaceNewPaneIDs.prepare(paneID: nonV7Identity, drawerID: validDrawerID)
                == .rejected(.nonUUIDv7(identity: .pane, value: nonV7Identity))
        )
        #expect(
            WorkspaceNewPaneIDs.prepare(paneID: validPaneID, drawerID: nonV7Identity)
                == .rejected(.nonUUIDv7(identity: .drawer, value: nonV7Identity))
        )
        #expect(
            WorkspaceNewPaneIDs.prepare(paneID: duplicateIdentity, drawerID: duplicateIdentity)
                == .rejected(.duplicateIdentity(duplicateIdentity))
        )
    }

    @Test("creation inserts the pane into one target tab and preserves the caller zmx identity")
    func creationProducesExactTargetedTransition() throws {
        // Arrange
        let fixture = try makeCreatePaneFixture()
        let storedSessionID = ZmxSessionID.generateUUIDv7()
        let request = fixture.request(
            content: .zmxTerminal(lifetime: .persistent, zmxSessionID: storedSessionID)
        )
        let expectedActiveLayout = try #require(
            fixture.tab.arrangements[0].layout.inserting(
                paneId: fixture.identities.paneID.uuid,
                at: fixture.targetPaneID,
                direction: request.direction,
                position: request.position,
                sizingMode: request.sizingMode
            )
        )
        let inactiveAnchor = try #require(fixture.tab.arrangements[1].layout.paneIds.last)
        let expectedInactiveLayout = try #require(
            fixture.tab.arrangements[1].layout.inserting(
                paneId: fixture.identities.paneID.uuid,
                at: inactiveAnchor,
                direction: .horizontal,
                position: .after,
                sizingMode: .proportional
            )
        )

        // Act
        let decision = WorkspaceCreatePaneInExistingTabTransitionPlanner.plan(
            request,
            context: fixture.context(zoom: .zoomed(fixture.targetPaneID))
        )

        // Assert
        let transition = try requireChangedCreatePaneTransition(decision)
        #expect(transition.previousTab == fixture.tab)
        #expect(transition.replacementTab.allPaneIds == fixture.tab.allPaneIds + [fixture.identities.paneID.uuid])
        #expect(transition.replacementTab.arrangements[0].layout.panes == expectedActiveLayout.panes)
        #expect(transition.replacementTab.arrangements[1].layout.panes == expectedInactiveLayout.panes)
        for (previous, replacement) in zip(
            fixture.tab.arrangements.map(\.layout),
            transition.replacementTab.arrangements.map(\.layout)
        ) {
            #expect(replacement.dividerIds.count == previous.dividerIds.count + 1)
            #expect(Set(previous.dividerIds).isSubset(of: Set(replacement.dividerIds)))
            #expect(replacement.dividerIds.allSatisfy(UUIDv7.isV7))
        }
        #expect(
            transition.replacementTab.arrangements.allSatisfy {
                !$0.minimizedPaneIds.contains(fixture.identities.paneID.uuid)
            })
        #expect(
            transition.activePaneMutations
                == [
                    .replace(
                        arrangementID: fixture.activeArrangementID,
                        previous: .present(.selected(fixture.targetPaneID)),
                        replacement: .selected(fixture.identities.paneID.uuid)
                    ),
                    .witness(
                        arrangementID: fixture.inactiveArrangementID,
                        expected: .present(.selected(fixture.otherPaneID))
                    ),
                ]
        )
        #expect(transition.zoom == .clear(tabID: fixture.tab.tabId, previousPaneID: fixture.targetPaneID))
        #expect(transition.paneInsertion.id == fixture.identities.paneID.uuid)
        #expect(transition.paneInsertion.drawer?.drawerId == fixture.identities.drawerID)
        #expect(transition.paneInsertion.drawer?.parentPaneId == fixture.identities.paneID.uuid)
        guard case .terminal(let terminal) = transition.paneInsertion.content else {
            Issue.record("expected terminal pane content")
            return
        }
        #expect(terminal.zmxSessionID == storedSessionID)
    }

    @Test("not-zoomed creation preserves an exact zoom witness")
    func notZoomedCreationPreservesWitness() throws {
        // Arrange
        let fixture = try makeCreatePaneFixture()

        // Act
        let decision = WorkspaceCreatePaneInExistingTabTransitionPlanner.plan(
            fixture.request(),
            context: fixture.context(zoom: .notZoomed)
        )

        // Assert
        let transition = try requireChangedCreatePaneTransition(decision)
        #expect(transition.zoom == .witness(tabID: fixture.tab.tabId, expected: .notZoomed))
    }

    @Test("target and proposed identity failures are typed")
    func targetAndIdentityFailuresAreTyped() throws {
        // Arrange
        let fixture = try makeCreatePaneFixture()
        let wrongTab = TabGraphState(
            tabId: UUIDv7.generate(),
            allPaneIds: fixture.tab.allPaneIds,
            arrangements: fixture.tab.arrangements
        )

        // Act / Assert
        #expect(
            WorkspaceCreatePaneInExistingTabTransitionPlanner.plan(
                fixture.request(),
                context: fixture.context(targetTab: .missing)
            ) == .rejected(.targetTabMissing(fixture.tab.tabId))
        )
        #expect(
            WorkspaceCreatePaneInExistingTabTransitionPlanner.plan(
                fixture.request(),
                context: fixture.context(targetTab: .present(wrongTab))
            ) == .rejected(.tabIdentityMismatch(expected: fixture.tab.tabId, actual: wrongTab.tabId))
        )
        #expect(
            WorkspaceCreatePaneInExistingTabTransitionPlanner.plan(
                fixture.request(),
                context: fixture.context(proposedPane: .paneGraphOccupied)
            ) == .rejected(.paneIdentityAlreadyExists(fixture.identities.paneID.uuid))
        )
        #expect(
            WorkspaceCreatePaneInExistingTabTransitionPlanner.plan(
                fixture.request(),
                context: fixture.context(proposedDrawer: .owned(parentPaneID: fixture.otherPaneID))
            )
                == .rejected(
                    .drawerIdentityAlreadyOwned(
                        drawerID: fixture.identities.drawerID,
                        parentPaneID: fixture.otherPaneID
                    )
                )
        )
    }

    @Test("active arrangement, target pane, and cursor failures are typed")
    func selectionAndCursorFailuresAreTyped() throws {
        // Arrange
        let fixture = try makeCreatePaneFixture()
        let missingTargetPaneID = UUIDv7.generate()
        let missingTargetRequest = fixture.request(targetPaneID: missingTargetPaneID)
        let duplicateCursor = fixture.cursorWitnesses[0]

        // Act / Assert
        #expect(
            WorkspaceCreatePaneInExistingTabTransitionPlanner.plan(
                fixture.request(),
                context: fixture.context(activeArrangement: .missing)
            ) == .rejected(.activeArrangementMissing(fixture.tab.tabId))
        )
        #expect(
            WorkspaceCreatePaneInExistingTabTransitionPlanner.plan(
                missingTargetRequest,
                context: fixture.context()
            ) == .rejected(.targetPaneMissing(tabID: fixture.tab.tabId, paneID: missingTargetPaneID))
        )
        #expect(
            WorkspaceCreatePaneInExistingTabTransitionPlanner.plan(
                fixture.request(),
                context: fixture.context(activePaneCursors: [duplicateCursor, duplicateCursor])
            ) == .rejected(.cursorArrangementDuplicate(duplicateCursor.arrangementID))
        )
        #expect(
            WorkspaceCreatePaneInExistingTabTransitionPlanner.plan(
                fixture.request(),
                context: fixture.context(activePaneCursors: Array(fixture.cursorWitnesses.prefix(1)))
            ) == .rejected(.cursorMissing(fixture.inactiveArrangementID))
        )
    }

    @Test("duplicate arrangement identities reject without a dictionary trap")
    func duplicateArrangementIdentitiesReject() throws {
        // Arrange
        let fixture = try makeCreatePaneFixture()
        var duplicateTab = fixture.tab
        duplicateTab.arrangements[1] = PaneArrangementGraphState(
            id: fixture.activeArrangementID,
            name: duplicateTab.arrangements[1].name,
            isDefault: false,
            layout: duplicateTab.arrangements[1].layout,
            minimizedPaneIds: [],
            showsMinimizedPanes: false,
            drawerViews: [:]
        )

        // Act
        let decision = WorkspaceCreatePaneInExistingTabTransitionPlanner.plan(
            fixture.request(),
            context: fixture.context(targetTab: .present(duplicateTab))
        )

        // Assert
        #expect(decision == .rejected(.duplicateArrangementIdentity(fixture.activeArrangementID)))
    }
}

struct CreatePaneInExistingTabFixture {
    let identities: WorkspaceNewPaneIDs
    let tab: TabGraphState
    let activeArrangementID: UUID
    let inactiveArrangementID: UUID
    let targetPaneID: UUID
    let otherPaneID: UUID
    let cursorWitnesses: [WorkspaceCreatePaneArrangementCursorWitness]

    func request(
        content: WorkspaceResolvedPaneContent = .ghosttyTerminal(
            lifetime: .temporary,
            zmxSessionID: .generateUUIDv7()
        ),
        targetPaneID: UUID? = nil
    ) -> WorkspaceCreatePaneInExistingTabRequest {
        .init(
            identities: identities,
            content: content,
            metadata: PaneMetadata(title: "Created"),
            residency: .active,
            targetTabID: tab.tabId,
            targetPaneID: targetPaneID ?? self.targetPaneID,
            direction: .vertical,
            position: .after,
            sizingMode: .halveTarget
        )
    }

    func context(
        proposedPane: WorkspaceProposedPaneIdentityWitness = .vacant,
        proposedDrawer: WorkspaceProposedDrawerIdentityWitness = .vacant,
        targetTab: WorkspaceCreatePaneTargetTabWitness? = nil,
        activeArrangement: WorkspaceActiveArrangementSelection? = nil,
        activePaneCursors: [WorkspaceCreatePaneArrangementCursorWitness]? = nil,
        zoom: WorkspaceZoomSelection = .notZoomed
    ) -> WorkspaceCreatePaneInExistingTabPlanningContext {
        .init(
            proposedPane: proposedPane,
            proposedDrawer: proposedDrawer,
            targetTab: targetTab ?? .present(tab),
            activeArrangement: activeArrangement ?? .selected(activeArrangementID),
            activePaneCursors: activePaneCursors ?? cursorWitnesses,
            zoom: zoom
        )
    }
}

func makeCreatePaneFixture() throws -> CreatePaneInExistingTabFixture {
    let paneID = UUIDv7.generate()
    let drawerID = UUIDv7.generate()
    let identities = try #require(validatedNewPaneIDs(paneID: paneID, drawerID: drawerID))
    let targetPaneID = UUIDv7.generate()
    let otherPaneID = UUIDv7.generate()
    let activeArrangementID = UUIDv7.generate()
    let inactiveArrangementID = UUIDv7.generate()
    let activeArrangement = PaneArrangementGraphState(
        id: activeArrangementID,
        name: "Active",
        isDefault: true,
        layout: Layout(
            panes: [
                .init(paneId: targetPaneID, ratio: 0.7),
                .init(paneId: otherPaneID, ratio: 0.3),
            ],
            dividerIds: [UUIDv7.generate()]
        ),
        minimizedPaneIds: [],
        showsMinimizedPanes: false,
        drawerViews: [:]
    )
    let inactiveArrangement = PaneArrangementGraphState(
        id: inactiveArrangementID,
        name: "Inactive",
        isDefault: false,
        layout: Layout(
            panes: [
                .init(paneId: targetPaneID, ratio: 0.4),
                .init(paneId: otherPaneID, ratio: 0.6),
            ],
            dividerIds: [UUIDv7.generate()]
        ),
        minimizedPaneIds: [],
        showsMinimizedPanes: false,
        drawerViews: [:]
    )
    return .init(
        identities: identities,
        tab: .init(
            tabId: UUIDv7.generate(),
            allPaneIds: [targetPaneID, otherPaneID],
            arrangements: [activeArrangement, inactiveArrangement]
        ),
        activeArrangementID: activeArrangementID,
        inactiveArrangementID: inactiveArrangementID,
        targetPaneID: targetPaneID,
        otherPaneID: otherPaneID,
        cursorWitnesses: [
            .init(
                arrangementID: activeArrangementID,
                cursor: .present(.selected(targetPaneID))
            ),
            .init(
                arrangementID: inactiveArrangementID,
                cursor: .present(.selected(otherPaneID))
            ),
        ]
    )
}

private func validatedNewPaneIDs(paneID: UUID, drawerID: UUID) -> WorkspaceNewPaneIDs? {
    guard case .validated(let identities) = WorkspaceNewPaneIDs.prepare(paneID: paneID, drawerID: drawerID) else {
        return nil
    }
    return identities
}

private func requireChangedCreatePaneTransition(
    _ decision: WorkspaceCreatePaneInExistingTabDecision
) throws -> WorkspaceCreatePaneInExistingTabTransition {
    guard case .changed(let transition) = decision else {
        throw CreatePaneInExistingTabTestError.expectedChangedTransition
    }
    return transition
}

private enum CreatePaneInExistingTabTestError: Error {
    case expectedChangedTransition
}
