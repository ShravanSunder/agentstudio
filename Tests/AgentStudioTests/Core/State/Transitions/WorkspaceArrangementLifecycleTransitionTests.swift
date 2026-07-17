import Foundation
import Testing

@testable import AgentStudio

@Suite("Workspace arrangement lifecycle transitions")
struct WorkspaceArrangementLifecycleTransitionTests {
    @Test("new arrangement identity accepts only UUIDv7")
    func newArrangementIdentityAcceptsOnlyUUIDv7() {
        // Arrange
        let validID = UUIDv7.generate()
        let invalidID = UUID()
        let generated = WorkspaceNewArrangementID.generate()

        // Act
        let valid = WorkspaceNewArrangementID.prepare(validID)
        let invalid = WorkspaceNewArrangementID.prepare(invalidID)

        // Assert
        guard case .validated(let identity) = valid else {
            Issue.record("expected UUIDv7 identity validation")
            return
        }
        #expect(identity.rawValue == validID)
        #expect(UUIDv7.isV7(identity.rawValue))
        #expect(UUIDv7.isV7(generated.rawValue))
        #expect(invalid == .rejected(.nonUUIDv7(invalidID)))
    }

    @Test("create copies the exact active complete view and cursor states")
    func createCopiesExactActiveViewAndCursors() {
        // Arrange
        let fixture = makeArrangementLifecycleFixture()
        let newID = preparedArrangementID()
        let request = WorkspaceCreateArrangementRequest(
            tabID: fixture.tab.tabId,
            arrangementID: newID,
            name: "  Focus\nMode "
        )

        // Act
        let decision = WorkspaceArrangementLifecycleTransitionPlanner.planCreate(
            request,
            context: fixture.createContext(newID: newID)
        )

        // Assert
        guard case .changed(.create(let transition)) = decision else {
            Issue.record("expected arrangement creation transition")
            return
        }
        let created = transition.replacementTab.arrangements.last
        #expect(created?.id == newID.rawValue)
        #expect(created?.name == "Focus Mode")
        #expect(created?.isDefault == false)
        #expect(created?.layout == fixture.activeArrangement.layout)
        #expect(created?.minimizedPaneIds == fixture.activeArrangement.minimizedPaneIds)
        #expect(created?.showsMinimizedPanes == fixture.activeArrangement.showsMinimizedPanes)
        #expect(created?.drawerViews == fixture.activeArrangement.drawerViews)
        #expect(transition.expectedActiveArrangement == .selected(fixture.activeArrangement.id))
        #expect(transition.paneCursorInsertion.state.activePaneId == fixture.mainPaneIDs[1])
        #expect(transition.drawerCursorInsertions.count == 1)
        #expect(transition.drawerCursorInsertions[0].state.activeChildId == fixture.drawerPaneIDs[0])
    }

    @Test("create rejects empty, missing, dangling, duplicate, and incomplete inputs")
    func createRejectsInvalidInputs() {
        // Arrange
        let fixture = makeArrangementLifecycleFixture()
        let newID = preparedArrangementID()
        let request = WorkspaceCreateArrangementRequest(
            tabID: fixture.tab.tabId,
            arrangementID: newID,
            name: "Focus"
        )
        var incompleteTab = fixture.tab
        incompleteTab.allPaneIds.append(UUIDv7.generate())

        // Act
        let empty = WorkspaceArrangementLifecycleTransitionPlanner.planCreate(
            .init(tabID: request.tabID, arrangementID: newID, name: " \n "),
            context: fixture.createContext(newID: newID)
        )
        let missingTab = WorkspaceArrangementLifecycleTransitionPlanner.planCreate(request, context: .missingTab)
        let dangling = WorkspaceArrangementLifecycleTransitionPlanner.planCreate(
            request,
            context: .selectedActiveArrangement(
                .init(
                    tab: fixture.tab,
                    arrangementID: UUIDv7.generate(),
                    activePaneCursor: fixture.activePaneCursor,
                    activeDrawerCursors: fixture.activeDrawerCursors,
                    proposedOwner: .unowned,
                    proposedCursors: fixture.proposedCursors(newID: newID)
                )
            )
        )
        let duplicate = WorkspaceArrangementLifecycleTransitionPlanner.planCreate(
            request,
            context: fixture.createContext(
                newID: newID,
                proposedOwner: .ownedByTab(fixture.tab.tabId)
            )
        )
        let incomplete = WorkspaceArrangementLifecycleTransitionPlanner.planCreate(
            request,
            context: fixture.createContext(newID: newID, tab: incompleteTab)
        )

        // Assert
        #expect(empty == .rejected(.emptyArrangementName))
        #expect(missingTab == .rejected(.missingTab(fixture.tab.tabId)))
        guard case .rejected(.missingArrangement) = dangling else {
            Issue.record("expected dangling active arrangement rejection")
            return
        }
        #expect(
            duplicate
                == .rejected(
                    .duplicateArrangementIdentity(
                        arrangementID: newID.rawValue,
                        ownerTabID: fixture.tab.tabId
                    )
                )
        )
        #expect(
            incomplete
                == .rejected(
                    .incompleteActiveArrangement(
                        tabID: fixture.tab.tabId,
                        arrangementID: fixture.activeArrangement.id
                    )
                )
        )
    }

    @Test("remove rejects missing and default arrangements")
    func removeRejectsMissingAndDefault() {
        // Arrange
        let fixture = makeArrangementLifecycleFixture()
        let missingID = UUIDv7.generate()

        // Act
        let missing = WorkspaceArrangementLifecycleTransitionPlanner.planRemove(
            .init(tabID: fixture.tab.tabId, arrangementID: missingID),
            context: fixture.removeContext(targetArrangementID: missingID)
        )
        let defaultRemoval = WorkspaceArrangementLifecycleTransitionPlanner.planRemove(
            .init(tabID: fixture.tab.tabId, arrangementID: fixture.defaultArrangement.id),
            context: fixture.removeContext(targetArrangementID: fixture.defaultArrangement.id)
        )

        // Assert
        #expect(
            missing
                == .rejected(
                    .missingArrangement(tabID: fixture.tab.tabId, arrangementID: missingID)
                )
        )
        #expect(
            defaultRemoval
                == .rejected(
                    .defaultArrangementCannotBeRemoved(
                        tabID: fixture.tab.tabId,
                        arrangementID: fixture.defaultArrangement.id
                    )
                )
        )
    }

    @Test("active removal falls back to default while inactive removal preserves active")
    func removeActiveAndInactiveSemantics() {
        // Arrange
        let fixture = makeArrangementLifecycleFixture()

        // Act
        let activeRemoval = WorkspaceArrangementLifecycleTransitionPlanner.planRemove(
            .init(tabID: fixture.tab.tabId, arrangementID: fixture.activeArrangement.id),
            context: fixture.removeContext(targetArrangementID: fixture.activeArrangement.id)
        )
        let inactiveRemoval = WorkspaceArrangementLifecycleTransitionPlanner.planRemove(
            .init(tabID: fixture.tab.tabId, arrangementID: fixture.inactiveArrangement.id),
            context: fixture.removeContext(targetArrangementID: fixture.inactiveArrangement.id)
        )

        // Assert
        guard case .changed(.remove(let active)) = activeRemoval,
            case .changed(.remove(let inactive)) = inactiveRemoval
        else {
            Issue.record("expected removal transitions")
            return
        }
        #expect(active.replacementActiveArrangementID == fixture.defaultArrangement.id)
        #expect(inactive.replacementActiveArrangementID == nil)
        #expect(active.replacementTab.arrangements.contains { $0.id == fixture.activeArrangement.id } == false)
        #expect(inactive.replacementTab.arrangements.contains { $0.id == fixture.inactiveArrangement.id } == false)
    }

    @Test("present no-selection cursors remain typed lifecycle state")
    func noSelectionCursorIsAccepted() {
        // Arrange
        var fixture = makeArrangementLifecycleFixture()
        let mainPaneIDs = fixture.mainPaneIDs
        let drawerPaneIDs = fixture.drawerPaneIDs
        let drawerID = fixture.drawerID
        fixture.tab.arrangements[1].minimizedPaneIds = Set(mainPaneIDs)
        var drawer = fixture.tab.arrangements[1].drawerViews[drawerID]!
        drawer.minimizedPaneIds = Set(drawerPaneIDs)
        fixture.tab.arrangements[1].drawerViews[drawerID] = drawer

        // Act
        let decision = WorkspaceArrangementLifecycleTransitionPlanner.planRemove(
            .init(tabID: fixture.tab.tabId, arrangementID: fixture.activeArrangement.id),
            context: .selectedActiveArrangement(
                .init(
                    tab: fixture.tab,
                    arrangementID: fixture.activeArrangement.id,
                    targetPaneCursor: .present(.noSelection),
                    targetDrawerCursors: [.init(drawerID: fixture.drawerID, cursor: .present(.noSelection))],
                    defaultArrangement: .selected(fixture.defaultArrangement.id)
                )
            )
        )

        // Assert
        guard case .changed(.remove(let transition)) = decision else {
            Issue.record("expected no-selection cursor removal")
            return
        }
        #expect(transition.expectedPaneCursor == .present(.noSelection))
    }
}

struct ArrangementLifecycleFixture {
    var tab: TabGraphState
    let defaultArrangement: PaneArrangementGraphState
    let activeArrangement: PaneArrangementGraphState
    let inactiveArrangement: PaneArrangementGraphState
    let mainPaneIDs: [UUID]
    let drawerID: UUID
    let drawerPaneIDs: [UUID]

    var activePaneCursor: WorkspaceActivePaneCursorWitness {
        .present(.selected(mainPaneIDs[1]))
    }

    var activeDrawerCursors: [WorkspaceArrangementDrawerCursorWitness] {
        [.init(drawerID: drawerID, cursor: .present(.selected(drawerPaneIDs[0])))]
    }

    func proposedCursors(newID _: WorkspaceNewArrangementID) -> WorkspaceArrangementProposedCursorWitness {
        .init(
            paneCursor: .missing,
            drawerCursors: [.init(drawerID: drawerID, cursor: .missing)]
        )
    }

    func createContext(
        newID: WorkspaceNewArrangementID,
        proposedOwner: WorkspaceArrangementIdentityOwnerWitness = .unowned,
        tab replacementTab: TabGraphState? = nil
    ) -> WorkspaceCreateArrangementPlanningContext {
        .selectedActiveArrangement(
            .init(
                tab: replacementTab ?? tab,
                arrangementID: activeArrangement.id,
                activePaneCursor: activePaneCursor,
                activeDrawerCursors: activeDrawerCursors,
                proposedOwner: proposedOwner,
                proposedCursors: proposedCursors(newID: newID)
            )
        )
    }

    func removeContext(targetArrangementID: UUID) -> WorkspaceRemoveArrangementPlanningContext {
        let target = tab.arrangements.first { $0.id == targetArrangementID }
        let paneCursor: WorkspaceActivePaneCursorWitness =
            target == nil
            ? .missing : .present(.selected(mainPaneIDs[1]))
        let drawers: [WorkspaceArrangementDrawerCursorWitness] =
            target?.drawerViews.keys.map { drawerID in
                .init(drawerID: drawerID, cursor: .present(.selected(drawerPaneIDs[0])))
            } ?? []
        return .selectedActiveArrangement(
            .init(
                tab: tab,
                arrangementID: activeArrangement.id,
                targetPaneCursor: paneCursor,
                targetDrawerCursors: drawers,
                defaultArrangement: .selected(defaultArrangement.id)
            )
        )
    }
}

func makeArrangementLifecycleFixture() -> ArrangementLifecycleFixture {
    let mainPaneIDs = [UUIDv7.generate(), UUIDv7.generate()]
    let drawerPaneIDs = [UUIDv7.generate(), UUIDv7.generate()]
    let drawerID = UUIDv7.generate()
    let mainLayout = Layout(
        panes: [
            .init(paneId: mainPaneIDs[0], ratio: 0.6),
            .init(paneId: mainPaneIDs[1], ratio: 0.4),
        ],
        dividerIds: [UUIDv7.generate()]
    )
    let drawerLayout = DrawerGridLayout(
        topRow: Layout(
            panes: [
                .init(paneId: drawerPaneIDs[0], ratio: 0.5),
                .init(paneId: drawerPaneIDs[1], ratio: 0.5),
            ],
            dividerIds: [UUIDv7.generate()]
        )
    )
    func arrangement(name: String, isDefault: Bool) -> PaneArrangementGraphState {
        .init(
            id: UUIDv7.generate(),
            name: name,
            isDefault: isDefault,
            layout: mainLayout,
            minimizedPaneIds: [mainPaneIDs[0]],
            showsMinimizedPanes: false,
            drawerViews: [
                drawerID: .init(
                    layout: drawerLayout,
                    minimizedPaneIds: [drawerPaneIDs[1]]
                )
            ]
        )
    }
    let defaultArrangement = arrangement(name: "Default", isDefault: true)
    let activeArrangement = arrangement(name: "Focus", isDefault: false)
    let inactiveArrangement = arrangement(name: "Review", isDefault: false)
    return .init(
        tab: .init(
            tabId: UUIDv7.generate(),
            allPaneIds: mainPaneIDs + drawerPaneIDs,
            arrangements: [defaultArrangement, activeArrangement, inactiveArrangement]
        ),
        defaultArrangement: defaultArrangement,
        activeArrangement: activeArrangement,
        inactiveArrangement: inactiveArrangement,
        mainPaneIDs: mainPaneIDs,
        drawerID: drawerID,
        drawerPaneIDs: drawerPaneIDs
    )
}

func preparedArrangementID() -> WorkspaceNewArrangementID {
    guard case .validated(let identity) = WorkspaceNewArrangementID.prepare(UUIDv7.generate()) else {
        preconditionFailure("UUIDv7 test identity must validate")
    }
    return identity
}
