import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace persistence pane residency mutation")
struct WorkspacePersistencePaneResidencyMutationTests {
    @Test("preinstall background rejects without state or revision")
    func preinstallBackgroundRejects() {
        // Arrange
        let fixture = makeBackgroundPersistenceFixture()
        let originalPaneStates = fixture.atomRegistry.workspacePaneGraph.paneStates

        // Act
        let result = fixture.runtime.mutationCoordinator.backgroundPane(
            .init(paneID: fixture.residency.parent.id),
            retainedDrawerPayload: .absent
        )

        // Assert
        #expect(result == .rejected(.compositionDomainNotInstalled(phase: .preinstall)))
        #expect(fixture.runtime.revisionOwner.committedRevision == .zero)
        #expect(fixture.atomRegistry.workspacePaneGraph.paneStates == originalPaneStates)
    }

    @Test("background captures every persisted owner at one fixed revision")
    func backgroundCapturesAllPersistedOwners() throws {
        // Arrange
        let fixture = makeBackgroundPersistenceFixture()
        let installed = try installResidencyParticipants(fixture.runtime)
        defer { closeResidencyParticipants(installed) }
        let originalTargetGraph = try #require(
            fixture.atomRegistry.workspaceTabGraph.tabState(fixture.residency.tabID)
        )
        let originalFollowingGraph = try #require(
            fixture.atomRegistry.workspaceTabGraph.tabState(fixture.followingTabID)
        )

        // Act
        let result = fixture.runtime.mutationCoordinator.backgroundPane(
            .init(paneID: fixture.residency.parent.id),
            retainedDrawerPayload: .absent
        )

        // Assert
        let receipt = try requireResidencyChanged(result)
        #expect(receipt.revision.rawValue == 1)
        guard case .replaceRetainedDrawerPayload(let paneID, .present(let payload)) = receipt.effect else {
            Issue.record("expected typed retained-drawer replacement effect")
            return
        }
        #expect(paneID == fixture.residency.parent.id)
        #expect(payload.drawerID == fixture.residency.drawerID)
        #expect(fixture.runtime.revisionOwner.committedRevision.rawValue == 1)
        #expect(fixture.atomRegistry.workspaceTabGraph.tabState(fixture.residency.tabID) == nil)
        #expect(fixture.atomRegistry.workspaceTabShell.tabShell(fixture.residency.tabID) == nil)
        #expect(fixture.atomRegistry.workspaceTabShell.activeTabId == fixture.followingTabID)
        #expect(
            fixture.atomRegistry.workspaceTabGraph.tabState(fixture.followingTabID)
                == originalFollowingGraph
        )
        #expect(
            fixture.atomRegistry.workspaceArrangementCursor.activeArrangementId(
                forTab: fixture.followingTabID
            ) == fixture.followingArrangementID
        )
        try expectResidencyBaseItem(
            .tabGraph(originalTargetGraph),
            participantID: .tabGraphs,
            installed: installed
        )
        try expectResidencyBaseItem(
            .tabShell(.init(shell: fixture.targetShell, sortIndex: 0)),
            participantID: .tabShells,
            installed: installed
        )
        try expectResidencyBaseItem(
            .tabShell(.init(shell: fixture.followingShell, sortIndex: 1)),
            participantID: .tabShells,
            installed: installed
        )
        try expectResidencyBaseItem(
            .activeTab(fixture.residency.tabID),
            participantID: .activeTab,
            installed: installed
        )
        for paneState in [fixture.residency.parent] + fixture.residency.children {
            try expectResidencyBaseItem(
                .paneGraph(paneState),
                participantID: .paneGraphs,
                installed: installed
            )
        }
        for arrangementID in fixture.residency.arrangementIDs {
            try expectResidencyBaseItem(
                .activeArrangement(
                    tabID: fixture.residency.tabID,
                    arrangementID: fixture.residency.arrangementIDs[0]
                ),
                participantID: .activeArrangements,
                installed: installed
            )
            try expectResidencyBaseItem(
                .activePane(
                    arrangementID: arrangementID,
                    paneID: fixture.residency.parent.id
                ),
                participantID: .activePanes,
                installed: installed
            )
            try expectResidencyBaseItem(
                .activeDrawerChild(
                    key: .init(
                        arrangementId: arrangementID,
                        drawerId: fixture.residency.drawerID
                    ),
                    childPaneID: fixture.residency.children[0].id
                ),
                participantID: .activeDrawerChildren,
                installed: installed
            )
        }
    }

    @Test("reactivate captures values and excludes inserted drawer cursors")
    func reactivateCapturesValuesAndInsertionExclusions() throws {
        // Arrange
        let fixture = makeReactivatePersistenceFixture()
        let installed = try installResidencyParticipants(fixture.runtime)
        defer { closeResidencyParticipants(installed) }
        let originalTargetGraph = try #require(
            fixture.atomRegistry.workspaceTabGraph.tabState(fixture.residency.tabID)
        )

        // Act
        let result = fixture.runtime.mutationCoordinator.reactivatePane(
            fixture.residency.reactivateRequest(),
            retainedDrawerPayload: .absent
        )

        // Assert
        let receipt = try requireResidencyChanged(result)
        #expect(receipt.revision.rawValue == 1)
        #expect(receipt.effect == .consumeRetainedDrawerPayloadAndMount(paneID: fixture.residency.parent.id))
        #expect(fixture.runtime.revisionOwner.committedRevision.rawValue == 1)
        #expect(
            fixture.atomRegistry.workspaceTabGraph.tabState(fixture.residency.tabID)?
                .allPaneIds.contains(fixture.residency.parent.id) == true
        )
        #expect(
            fixture.atomRegistry.workspacePaneGraph.paneState(fixture.residency.parent.id)?.residency
                == .active
        )
        try expectResidencyBaseItem(
            .tabGraph(originalTargetGraph),
            participantID: .tabGraphs,
            installed: installed
        )
        for paneState in [fixture.residency.parent] + fixture.residency.children {
            try expectResidencyBaseItem(
                .paneGraph(paneState),
                participantID: .paneGraphs,
                installed: installed
            )
        }
        for arrangementID in fixture.residency.arrangementIDs {
            try expectResidencyBaseItem(
                .activePane(
                    arrangementID: arrangementID,
                    paneID: fixture.residency.otherPane.id
                ),
                participantID: .activePanes,
                installed: installed
            )
        }
        try expectResidencyParticipantBaseIsEmpty(
            .activeDrawerChildren,
            installed: installed
        )
    }

    @Test("unchanged and planning rejection advance no revision")
    func unchangedAndPlanningRejectionAdvanceNoRevision() throws {
        // Arrange
        let fixture = makeReactivatePersistenceFixture()
        _ = try installResidencyParticipants(fixture.runtime, openLease: false)
        let missingPaneID = UUIDv7.generate()

        // Act
        let unchanged = fixture.runtime.mutationCoordinator.backgroundPane(
            .init(paneID: fixture.residency.parent.id),
            retainedDrawerPayload: .absent
        )
        let rejected = fixture.runtime.mutationCoordinator.backgroundPane(
            .init(paneID: missingPaneID),
            retainedDrawerPayload: .absent
        )

        // Assert
        #expect(unchanged == .unchanged(revision: .zero))
        #expect(rejected == .rejected(.planning(.paneMissing(missingPaneID))))
        #expect(fixture.runtime.revisionOwner.committedRevision == .zero)
    }

    @Test("transaction admission failure mutates no owner or revision")
    func transactionAdmissionFailureIsAtomic() throws {
        // Arrange
        let fixture = makeBackgroundPersistenceFixture()
        _ = try installResidencyParticipants(fixture.runtime, openLease: false)
        let originalPaneStates = fixture.atomRegistry.workspacePaneGraph.paneStates
        let originalTabStates = fixture.atomRegistry.workspaceTabGraph.tabStates

        // Act
        do {
            let _: WorkspacePersistenceRevision = try fixture.runtime.revisionOwner
                .performSynchronousTransaction { _ -> PreparedResidencyRevisionMutation in
                    let result = fixture.runtime.mutationCoordinator.backgroundPane(
                        .init(paneID: fixture.residency.parent.id),
                        retainedDrawerPayload: .absent
                    )
                    #expect(result == .rejected(.revisionOwner(.reentrantTransaction)))
                    throw WorkspacePaneResidencyPersistenceTestError.abortOuterTransaction
                }
        } catch WorkspacePaneResidencyPersistenceTestError.abortOuterTransaction {
            // Expected cancellation of the outer test transaction.
        }

        // Assert
        #expect(fixture.runtime.revisionOwner.committedRevision == .zero)
        #expect(fixture.atomRegistry.workspacePaneGraph.paneStates == originalPaneStates)
        #expect(fixture.atomRegistry.workspaceTabGraph.tabStates == originalTabStates)
    }
}

private typealias PreparedResidencyRevisionMutation =
    WorkspacePersistencePreparedMutation<WorkspacePersistenceRevision>

private struct ResidencyPersistenceFixture {
    let atomRegistry: AtomRegistry
    let runtime: WorkspacePersistenceRuntime
    let residency: PaneResidencyFixture
    let targetShell: TabShell
    let followingTabID: UUID
    let followingShell: TabShell
    let followingArrangementID: UUID
}

private struct InstalledResidencyParticipants {
    let participantSet: WorkspacePersistenceSnapshotParticipantSet
    let lease: WorkspaceStateSnapshotLease
    let baseMembershipCounts: [WorkspacePersistenceSnapshotParticipantID: Int]
}

@MainActor
private func makeBackgroundPersistenceFixture() -> ResidencyPersistenceFixture {
    let residency = makeResidencyFixture(includeOtherPane: false)
    let atomRegistry = AtomRegistry()
    installResidencyPanes(residency, in: atomRegistry)
    let followingTabID = UUIDv7.generate()
    let followingArrangementID = UUIDv7.generate()
    let targetShell = TabShell(id: residency.tabID, name: "Target")
    let followingShell = TabShell(id: followingTabID, name: "Following")
    let followingGraph = TabGraphState(
        tabId: followingTabID,
        allPaneIds: [residency.otherPane.id],
        arrangements: [
            .init(
                id: followingArrangementID,
                name: "Following",
                isDefault: true,
                layout: Layout(paneId: residency.otherPane.id),
                minimizedPaneIds: [],
                showsMinimizedPanes: false,
                drawerViews: [:]
            )
        ]
    )
    atomRegistry.workspaceTabShell.replaceTabShells([targetShell, followingShell])
    atomRegistry.workspaceTabCursor.replaceActiveTab(residency.tabID)
    atomRegistry.workspaceTabGraph.replaceTabStates([residency.tabState, followingGraph])
    atomRegistry.workspaceArrangementCursor.replaceCursors(
        activeArrangementIdsByTabId: [
            residency.tabID: residency.arrangementIDs[0],
            followingTabID: followingArrangementID,
        ],
        paneCursorsByArrangementId: [
            residency.arrangementIDs[0]: .init(activePaneId: residency.parent.id),
            residency.arrangementIDs[1]: .init(activePaneId: residency.parent.id),
            followingArrangementID: .init(activePaneId: residency.otherPane.id),
        ],
        drawerCursorsByKey: Dictionary(
            uniqueKeysWithValues: residency.arrangementIDs.map {
                (
                    ArrangementDrawerCursorKey(
                        arrangementId: $0,
                        drawerId: residency.drawerID
                    ),
                    ArrangementDrawerCursorState(activeChildId: residency.children[0].id)
                )
            }
        )
    )
    atomRegistry.workspacePanePresentation.setZoomedPaneId(
        residency.parent.id,
        forTab: residency.tabID
    )
    return .init(
        atomRegistry: atomRegistry,
        runtime: WorkspacePersistenceRuntime(atomRegistry: atomRegistry),
        residency: residency,
        targetShell: targetShell,
        followingTabID: followingTabID,
        followingShell: followingShell,
        followingArrangementID: followingArrangementID
    )
}

@MainActor
private func makeReactivatePersistenceFixture() -> ResidencyPersistenceFixture {
    let residency = makeResidencyFixture(parentResidency: .backgrounded)
    let atomRegistry = AtomRegistry()
    installResidencyPanes(residency, in: atomRegistry)
    let targetShell = TabShell(id: residency.tabID, name: "Target")
    atomRegistry.workspaceTabShell.replaceTabShells([targetShell])
    atomRegistry.workspaceTabCursor.replaceActiveTab(residency.tabID)
    atomRegistry.workspaceTabGraph.replaceTabStates([residency.targetGraphForReactivation()])
    atomRegistry.workspaceArrangementCursor.replaceCursors(
        activeArrangementIdsByTabId: [residency.tabID: residency.arrangementIDs[0]],
        paneCursorsByArrangementId: Dictionary(
            uniqueKeysWithValues: residency.arrangementIDs.map {
                ($0, ArrangementPaneCursorState(activePaneId: residency.otherPane.id))
            }
        ),
        drawerCursorsByKey: [:]
    )
    atomRegistry.workspacePanePresentation.setZoomedPaneId(
        residency.otherPane.id,
        forTab: residency.tabID
    )
    return .init(
        atomRegistry: atomRegistry,
        runtime: WorkspacePersistenceRuntime(atomRegistry: atomRegistry),
        residency: residency,
        targetShell: targetShell,
        followingTabID: UUIDv7.generate(),
        followingShell: TabShell(id: UUIDv7.generate(), name: "Unused"),
        followingArrangementID: UUIDv7.generate()
    )
}

@MainActor
private func installResidencyPanes(
    _ residency: PaneResidencyFixture,
    in atomRegistry: AtomRegistry
) {
    for paneState in [residency.parent] + residency.children + [residency.otherPane] {
        atomRegistry.workspacePaneGraph.setCanonicalPaneState(paneState)
    }
}

@MainActor
private func installResidencyParticipants(
    _ runtime: WorkspacePersistenceRuntime,
    openLease: Bool = true
) throws -> InstalledResidencyParticipants {
    guard
        case .constructed(let participantSet) = runtime.snapshotParticipantFactory
            .constructCompositionParticipantSet()
    else {
        throw WorkspacePaneResidencyPersistenceTestError.installationFailed
    }
    let lease = WorkspaceStateSnapshotLease.open(
        pagerIdentity: .make(),
        revisionOwner: runtime.revisionOwner
    )
    var baseMembershipCounts: [WorkspacePersistenceSnapshotParticipantID: Int] = [:]
    if openLease {
        for participant in participantSet.participants {
            guard case .opened(let count) = participant.open(lease: lease) else {
                throw WorkspacePaneResidencyPersistenceTestError.leaseOpenFailed(
                    participant.participantID
                )
            }
            baseMembershipCounts[participant.participantID] = count
        }
    }
    return .init(
        participantSet: participantSet,
        lease: lease,
        baseMembershipCounts: baseMembershipCounts
    )
}

@MainActor
private func expectResidencyBaseItem(
    _ expectedItem: WorkspacePersistenceSnapshotItem,
    participantID: WorkspacePersistenceSnapshotParticipantID,
    installed: InstalledResidencyParticipants
) throws {
    let participant = try requireResidencyParticipant(participantID, installed: installed)
    let count = try #require(installed.baseMembershipCounts[participantID])
    for slotCursor in 0..<count {
        if case .item(let projectedItem, _, _, _) = participant.inspectBaseSlot(
            lease: installed.lease,
            slotCursor: slotCursor
        ), projectedItem.item == expectedItem {
            return
        }
    }
    throw WorkspacePaneResidencyPersistenceTestError.baseItemMissing(expectedItem)
}

@MainActor
private func expectResidencyParticipantBaseIsEmpty(
    _ participantID: WorkspacePersistenceSnapshotParticipantID,
    installed: InstalledResidencyParticipants
) throws {
    let participant = try requireResidencyParticipant(participantID, installed: installed)
    #expect(installed.baseMembershipCounts[participantID] == 0)
    guard case .exhausted = participant.inspectBaseSlot(lease: installed.lease, slotCursor: 0) else {
        throw WorkspacePaneResidencyPersistenceTestError.expectedEmptyParticipant(participantID)
    }
}

@MainActor
private func requireResidencyParticipant(
    _ participantID: WorkspacePersistenceSnapshotParticipantID,
    installed: InstalledResidencyParticipants
) throws -> WorkspacePersistenceSnapshotParticipantSet.Participant {
    guard
        let participant = installed.participantSet.participants.first(where: {
            $0.participantID == participantID
        })
    else { throw WorkspacePaneResidencyPersistenceTestError.participantMissing(participantID) }
    return participant
}

@MainActor
private func closeResidencyParticipants(_ installed: InstalledResidencyParticipants) {
    for participant in installed.participantSet.participants {
        _ = participant.close(lease: installed.lease)
    }
}

private func requireResidencyChanged(
    _ result: WorkspacePaneResidencyPersistenceResult
) throws -> (revision: WorkspacePersistenceRevision, effect: WorkspacePaneResidencyRuntimeEffect) {
    guard case .changed(let revision, let effect) = result else {
        throw WorkspacePaneResidencyPersistenceTestError.expectedChangedResult
    }
    return (revision, effect)
}

private enum WorkspacePaneResidencyPersistenceTestError: Error {
    case abortOuterTransaction
    case baseItemMissing(WorkspacePersistenceSnapshotItem)
    case expectedChangedResult
    case expectedEmptyParticipant(WorkspacePersistenceSnapshotParticipantID)
    case installationFailed
    case leaseOpenFailed(WorkspacePersistenceSnapshotParticipantID)
    case participantMissing(WorkspacePersistenceSnapshotParticipantID)
}
