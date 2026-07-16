import Foundation
import Testing

@testable import AgentStudio

@Suite("Workspace append-tab validation context")
struct WorkspaceAppendTabValidationContextTests {
    @Test("aligned owner preparation rejects duplicate, set, and order divergence")
    func alignedOwnerPreparationRejectsDivergence() {
        // Arrange
        let firstTabID = UUIDv7.generate()
        let secondTabID = UUIDv7.generate()
        let thirdTabID = UUIDv7.generate()

        // Act / Assert
        #expect(
            WorkspaceAlignedTabOwnerIndex.prepare(
                shellTabIDs: [firstTabID, firstTabID],
                graphTabIDs: [firstTabID, firstTabID]
            ) == .rejected(.duplicateShellTabID(firstTabID))
        )
        #expect(
            WorkspaceAlignedTabOwnerIndex.prepare(
                shellTabIDs: [firstTabID, secondTabID],
                graphTabIDs: [firstTabID, firstTabID]
            ) == .rejected(.duplicateGraphTabID(firstTabID))
        )
        #expect(
            WorkspaceAlignedTabOwnerIndex.prepare(
                shellTabIDs: [firstTabID, secondTabID],
                graphTabIDs: [firstTabID, thirdTabID]
            )
                == .rejected(
                    .tabIDSetMismatch(
                        shellOnly: [secondTabID],
                        graphOnly: [thirdTabID]
                    )
                )
        )
        #expect(
            WorkspaceAlignedTabOwnerIndex.prepare(
                shellTabIDs: [firstTabID, secondTabID],
                graphTabIDs: [secondTabID, firstTabID]
            )
                == .rejected(
                    .tabOrderMismatch(
                        index: 0,
                        shellTabID: firstTabID,
                        graphTabID: secondTabID
                    )
                )
        )
    }

    @Test("aligned owner preparation exposes O(1) count and membership")
    func alignedOwnerPreparationExposesIndexedLookup() {
        // Arrange
        let firstTabID = UUIDv7.generate()
        let secondTabID = UUIDv7.generate()

        // Act
        let preparation = WorkspaceAlignedTabOwnerIndex.prepare(
            shellTabIDs: [firstTabID, secondTabID],
            graphTabIDs: [firstTabID, secondTabID]
        )

        // Assert
        guard case .validated(let index) = preparation else {
            Issue.record("expected aligned owner preparation")
            return
        }
        #expect(index.count == 2)
        #expect(index.contains(firstTabID))
        #expect(!index.contains(UUIDv7.generate()))
    }

    @Test("pane placement preparation exposes strict pane and drawer lookups")
    func panePlacementPreparationExposesStrictLookups() {
        // Arrange
        let parentPaneID = UUIDv7.generate()
        let ordinaryPaneID = UUIDv7.generate()
        let childPaneID = UUIDv7.generate()
        let drawerID = UUIDv7.generate()

        // Act
        let preparation = WorkspacePanePlacementIndex.prepare([
            .mainLayout(paneID: ordinaryPaneID),
            .drawerParent(
                paneID: parentPaneID,
                drawerID: drawerID,
                drawerChildPaneIDs: [childPaneID]
            ),
            .drawerChild(paneID: childPaneID, parentPaneID: parentPaneID),
        ])

        // Assert
        guard case .validated(let index) = preparation else {
            Issue.record("expected pane placement preparation")
            return
        }
        #expect(index.placement(for: ordinaryPaneID) == .mainLayout)
        #expect(index.placement(for: parentPaneID) == .drawerParent(drawerID: drawerID))
        #expect(index.placement(for: childPaneID) == .drawerChild(parentPaneID: parentPaneID))
        #expect(index.placement(for: UUIDv7.generate()) == .missing)
        #expect(
            index.drawer(for: drawerID)
                == .found(
                    WorkspaceDrawerPlacementCapability(
                        parentPaneID: parentPaneID,
                        childPaneIDs: [childPaneID]
                    )
                )
        )
        #expect(index.drawer(for: UUIDv7.generate()) == .missing)
    }

    @Test("ordinary main pane without a drawer capability can append")
    func ordinaryMainPaneCanAppend() {
        // Arrange
        let paneID = UUIDv7.generate()
        let tab = Tab(id: UUIDv7.generate(), paneId: paneID)
        let context = makeAppendContext(
            panePlacementDescriptors: [.mainLayout(paneID: paneID)]
        )

        // Act
        let decision = WorkspaceAppendTabTransitionDecider.decide(
            tab: tab,
            context: context
        )

        // Assert
        guard case .changed(let transition) = decision else {
            Issue.record("expected ordinary main pane append")
            return
        }
        #expect(transition.activePanes.count == 1)
        #expect(transition.activeDrawerChildren.isEmpty)
    }

    @Test("pane placement preparation rejects cross-owner descriptor graphs")
    func panePlacementPreparationRejectsCrossOwnerDescriptors() {
        // Arrange
        let firstParentPaneID = UUIDv7.generate()
        let secondParentPaneID = UUIDv7.generate()
        let childPaneID = UUIDv7.generate()

        // Act
        let preparation = WorkspacePanePlacementIndex.prepare([
            .drawerParent(
                paneID: firstParentPaneID,
                drawerID: UUIDv7.generate(),
                drawerChildPaneIDs: [childPaneID]
            ),
            .mainLayout(paneID: secondParentPaneID),
            .drawerChild(paneID: childPaneID, parentPaneID: secondParentPaneID),
        ])

        // Assert
        #expect(
            preparation
                == .rejected(
                    .drawerChildParentMismatch(
                        childPaneID: childPaneID,
                        expectedParentPaneID: firstParentPaneID,
                        actualParentPaneID: secondParentPaneID
                    )
                )
        )
    }
    @Test("append rejects a drawer child in a main arrangement layout")
    func appendRejectsDrawerChildInMainLayout() {
        // Arrange
        var fixture = makeComplexTabFixture()
        fixture.tab.arrangements[0].layout = Layout(paneId: fixture.firstDrawerPaneID)
        fixture.tab.arrangements[0].activePaneId = fixture.firstDrawerPaneID

        // Act
        let decision = WorkspaceAppendTabTransitionDecider.decide(
            tab: fixture.tab,
            context: makeAppendContext(for: fixture)
        )

        // Assert
        #expect(
            decision
                == .rejected(
                    .arrangementLayoutUsesDrawerChild(
                        arrangementID: fixture.firstArrangementID,
                        paneID: fixture.firstDrawerPaneID,
                        parentPaneID: fixture.firstPaneID
                    )
                )
        )
    }

    @Test("append rejects a main-layout pane inside a drawer view")
    func appendRejectsMainLayoutPaneInsideDrawer() {
        // Arrange
        var fixture = makeComplexTabFixture()
        fixture.tab.arrangements[0].drawerViews[fixture.firstDrawerID] = DrawerView(
            layout: DrawerGridLayout(topRow: Layout(paneId: fixture.secondPaneID)),
            activeChildId: fixture.secondPaneID
        )
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
                    .drawerViewUsesMainLayoutPane(
                        key: key,
                        paneID: fixture.secondPaneID
                    )
                )
        )
    }

    @Test("append rejects a drawer view without a capability")
    func appendRejectsMissingDrawerCapability() {
        // Arrange
        var fixture = makeComplexTabFixture()
        let missingDrawerID = UUIDv7.generate()
        let drawerView = fixture.tab.arrangements[0].drawerViews.removeValue(forKey: fixture.firstDrawerID)
        fixture.tab.arrangements[0].drawerViews[missingDrawerID] = drawerView
        let key = ArrangementDrawerCursorKey(
            arrangementId: fixture.firstArrangementID,
            drawerId: missingDrawerID
        )

        // Act
        let decision = WorkspaceAppendTabTransitionDecider.decide(
            tab: fixture.tab,
            context: makeAppendContext(for: fixture)
        )

        // Assert
        #expect(decision == .rejected(.drawerCapabilityMissing(key: key)))
    }

    @Test("append rejects a drawer whose parent is absent from the arrangement")
    func appendRejectsDrawerWithAbsentParent() {
        // Arrange
        var fixture = makeComplexTabFixture()
        fixture.tab.arrangements[0].layout = Layout(paneId: fixture.secondPaneID)
        fixture.tab.arrangements[0].activePaneId = fixture.secondPaneID
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
                    .drawerParentPaneMissingFromLayout(
                        key: key,
                        parentPaneID: fixture.firstPaneID
                    )
                )
        )
    }

}

struct ComplexTabFixture {
    var tab: Tab
    let firstPaneID: UUID
    let secondPaneID: UUID
    let firstDrawerPaneID: UUID
    let secondDrawerPaneID: UUID
    let firstArrangementID: UUID
    let secondArrangementID: UUID
    let firstDrawerID: UUID
    let secondDrawerID: UUID
}

func makeComplexTabFixture() -> ComplexTabFixture {
    let firstPaneID = UUIDv7.generate()
    let secondPaneID = UUIDv7.generate()
    let firstDrawerPaneID = UUIDv7.generate()
    let secondDrawerPaneID = UUIDv7.generate()
    let firstArrangementID = UUIDv7.generate()
    let secondArrangementID = UUIDv7.generate()
    let firstDrawerID = UUIDv7.generate()
    let secondDrawerID = UUIDv7.generate()
    let firstDrawer = DrawerView(
        layout: DrawerGridLayout(topRow: Layout(paneId: firstDrawerPaneID)),
        activeChildId: firstDrawerPaneID
    )
    var secondDrawer = DrawerView(
        layout: DrawerGridLayout(topRow: Layout(paneId: secondDrawerPaneID)),
        activeChildId: secondDrawerPaneID
    )
    secondDrawer.activeChildId = nil
    let firstArrangement = PaneArrangement(
        id: firstArrangementID,
        name: "Default",
        isDefault: true,
        layout: Layout(paneId: firstPaneID),
        activePaneId: firstPaneID,
        drawerViews: [firstDrawerID: firstDrawer]
    )
    var secondArrangement = PaneArrangement(
        id: secondArrangementID,
        name: "Focused",
        isDefault: false,
        layout: Layout(paneId: secondPaneID),
        activePaneId: secondPaneID,
        drawerViews: [secondDrawerID: secondDrawer]
    )
    secondArrangement.activePaneId = nil
    let tab = Tab(
        id: UUIDv7.generate(),
        name: "Review",
        allPaneIds: [firstPaneID, secondPaneID, firstDrawerPaneID, secondDrawerPaneID],
        arrangements: [firstArrangement, secondArrangement],
        activeArrangementId: secondArrangementID,
        colorHex: "#22CC88"
    )
    return ComplexTabFixture(
        tab: tab,
        firstPaneID: firstPaneID,
        secondPaneID: secondPaneID,
        firstDrawerPaneID: firstDrawerPaneID,
        secondDrawerPaneID: secondDrawerPaneID,
        firstArrangementID: firstArrangementID,
        secondArrangementID: secondArrangementID,
        firstDrawerID: firstDrawerID,
        secondDrawerID: secondDrawerID
    )
}

func makeAppendContext(
    activeTab: WorkspaceExistingActiveTabSelection = .noSelection,
    orderedTabIDs: [UUID] = [],
    paneOwners: [UUID: UUID] = [:],
    panePlacementDescriptors: [WorkspacePanePlacementDescriptor] = [],
    arrangementIDs: Set<UUID> = [],
    activeArrangementTabIDs: Set<UUID> = [],
    activePaneArrangementIDs: Set<UUID> = [],
    drawerCursorKeys: Set<ArrangementDrawerCursorKey> = []
) -> WorkspaceAppendTabContext {
    guard
        case .validated(let alignedTabOwners) = WorkspaceAlignedTabOwnerIndex.prepare(
            shellTabIDs: orderedTabIDs,
            graphTabIDs: orderedTabIDs
        )
    else {
        preconditionFailure("test context requires aligned tab owners")
    }
    guard
        case .validated(let panePlacements) = WorkspacePanePlacementIndex.prepare(
            panePlacementDescriptors
        )
    else {
        preconditionFailure("test context requires valid pane placements")
    }
    return WorkspaceAppendTabContext(
        activeTab: activeTab,
        alignedTabOwners: alignedTabOwners,
        panePlacements: panePlacements,
        paneOwnerByPaneID: paneOwners,
        existingArrangementIDs: arrangementIDs,
        existingActiveArrangementTabIDs: activeArrangementTabIDs,
        existingActivePaneArrangementIDs: activePaneArrangementIDs,
        existingActiveDrawerChildKeys: drawerCursorKeys
    )
}

func makeAppendContext(
    for fixture: ComplexTabFixture,
    activeTab: WorkspaceExistingActiveTabSelection = .noSelection,
    orderedTabIDs: [UUID] = [],
    paneOwners: [UUID: UUID] = [:],
    additionalPanePlacementDescriptors: [WorkspacePanePlacementDescriptor] = [],
    arrangementIDs: Set<UUID> = [],
    activeArrangementTabIDs: Set<UUID> = [],
    activePaneArrangementIDs: Set<UUID> = [],
    drawerCursorKeys: Set<ArrangementDrawerCursorKey> = []
) -> WorkspaceAppendTabContext {
    makeAppendContext(
        activeTab: activeTab,
        orderedTabIDs: orderedTabIDs,
        paneOwners: paneOwners,
        panePlacementDescriptors: panePlacementDescriptors(for: fixture)
            + additionalPanePlacementDescriptors,
        arrangementIDs: arrangementIDs,
        activeArrangementTabIDs: activeArrangementTabIDs,
        activePaneArrangementIDs: activePaneArrangementIDs,
        drawerCursorKeys: drawerCursorKeys
    )
}

func panePlacementDescriptors(
    for fixture: ComplexTabFixture
) -> [WorkspacePanePlacementDescriptor] {
    [
        .drawerParent(
            paneID: fixture.firstPaneID,
            drawerID: fixture.firstDrawerID,
            drawerChildPaneIDs: [fixture.firstDrawerPaneID]
        ),
        .drawerParent(
            paneID: fixture.secondPaneID,
            drawerID: fixture.secondDrawerID,
            drawerChildPaneIDs: [fixture.secondDrawerPaneID]
        ),
        .drawerChild(
            paneID: fixture.firstDrawerPaneID,
            parentPaneID: fixture.firstPaneID
        ),
        .drawerChild(
            paneID: fixture.secondDrawerPaneID,
            parentPaneID: fixture.secondPaneID
        ),
    ]
}
