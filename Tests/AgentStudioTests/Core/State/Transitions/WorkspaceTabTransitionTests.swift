import Foundation
import Testing

@testable import AgentStudio

@Suite("Workspace tab transitions")
struct WorkspaceTabTransitionTests {
    @Test("append produces exact shell, graph, and explicit cursor insertions")
    func appendProducesExactInsertions() {
        // Arrange
        let fixture = makeComplexTabFixture()
        let context = makeAppendContext(for: fixture)

        // Act
        let decision = WorkspaceAppendTabTransitionDecider.decide(
            tab: fixture.tab,
            context: context
        )

        // Assert
        guard case .changed(let transition) = decision else {
            Issue.record("expected one changed append-tab transition")
            return
        }
        #expect(
            transition.shell
                == .insert(
                    TabShell(id: fixture.tab.id, name: fixture.tab.name, colorHex: fixture.tab.colorHex),
                    at: 0
                )
        )
        #expect(transition.activeTab == .select(fixture.tab.id))
        #expect(
            transition.graph
                == .insert(
                    TabGraphState(
                        tabId: fixture.tab.id,
                        allPaneIds: fixture.tab.allPaneIds,
                        arrangements: fixture.tab.arrangements.map(PaneArrangementGraphState.init)
                    ),
                    at: 0
                )
        )
        #expect(
            transition.activeArrangement
                == .insert(tabID: fixture.tab.id, arrangementID: fixture.secondArrangementID)
        )
        #expect(
            transition.activePanes == [
                .insert(
                    arrangementID: fixture.firstArrangementID,
                    selection: .selected(fixture.firstPaneID)
                ),
                .insert(
                    arrangementID: fixture.secondArrangementID,
                    selection: .noSelection
                ),
            ]
        )
        #expect(
            transition.activeDrawerChildren == [
                .insert(
                    key: ArrangementDrawerCursorKey(
                        arrangementId: fixture.firstArrangementID,
                        drawerId: fixture.firstDrawerID
                    ),
                    selection: .selected(fixture.firstDrawerPaneID)
                ),
                .insert(
                    key: ArrangementDrawerCursorKey(
                        arrangementId: fixture.secondArrangementID,
                        drawerId: fixture.secondDrawerID
                    ),
                    selection: .noSelection
                ),
            ]
        )
    }

    @Test("append footprint contains only incoming keys with 300 unrelated tabs")
    func appendFootprintExcludesUnrelatedFleet() throws {
        // Arrange
        let fixture = makeComplexTabFixture()
        var orderedTabIDs: [UUID] = []
        var paneOwners: [UUID: UUID] = [:]
        var additionalPanePlacementDescriptors: [WorkspacePanePlacementDescriptor] = []
        var arrangementIDs: Set<UUID> = []
        var activeArrangementTabIDs: Set<UUID> = []
        var activePaneArrangementIDs: Set<UUID> = []
        var drawerCursorKeys: Set<ArrangementDrawerCursorKey> = []
        var firstTabID: UUID?

        for _ in 0..<300 {
            let tabID = UUIDv7.generate()
            let paneID = UUIDv7.generate()
            let arrangementID = UUIDv7.generate()
            let drawerKey = ArrangementDrawerCursorKey(
                arrangementId: arrangementID,
                drawerId: UUIDv7.generate()
            )
            firstTabID = firstTabID ?? tabID
            orderedTabIDs.append(tabID)
            paneOwners[paneID] = tabID
            additionalPanePlacementDescriptors.append(
                .mainLayout(paneID: paneID)
            )
            arrangementIDs.insert(arrangementID)
            activeArrangementTabIDs.insert(tabID)
            activePaneArrangementIDs.insert(arrangementID)
            drawerCursorKeys.insert(drawerKey)
        }
        let selectedTabID = try #require(firstTabID)
        let context = makeAppendContext(
            for: fixture,
            activeTab: .selected(selectedTabID),
            orderedTabIDs: orderedTabIDs,
            paneOwners: paneOwners,
            additionalPanePlacementDescriptors: additionalPanePlacementDescriptors,
            arrangementIDs: arrangementIDs,
            activeArrangementTabIDs: activeArrangementTabIDs,
            activePaneArrangementIDs: activePaneArrangementIDs,
            drawerCursorKeys: drawerCursorKeys
        )

        // Act
        let decision = WorkspaceAppendTabTransitionDecider.decide(
            tab: fixture.tab,
            context: context
        )

        // Assert
        guard case .changed(let transition) = decision else {
            Issue.record("expected one changed append-tab transition")
            return
        }
        #expect(transition.activePanes.count == fixture.tab.arrangements.count)
        #expect(
            transition.activeDrawerChildren.count
                == fixture.tab.arrangements.reduce(0) { $0 + $1.drawerViews.count }
        )
        #expect(
            transition.activePanes.allSatisfy { insertion in
                guard case .insert(let arrangementID, _) = insertion else { return false }
                return !arrangementIDs.contains(arrangementID)
            }
        )
        #expect(
            transition.activeDrawerChildren.allSatisfy { insertion in
                guard case .insert(let key, _) = insertion else { return false }
                return !drawerCursorKeys.contains(key)
            }
        )
        guard case .insert(let graph, _) = transition.graph else {
            Issue.record("expected one graph insertion")
            return
        }
        #expect(graph.tabId == fixture.tab.id)
        #expect(Set(graph.allPaneIds).isDisjoint(with: Set(paneOwners.keys)))
    }

    @Test("append rejects duplicate and conflicting tab, pane, and arrangement keys atomically")
    func appendRejectsDuplicateAndConflictingKeys() {
        // Arrange
        let fixture = makeComplexTabFixture()
        var duplicatePaneTab = fixture.tab
        duplicatePaneTab.allPaneIds.append(fixture.firstPaneID)
        var duplicateArrangementTab = fixture.tab
        duplicateArrangementTab.arrangements[1] = copying(
            duplicateArrangementTab.arrangements[1],
            id: fixture.firstArrangementID
        )

        // Act / Assert
        #expect(
            WorkspaceAppendTabTransitionDecider.decide(
                tab: fixture.tab,
                context: makeAppendContext(for: fixture, orderedTabIDs: [fixture.tab.id])
            ) == .rejected(.duplicateTabShellID(fixture.tab.id))
        )
        #expect(
            WorkspaceAppendTabTransitionDecider.decide(
                tab: duplicatePaneTab,
                context: makeAppendContext(for: fixture)
            ) == .rejected(.duplicatePaneMembership(fixture.firstPaneID))
        )
        #expect(
            WorkspaceAppendTabTransitionDecider.decide(
                tab: duplicateArrangementTab,
                context: makeAppendContext(for: fixture)
            ) == .rejected(.duplicateArrangementID(fixture.firstArrangementID))
        )
    }

    @Test("append rejects a pane already owned by another tab atomically")
    func appendRejectsExistingPaneOwnership() {
        // Arrange
        let fixture = makeComplexTabFixture()
        let owningTabID = UUIDv7.generate()
        let context = makeAppendContext(
            for: fixture,
            paneOwners: [fixture.firstPaneID: owningTabID]
        )

        // Act
        let decision = WorkspaceAppendTabTransitionDecider.decide(
            tab: fixture.tab,
            context: context
        )

        // Assert
        #expect(
            decision
                == .rejected(
                    .paneAlreadyOwned(
                        paneID: fixture.firstPaneID,
                        ownerTabID: owningTabID
                    )
                )
        )
    }

    @Test("append rejects an invalid active arrangement atomically")
    func appendRejectsInvalidActiveArrangement() {
        // Arrange
        var fixture = makeComplexTabFixture()
        let missingArrangementID = UUIDv7.generate()
        fixture.tab.activeArrangementId = missingArrangementID

        // Act
        let decision = WorkspaceAppendTabTransitionDecider.decide(
            tab: fixture.tab,
            context: makeAppendContext(for: fixture)
        )

        // Assert
        #expect(
            decision
                == .rejected(
                    .invalidActiveArrangement(
                        tabID: fixture.tab.id,
                        arrangementID: missingArrangementID
                    )
                )
        )
    }

    @Test("append rejects an invalid active pane selection atomically")
    func appendRejectsInvalidActivePaneSelection() {
        // Arrange
        var fixture = makeComplexTabFixture()
        let missingPaneID = UUIDv7.generate()
        fixture.tab.arrangements[0].activePaneId = missingPaneID

        // Act
        let decision = WorkspaceAppendTabTransitionDecider.decide(
            tab: fixture.tab,
            context: makeAppendContext(for: fixture)
        )

        // Assert
        #expect(
            decision
                == .rejected(
                    .invalidActivePaneSelection(
                        arrangementID: fixture.firstArrangementID,
                        paneID: missingPaneID
                    )
                )
        )
    }

    @Test("append rejects an invalid active drawer selection atomically")
    func appendRejectsInvalidActiveDrawerSelection() {
        // Arrange
        var fixture = makeComplexTabFixture()
        let missingPaneID = UUIDv7.generate()
        fixture.tab.arrangements[0].drawerViews[fixture.firstDrawerID]?.activeChildId = missingPaneID
        let key = ArrangementDrawerCursorKey(
            arrangementId: fixture.firstArrangementID,
            drawerId: fixture.firstDrawerID
        )

        // Act
        let decision = WorkspaceAppendTabTransitionDecider.decide(
            tab: fixture.tab,
            context: makeAppendContext(for: fixture)
        )

        // Assert
        #expect(
            decision
                == .rejected(
                    .invalidActiveDrawerChildSelection(
                        key: key,
                        paneID: missingPaneID
                    )
                )
        )
    }

    @Test("append rejects existing arrangement and cursor keys atomically")
    func appendRejectsExistingArrangementAndCursorKeys() {
        // Arrange
        let fixture = makeComplexTabFixture()
        let drawerKey = ArrangementDrawerCursorKey(
            arrangementId: fixture.firstArrangementID,
            drawerId: fixture.firstDrawerID
        )

        // Act / Assert
        #expect(
            WorkspaceAppendTabTransitionDecider.decide(
                tab: fixture.tab,
                context: makeAppendContext(for: fixture, arrangementIDs: [fixture.firstArrangementID])
            ) == .rejected(.existingArrangementID(fixture.firstArrangementID))
        )
        #expect(
            WorkspaceAppendTabTransitionDecider.decide(
                tab: fixture.tab,
                context: makeAppendContext(for: fixture, activeArrangementTabIDs: [fixture.tab.id])
            ) == .rejected(.existingActiveArrangementCursor(tabID: fixture.tab.id))
        )
        #expect(
            WorkspaceAppendTabTransitionDecider.decide(
                tab: fixture.tab,
                context: makeAppendContext(
                    for: fixture,
                    activePaneArrangementIDs: [fixture.firstArrangementID]
                )
            ) == .rejected(.existingActivePaneCursor(arrangementID: fixture.firstArrangementID))
        )
        #expect(
            WorkspaceAppendTabTransitionDecider.decide(
                tab: fixture.tab,
                context: makeAppendContext(for: fixture, drawerCursorKeys: [drawerKey])
            ) == .rejected(.existingActiveDrawerChildCursor(key: drawerKey))
        )
    }

}

private func copying(_ arrangement: PaneArrangement, id: UUID) -> PaneArrangement {
    var copy = PaneArrangement(
        id: id,
        name: arrangement.name,
        isDefault: arrangement.isDefault,
        layout: arrangement.layout,
        minimizedPaneIds: arrangement.minimizedPaneIds,
        showsMinimizedPanes: arrangement.showsMinimizedPanes,
        activePaneId: arrangement.activePaneId,
        drawerViews: arrangement.drawerViews
    )
    copy.activePaneId = arrangement.activePaneId
    return copy
}
