import Foundation
import Testing

@testable import AgentStudio

@Suite("Workspace pane residency lifecycle transitions")
struct WorkspacePaneResidencyLifecycleTransitionTests {
    @Test("background removes parent and children while retaining drawer views")
    func backgroundParentAndChildren() throws {
        // Arrange
        let fixture = makeResidencyFixture()

        // Act
        let decision = WorkspaceBackgroundPaneTransitionPlanner.plan(
            .init(paneID: fixture.parent.id),
            context: fixture.backgroundContext()
        )

        // Assert
        let transition = try requireBackgroundTransition(decision)
        #expect(transition.paneReplacements.count == 3)
        guard case .replace(_, let replacement) = transition.tabGraph else {
            Issue.record("expected tab graph replacement")
            return
        }
        #expect(replacement.state.allPaneIds == [fixture.otherPane.id])
        #expect(replacement.state.arrangements.allSatisfy { $0.layout.paneIds == [fixture.otherPane.id] })
        guard case .replaceRetainedDrawerPayload(_, let payload) = transition.runtimePayload.effect,
            case .present(let retained) = payload
        else {
            Issue.record("expected retained drawer payload")
            return
        }
        #expect(retained.drawerID == fixture.drawerID)
        #expect(retained.viewsByArrangementID.count == 2)
    }

    @Test("background repairs only pane cursors and preserves active arrangement")
    func backgroundRepairsPaneCursors() throws {
        // Arrange
        let fixture = makeResidencyFixture()

        // Act
        let transition = try requireBackgroundTransition(
            WorkspaceBackgroundPaneTransitionPlanner.plan(
                .init(paneID: fixture.parent.id),
                context: fixture.backgroundContext()
            )
        )

        // Assert
        #expect(
            transition.activeArrangements == [
                .witness(tabID: fixture.tabID, expected: .selected(fixture.arrangementIDs[0]))
            ]
        )
        #expect(
            transition.activePanes.contains(
                .replace(
                    arrangementID: fixture.arrangementIDs[0],
                    previous: .present(.selected(fixture.parent.id)),
                    replacement: .selected(fixture.otherPane.id)
                )
            )
        )
        #expect(transition.zoom == .clear(tabID: fixture.tabID, previous: fixture.parent.id))
    }

    @Test("background last pane removes exact tab owners and shifted shell suffix")
    func backgroundLastPaneRemovesTabOwners() throws {
        // Arrange
        let fixture = makeResidencyFixture(includeOtherPane: false)
        let followingTabID = UUIDv7.generate()
        let shells = [
            TabShell(id: fixture.tabID, name: "Target"),
            TabShell(id: followingTabID, name: "Following"),
        ]
        var context = fixture.backgroundContext()
        context = .init(
            pane: context.pane,
            declaredDrawerChildrenByID: context.declaredDrawerChildrenByID,
            ownershipByPaneID: context.ownershipByPaneID,
            tabCursors: context.tabCursors,
            tabRemoval: .current(tabShells: shells, activeTab: .selected(fixture.tabID)),
            retainedDrawerPayload: context.retainedDrawerPayload
        )

        // Act
        let transition = try requireBackgroundTransition(
            WorkspaceBackgroundPaneTransitionPlanner.plan(.init(paneID: fixture.parent.id), context: context)
        )

        // Assert
        guard case .remove = transition.tabGraph,
            case .remove(let removed, let shiftedSuffix) = transition.tabShell,
            case .replace(let cursor) = transition.tabCursor
        else {
            Issue.record("expected exact tab owner removals")
            return
        }
        #expect(removed.shell.id == fixture.tabID)
        #expect(removed.index == 0)
        #expect(shiftedSuffix.map(\.shell.id) == [followingTabID])
        #expect(cursor.replacement == .selected(followingTabID))
        #expect(transition.activePanes.count == fixture.arrangementIDs.count)
    }

    @Test("already backgrounded and absent is unchanged without consuming payload")
    func doubleBackgroundIsUnchanged() {
        // Arrange
        let fixture = makeResidencyFixture(parentResidency: .backgrounded)
        let retained = WorkspaceRetainedDrawerPayloadWitness.present(
            .init(drawerID: fixture.drawerID, viewsByArrangementID: [:])
        )

        // Act
        let decision = WorkspaceBackgroundPaneTransitionPlanner.plan(
            .init(paneID: fixture.parent.id),
            context: fixture.backgroundContext(ownership: .absent, retainedPayload: retained)
        )

        // Assert
        #expect(decision == .unchanged)
    }

    @Test("background rejects drawer child and missing declared child")
    func backgroundRejectsInvalidPaneGraph() {
        // Arrange
        let fixture = makeResidencyFixture()
        let child = fixture.children[0]
        let missingChildID = fixture.children[1].id
        var missingChildren = fixture.childStatesByID
        missingChildren.removeValue(forKey: missingChildID)
        let base = fixture.backgroundContext()

        // Act
        let drawerChild = WorkspaceBackgroundPaneTransitionPlanner.plan(
            .init(paneID: child.id),
            context: .init(
                pane: .present(child),
                declaredDrawerChildrenByID: [:],
                ownershipByPaneID: [child.id: .absent],
                tabCursors: base.tabCursors,
                tabRemoval: .notRequired,
                retainedDrawerPayload: .absent
            )
        )
        let missingChild = WorkspaceBackgroundPaneTransitionPlanner.plan(
            .init(paneID: fixture.parent.id),
            context: .init(
                pane: .present(fixture.parent),
                declaredDrawerChildrenByID: missingChildren,
                ownershipByPaneID: base.ownershipByPaneID,
                tabCursors: base.tabCursors,
                tabRemoval: base.tabRemoval,
                retainedDrawerPayload: .absent
            )
        )

        // Assert
        #expect(drawerChild == .rejected(.drawerChildPane(child.id)))
        #expect(missingChild == .rejected(.childMissing(missingChildID)))
    }

    @Test("background rejects missing and dangling active arrangement cursors")
    func backgroundRejectsInvalidActiveArrangement() {
        // Arrange
        let fixture = makeResidencyFixture()
        let base = fixture.backgroundContext()
        let missing = WorkspacePaneResidencyTabCursorSnapshot(
            activeArrangement: .missing,
            activePanesByArrangementID: base.tabCursors.activePanesByArrangementID,
            activeDrawerChildrenByKey: base.tabCursors.activeDrawerChildrenByKey,
            zoom: base.tabCursors.zoom
        )
        let danglingID = UUIDv7.generate()
        let dangling = WorkspacePaneResidencyTabCursorSnapshot(
            activeArrangement: .selected(danglingID),
            activePanesByArrangementID: base.tabCursors.activePanesByArrangementID,
            activeDrawerChildrenByKey: base.tabCursors.activeDrawerChildrenByKey,
            zoom: base.tabCursors.zoom
        )

        // Act
        let missingDecision = WorkspaceBackgroundPaneTransitionPlanner.plan(
            .init(paneID: fixture.parent.id),
            context: fixture.backgroundContext(cursors: missing)
        )
        let danglingDecision = WorkspaceBackgroundPaneTransitionPlanner.plan(
            .init(paneID: fixture.parent.id),
            context: fixture.backgroundContext(cursors: dangling)
        )

        // Assert
        #expect(missingDecision == .rejected(.activeArrangementMissing(fixture.tabID)))
        #expect(
            danglingDecision
                == .rejected(.activeArrangementNotInTab(tabID: fixture.tabID, arrangementID: danglingID))
        )
    }

    @Test("reactivate inserts into selected arrangement and appends to other arrangements")
    func reactivateAcrossArrangements() throws {
        // Arrange
        let fixture = makeResidencyFixture(parentResidency: .backgrounded)

        // Act
        let transition = try requireReactivateTransition(
            WorkspaceReactivatePaneTransitionPlanner.plan(
                fixture.reactivateRequest(),
                context: fixture.reactivateContext()
            )
        )

        // Assert
        guard case .replace(_, let replacement) = transition.tabGraph else {
            Issue.record("expected target graph replacement")
            return
        }
        #expect(replacement.state.allPaneIds.suffix(3) == [fixture.parent.id] + fixture.children.map(\.id))
        #expect(replacement.state.arrangements.allSatisfy { $0.layout.contains(fixture.parent.id) })
        #expect(
            transition.activePanes.contains(
                .replace(
                    arrangementID: fixture.arrangementIDs[0],
                    previous: .present(.selected(fixture.otherPane.id)),
                    replacement: .selected(fixture.parent.id)
                )
            )
        )
        #expect(transition.zoom == .clear(tabID: fixture.tabID, previous: fixture.otherPane.id))
    }

    @Test("reactivate restores matching retained views and falls back for missing arrangement")
    func reactivateRestoresMatchingPayload() throws {
        // Arrange
        let fixture = makeResidencyFixture(parentResidency: .backgrounded)
        let customLayout = DrawerGridLayout(topRow: Layout.autoTiled(fixture.children.map(\.id).reversed()))
        let retained = WorkspaceRetainedDrawerPayloadWitness.present(
            .init(
                drawerID: fixture.drawerID,
                viewsByArrangementID: [
                    fixture.arrangementIDs[0]: DrawerView(
                        layout: customLayout,
                        activeChildId: fixture.children.last!.id
                    )
                ]
            )
        )

        // Act
        let transition = try requireReactivateTransition(
            WorkspaceReactivatePaneTransitionPlanner.plan(
                fixture.reactivateRequest(),
                context: fixture.reactivateContext(retainedPayload: retained)
            )
        )

        // Assert
        guard case .replace(_, let replacement) = transition.tabGraph else { return }
        let restored = replacement.state.arrangements[0].drawerViews[fixture.drawerID]
        let fallback = replacement.state.arrangements[1].drawerViews[fixture.drawerID]
        #expect(restored?.layout == customLayout)
        #expect(fallback?.layout.paneIds == fixture.children.map(\.id))
    }

    @Test("reactivate active pane with one owner is unchanged")
    func reactivateActivePaneIsUnchanged() {
        // Arrange
        let fixture = makeResidencyFixture()

        // Act
        let decision = WorkspaceReactivatePaneTransitionPlanner.plan(
            fixture.reactivateRequest(),
            context: fixture.reactivateContext(currentOwnership: fixture.ownership)
        )

        // Assert
        #expect(decision == .unchanged)
    }

    @Test("reactivate rejects missing target, missing anchor, and duplicate ownership")
    func reactivateRejectsInvalidTargets() {
        // Arrange
        let fixture = makeResidencyFixture(parentResidency: .backgrounded)
        let missingTarget = fixture.reactivateContext(targetTab: .missing)
        var missingAnchorRequest = fixture.reactivateRequest()
        missingAnchorRequest = .init(
            paneID: missingAnchorRequest.paneID,
            targetTabID: missingAnchorRequest.targetTabID,
            targetPaneID: UUIDv7.generate(),
            direction: missingAnchorRequest.direction,
            position: missingAnchorRequest.position,
            sizingMode: missingAnchorRequest.sizingMode
        )

        // Act
        let targetDecision = WorkspaceReactivatePaneTransitionPlanner.plan(
            fixture.reactivateRequest(), context: missingTarget
        )
        let anchorDecision = WorkspaceReactivatePaneTransitionPlanner.plan(
            missingAnchorRequest, context: fixture.reactivateContext()
        )
        let ownedDecision = WorkspaceReactivatePaneTransitionPlanner.plan(
            fixture.reactivateRequest(),
            context: fixture.reactivateContext(currentOwnership: fixture.ownership)
        )

        // Assert
        #expect(targetDecision == .rejected(.targetTabMissing(fixture.tabID)))
        guard case .rejected(.targetPaneMissing) = anchorDecision else {
            Issue.record("expected missing target pane")
            return
        }
        #expect(ownedDecision == .rejected(.paneAlreadyOwnedByTab(paneID: fixture.parent.id, tabID: fixture.tabID)))
    }
}

struct PaneResidencyFixture {
    let parent: PaneGraphState
    let children: [PaneGraphState]
    let otherPane: PaneGraphState
    let drawerID: UUID
    let tabID: UUID
    let arrangementIDs: [UUID]
    let tabState: TabGraphState
    let ownership: WorkspacePaneResidencyTabOwnershipWitness
    let ownershipByPaneID: [UUID: WorkspacePaneResidencyTabOwnershipWitness]
    let childStatesByID: [UUID: PaneGraphState]
    let cursors: WorkspacePaneResidencyTabCursorSnapshot

    func backgroundContext(
        ownership: WorkspacePaneResidencyTabOwnershipWitness? = nil,
        ownershipByPaneID: [UUID: WorkspacePaneResidencyTabOwnershipWitness]? = nil,
        cursors: WorkspacePaneResidencyTabCursorSnapshot? = nil,
        retainedPayload: WorkspaceRetainedDrawerPayloadWitness = .absent
    ) -> WorkspaceBackgroundPanePlanningContext {
        .init(
            pane: .present(parent),
            declaredDrawerChildrenByID: childStatesByID,
            ownershipByPaneID: ownershipByPaneID
                ?? Dictionary(
                    uniqueKeysWithValues: ([parent.id] + children.map(\.id)).map {
                        ($0, ownership ?? self.ownership)
                    }
                ),
            tabCursors: cursors ?? self.cursors,
            tabRemoval: tabState.allPaneIds.count == 3
                ? .current(tabShells: [TabShell(id: tabID, name: "Target")], activeTab: .selected(tabID))
                : .notRequired,
            retainedDrawerPayload: retainedPayload
        )
    }

    func reactivateRequest() -> WorkspaceReactivatePaneRequest {
        .init(
            paneID: parent.id,
            targetTabID: tabID,
            targetPaneID: otherPane.id,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )
    }

    func reactivateContext(
        currentOwnership: WorkspacePaneResidencyTabOwnershipWitness = .absent,
        ownershipByPaneID: [UUID: WorkspacePaneResidencyTabOwnershipWitness]? = nil,
        targetTab: WorkspaceTargetTabWitness? = nil,
        targetCursors: WorkspacePaneResidencyTabCursorSnapshot? = nil,
        retainedPayload: WorkspaceRetainedDrawerPayloadWitness = .absent
    ) -> WorkspaceReactivatePanePlanningContext {
        .init(
            pane: .present(parent),
            declaredDrawerChildrenByID: childStatesByID,
            ownershipByPaneID: ownershipByPaneID
                ?? Dictionary(
                    uniqueKeysWithValues: ([parent.id] + children.map(\.id)).map { ($0, currentOwnership) }
                ),
            targetTab: targetTab ?? .present(.init(index: 0, state: targetGraphForReactivation())),
            targetTabCursors: targetCursors ?? targetCursorsForReactivation(),
            retainedDrawerPayload: retainedPayload
        )
    }

    func targetGraphForReactivation() -> TabGraphState {
        var target = tabState
        target.allPaneIds = [otherPane.id]
        for index in target.arrangements.indices {
            target.arrangements[index].layout = Layout(paneId: otherPane.id)
            target.arrangements[index].drawerViews = [:]
            target.arrangements[index].minimizedPaneIds = []
        }
        return target
    }

    func targetCursorsForReactivation() -> WorkspacePaneResidencyTabCursorSnapshot {
        .init(
            activeArrangement: .selected(arrangementIDs[0]),
            activePanesByArrangementID: Dictionary(
                uniqueKeysWithValues: arrangementIDs.map { ($0, .present(.selected(otherPane.id))) }
            ),
            activeDrawerChildrenByKey: [:],
            zoom: .zoomed(otherPane.id)
        )
    }
}

func makeResidencyFixture(
    parentResidency: SessionResidency = .active,
    includeOtherPane: Bool = true
) -> PaneResidencyFixture {
    let parentID = UUIDv7.generate()
    let drawerID = UUIDv7.generate()
    let childIDs = [UUIDv7.generate(), UUIDv7.generate()]
    let parent = makeResidencyPane(
        id: parentID,
        residency: parentResidency,
        kind: .layout(drawer: Drawer(drawerId: drawerID, parentPaneId: parentID, paneIds: childIDs))
    )
    let children = childIDs.map {
        makeResidencyPane(
            id: $0,
            residency: parentResidency,
            kind: .drawerChild(parentPaneId: parentID)
        )
    }
    let other = makeResidencyPane(id: UUIDv7.generate(), residency: .active)
    let tabID = UUIDv7.generate()
    let arrangementIDs = [UUIDv7.generate(), UUIDv7.generate()]
    let layoutPaneIDs = includeOtherPane ? [parentID, other.id] : [parentID]
    let drawerLayout = DrawerGridLayout(topRow: Layout.autoTiled(childIDs))
    let arrangements = arrangementIDs.enumerated().map { index, arrangementID in
        PaneArrangementGraphState(
            id: arrangementID,
            name: index == 0 ? "Default" : "Focus",
            isDefault: index == 0,
            layout: Layout.autoTiled(layoutPaneIDs),
            minimizedPaneIds: [parentID],
            showsMinimizedPanes: true,
            drawerViews: [drawerID: DrawerViewGraphState(layout: drawerLayout, minimizedPaneIds: [])]
        )
    }
    let allPaneIDs = [parentID] + childIDs + (includeOtherPane ? [other.id] : [])
    let tabState = TabGraphState(tabId: tabID, allPaneIds: allPaneIDs, arrangements: arrangements)
    let drawerCursors = Dictionary(
        uniqueKeysWithValues: arrangementIDs.map {
            (
                ArrangementDrawerCursorKey(arrangementId: $0, drawerId: drawerID),
                WorkspacePaneResidencyDrawerCursorWitness.present(.selected(childIDs[0]))
            )
        }
    )
    return .init(
        parent: parent,
        children: children,
        otherPane: other,
        drawerID: drawerID,
        tabID: tabID,
        arrangementIDs: arrangementIDs,
        tabState: tabState,
        ownership: .owned(.init(index: 0, state: tabState)),
        ownershipByPaneID: Dictionary(
            uniqueKeysWithValues: ([parentID] + childIDs).map {
                ($0, .owned(.init(index: 0, state: tabState)))
            }
        ),
        childStatesByID: Dictionary(uniqueKeysWithValues: children.map { ($0.id, $0) }),
        cursors: .init(
            activeArrangement: .selected(arrangementIDs[0]),
            activePanesByArrangementID: [
                arrangementIDs[0]: .present(.selected(parentID)),
                arrangementIDs[1]: .present(.selected(includeOtherPane ? other.id : parentID)),
            ],
            activeDrawerChildrenByKey: drawerCursors,
            zoom: .zoomed(parentID)
        )
    )
}

private func makeResidencyPane(
    id: UUID,
    residency: SessionResidency,
    kind: PaneKind? = nil
) -> PaneGraphState {
    PaneGraphState(
        pane: Pane(
            id: id,
            content: .terminal(
                TerminalState(provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7())
            ),
            metadata: PaneMetadata(title: "Pane"),
            residency: residency,
            kind: kind
        )
    )
}

private func requireBackgroundTransition(
    _ decision: WorkspaceBackgroundPaneTransitionDecision
) throws -> WorkspaceBackgroundPaneTransition {
    guard case .changed(.background(let transition)) = decision else {
        throw PaneResidencyTestError.expectedBackgroundTransition
    }
    return transition
}

private func requireReactivateTransition(
    _ decision: WorkspaceReactivatePaneTransitionDecision
) throws -> WorkspaceReactivatePaneTransition {
    guard case .changed(.reactivate(let transition)) = decision else {
        throw PaneResidencyTestError.expectedReactivateTransition
    }
    return transition
}

private enum PaneResidencyTestError: Error {
    case expectedBackgroundTransition
    case expectedReactivateTransition
}
