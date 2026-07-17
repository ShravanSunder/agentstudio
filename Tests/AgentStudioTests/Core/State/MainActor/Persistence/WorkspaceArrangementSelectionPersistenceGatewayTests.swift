import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace arrangement selection persistence gateway")
struct ArrangementSelectionPersistenceGatewayTests {
    @Test("preinstall selection rejects without mutation or revision")
    func preinstallRejects() {
        // Arrange
        let fixture = makeArrangementSelectionPersistenceFixture()

        // Act
        let result = fixture.runtime.mutationCoordinator.setActivePane(
            .init(tabID: fixture.selection.tabID, selection: .selected(fixture.selection.mainPaneIDs[1]))
        )

        // Assert
        #expect(result == .rejected(.compositionDomainNotInstalled(phase: .preinstall)))
        #expect(fixture.runtime.revisionOwner.committedRevision == .zero)
        #expect(
            fixture.atomRegistry.workspaceArrangementCursor.activePaneId(
                forArrangement: fixture.selection.activeArrangementID
            ) == fixture.selection.mainPaneIDs[0]
        )
    }

    @Test("active pane captures one exact cursor preimage and commits one revision")
    func activePaneCapturesOnePreimage() throws {
        // Arrange
        let fixture = makeArrangementSelectionPersistenceFixture()
        let installed = try installArrangementSelectionParticipants(fixture.runtime)

        // Act
        let result = fixture.runtime.mutationCoordinator.setActivePane(
            .init(tabID: fixture.selection.tabID, selection: .selected(fixture.selection.mainPaneIDs[1]))
        )

        // Assert
        let revision = try requireArrangementSelectionChangedRevision(result)
        #expect(revision.rawValue == 1)
        #expect(
            fixture.atomRegistry.workspaceArrangementCursor.activePaneId(
                forArrangement: fixture.selection.activeArrangementID
            ) == fixture.selection.mainPaneIDs[1]
        )
        try expectArrangementSelectionBaseItem(
            .activePane(
                arrangementID: fixture.selection.activeArrangementID,
                paneID: fixture.selection.mainPaneIDs[0]
            ),
            participantID: .activePanes,
            installed: installed
        )
        closeArrangementSelectionParticipants(installed)
    }

    @Test("active drawer child captures one exact cursor preimage and commits one revision")
    func activeDrawerChildCapturesOnePreimage() throws {
        // Arrange
        let fixture = makeArrangementSelectionPersistenceFixture()
        let installed = try installArrangementSelectionParticipants(fixture.runtime)

        // Act
        let result = fixture.runtime.mutationCoordinator.setActiveDrawerChild(
            .init(
                tabID: fixture.selection.tabID,
                drawerID: fixture.selection.drawerID,
                childPaneID: fixture.selection.drawerChildIDs[1]
            )
        )

        // Assert
        let revision = try requireArrangementSelectionChangedRevision(result)
        #expect(revision.rawValue == 1)
        #expect(
            fixture.atomRegistry.workspaceArrangementCursor.activeChildId(
                forArrangement: fixture.selection.activeArrangementID,
                drawerId: fixture.selection.drawerID
            ) == fixture.selection.drawerChildIDs[1]
        )
        try expectArrangementSelectionBaseItem(
            .activeDrawerChild(
                key: fixture.selection.drawerCursorKey,
                childPaneID: fixture.selection.drawerChildIDs[0]
            ),
            participantID: .activeDrawerChildren,
            installed: installed
        )
        closeArrangementSelectionParticipants(installed)
    }

    @Test("semantic no-op and rejection advance zero revisions")
    func noOpAndRejectionAdvanceZeroRevisions() throws {
        // Arrange
        let fixture = makeArrangementSelectionPersistenceFixture()
        _ = try installArrangementSelectionParticipants(fixture.runtime, openLease: false)
        let missingPaneID = UUIDv7.generate()

        // Act
        let unchanged = fixture.runtime.mutationCoordinator.setActivePane(
            .init(tabID: fixture.selection.tabID, selection: .selected(fixture.selection.mainPaneIDs[0]))
        )
        let rejected = fixture.runtime.mutationCoordinator.setActivePane(
            .init(tabID: fixture.selection.tabID, selection: .selected(missingPaneID))
        )

        // Assert
        #expect(unchanged == .unchanged(revision: .zero))
        #expect(
            rejected
                == .rejected(
                    .planning(
                        .paneNotOwnedByTab(
                            tabID: fixture.selection.tabID,
                            paneID: missingPaneID
                        )
                    )
                )
        )
        #expect(fixture.runtime.revisionOwner.committedRevision == .zero)
    }

    @Test("missing and present-no-selection insertions stay outside the fixed base")
    func insertionsStayOutsideFixedBase() throws {
        for initialCursor in [InitialArrangementActivePaneCursor.missing, .noSelection] {
            // Arrange
            let fixture = makeArrangementSelectionPersistenceFixture(activePaneCursor: initialCursor)
            let installed = try installArrangementSelectionParticipants(fixture.runtime)

            // Act
            let result = fixture.runtime.mutationCoordinator.setActivePane(
                .init(
                    tabID: fixture.selection.tabID,
                    selection: .selected(fixture.selection.mainPaneIDs[1])
                )
            )

            // Assert
            #expect(try requireArrangementSelectionChangedRevision(result).rawValue == 1)
            #expect(
                fixture.atomRegistry.workspaceArrangementCursor.activePaneId(
                    forArrangement: fixture.selection.activeArrangementID
                ) == fixture.selection.mainPaneIDs[1]
            )
            try expectArrangementSelectionBaseItemAbsent(
                .activePane(arrangementID: fixture.selection.activeArrangementID),
                participantID: .activePanes,
                installed: installed
            )
            closeArrangementSelectionParticipants(installed)
        }
    }

    @Test("selected to no-selection captures the fixed-base value as a removal tombstone")
    func removalRetainsFixedBaseValue() throws {
        // Arrange
        let fixture = makeArrangementSelectionPersistenceFixture()
        let installed = try installArrangementSelectionParticipants(fixture.runtime)

        // Act
        let result = fixture.runtime.mutationCoordinator.setActivePane(
            .init(tabID: fixture.selection.tabID, selection: .noSelection)
        )

        // Assert
        #expect(try requireArrangementSelectionChangedRevision(result).rawValue == 1)
        #expect(
            fixture.atomRegistry.workspaceArrangementCursor.activePaneId(
                forArrangement: fixture.selection.activeArrangementID
            ) == nil
        )
        #expect(
            fixture.atomRegistry.workspaceArrangementCursor.hasPaneCursor(
                arrangementID: fixture.selection.activeArrangementID
            )
        )
        try expectArrangementSelectionBaseItem(
            .activePane(
                arrangementID: fixture.selection.activeArrangementID,
                paneID: fixture.selection.mainPaneIDs[0]
            ),
            participantID: .activePanes,
            installed: installed
        )
        closeArrangementSelectionParticipants(installed)
    }

    @Test("gateway reads only target keys and preserves a large unrelated fleet")
    func targetKeyedGatewayPreservesUnrelatedFleet() throws {
        // Arrange
        let fixture = makeArrangementSelectionPersistenceFixture()
        let source = try arrangementSelectionGatewayProductionSource()
        let unrelatedTabs = (0..<256).map { index in
            let tabID = UUIDv7.generate()
            let arrangementID = UUIDv7.generate()
            let paneID = UUIDv7.generate()
            return (
                tab: TabGraphState(
                    tabId: tabID,
                    allPaneIds: [paneID],
                    arrangements: [
                        .init(
                            id: arrangementID,
                            name: "Unrelated \(index)",
                            isDefault: true,
                            layout: Layout(paneId: paneID),
                            minimizedPaneIds: [],
                            showsMinimizedPanes: true,
                            drawerViews: [:]
                        )
                    ]
                ),
                arrangementID: arrangementID,
                paneID: paneID
            )
        }
        let graphBefore = [fixture.selection.tabState] + unrelatedTabs.map(\.tab)
        var activeArrangementsBefore = [fixture.selection.tabID: fixture.selection.activeArrangementID]
        var paneCursorsBefore: [UUID: ArrangementPaneCursorState] = [
            fixture.selection.activeArrangementID: .init(activePaneId: fixture.selection.mainPaneIDs[0]),
            fixture.selection.inactiveArrangementID: .init(activePaneId: fixture.selection.inactivePaneID),
        ]
        for unrelated in unrelatedTabs {
            activeArrangementsBefore[unrelated.tab.tabId] = unrelated.arrangementID
            paneCursorsBefore[unrelated.arrangementID] = .init(activePaneId: unrelated.paneID)
        }
        let drawersBefore = fixture.atomRegistry.workspaceArrangementCursor.drawerCursorsByKey
        fixture.atomRegistry.workspaceTabGraph.replaceTabStates(graphBefore)
        fixture.atomRegistry.workspaceArrangementCursor.replaceCursors(
            activeArrangementIdsByTabId: activeArrangementsBefore,
            paneCursorsByArrangementId: paneCursorsBefore,
            drawerCursorsByKey: drawersBefore
        )
        let installed = try installArrangementSelectionParticipants(fixture.runtime, openLease: false)

        // Act
        let result = fixture.runtime.mutationCoordinator.setActivePane(
            .init(
                tabID: fixture.selection.tabID,
                selection: .selected(fixture.selection.mainPaneIDs[1])
            )
        )

        // Assert
        #expect(try requireArrangementSelectionChangedRevision(result).rawValue == 1)
        #expect(source.contains("workspaceTabGraphAtom.tabState(tabID)"))
        #expect(source.contains("workspaceArrangementCursorAtom.activeArrangementId(forTab:"))
        #expect(source.contains("workspaceArrangementCursorAtom.hasPaneCursor(arrangementID:"))
        #expect(source.contains("workspaceArrangementCursorAtom.hasDrawerCursor(cursorKey)"))
        #expect(!source.contains("workspaceTabGraphAtom.tabStates"))
        #expect(!source.contains("workspaceArrangementCursorAtom.activeArrangementIdsByTabId"))
        #expect(!source.contains("workspaceArrangementCursorAtom.paneCursorsByArrangementId"))
        #expect(!source.contains("workspaceArrangementCursorAtom.drawerCursorsByKey"))
        #expect(fixture.atomRegistry.workspaceTabGraph.tabStates == graphBefore)
        for unrelated in unrelatedTabs {
            #expect(
                fixture.atomRegistry.workspaceArrangementCursor.activeArrangementId(forTab: unrelated.tab.tabId)
                    == unrelated.arrangementID
            )
            #expect(
                fixture.atomRegistry.workspaceArrangementCursor.activePaneId(
                    forArrangement: unrelated.arrangementID
                ) == unrelated.paneID
            )
        }
        #expect(fixture.atomRegistry.workspaceArrangementCursor.drawerCursorsByKey == drawersBefore)
        closeArrangementSelectionParticipants(installed)
    }
}

private struct ArrangementSelectionPersistenceFixture {
    let atomRegistry: AtomRegistry
    let runtime: WorkspacePersistenceRuntime
    let selection: ArrangementSelectionFixture
}

private enum InitialArrangementActivePaneCursor {
    case missing
    case noSelection
    case selected
}

private func requireArrangementSelectionChangedRevision(
    _ result: WorkspaceArrangementSelectionPersistenceResult
) throws -> WorkspacePersistenceRevision {
    guard case .changed(let revision) = result else {
        throw WorkspaceArrangementSelectionPersistenceTestError.expectedChangedResult
    }
    return revision
}

private struct InstalledArrangementSelectionParticipants {
    let participantSet: WorkspacePersistenceSnapshotParticipantSet
    let lease: WorkspaceStateSnapshotLease
    let baseMembershipCounts: [WorkspacePersistenceSnapshotParticipantID: Int]
}

@MainActor
private func makeArrangementSelectionPersistenceFixture() -> ArrangementSelectionPersistenceFixture {
    makeArrangementSelectionPersistenceFixture(activePaneCursor: .selected)
}

@MainActor
private func makeArrangementSelectionPersistenceFixture(
    activePaneCursor: InitialArrangementActivePaneCursor
) -> ArrangementSelectionPersistenceFixture {
    let selection = makeArrangementSelectionFixture()
    let atomRegistry = AtomRegistry()
    atomRegistry.workspaceTabGraph.replaceTabStates([selection.tabState])
    var paneCursorsByArrangementID: [UUID: ArrangementPaneCursorState] = [
        selection.inactiveArrangementID: .init(activePaneId: selection.inactivePaneID)
    ]
    switch activePaneCursor {
    case .missing:
        break
    case .noSelection:
        paneCursorsByArrangementID[selection.activeArrangementID] = .init(activePaneId: nil)
    case .selected:
        paneCursorsByArrangementID[selection.activeArrangementID] = .init(
            activePaneId: selection.mainPaneIDs[0]
        )
    }
    atomRegistry.workspaceArrangementCursor.replaceCursors(
        activeArrangementIdsByTabId: [selection.tabID: selection.activeArrangementID],
        paneCursorsByArrangementId: paneCursorsByArrangementID,
        drawerCursorsByKey: [
            selection.drawerCursorKey: .init(activeChildId: selection.drawerChildIDs[0])
        ]
    )
    return .init(
        atomRegistry: atomRegistry,
        runtime: WorkspacePersistenceRuntime(atomRegistry: atomRegistry),
        selection: selection
    )
}

@MainActor
private func installArrangementSelectionParticipants(
    _ runtime: WorkspacePersistenceRuntime,
    openLease: Bool = true
) throws -> InstalledArrangementSelectionParticipants {
    guard
        case .constructed(let participantSet) = runtime.snapshotParticipantFactory
            .constructCompositionParticipantSet()
    else {
        throw WorkspaceArrangementSelectionPersistenceTestError.installationFailed
    }
    let lease = WorkspaceStateSnapshotLease.open(
        pagerIdentity: .make(),
        revisionOwner: runtime.revisionOwner
    )
    var baseMembershipCounts: [WorkspacePersistenceSnapshotParticipantID: Int] = [:]
    if openLease {
        for participant in participantSet.participants {
            guard case .opened(let count) = participant.open(lease: lease) else {
                throw WorkspaceArrangementSelectionPersistenceTestError.leaseOpenFailed(participant.participantID)
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
private func expectArrangementSelectionBaseItem(
    _ expectedItem: WorkspacePersistenceSnapshotItem,
    participantID: WorkspacePersistenceSnapshotParticipantID,
    installed: InstalledArrangementSelectionParticipants
) throws {
    guard
        let participant = installed.participantSet.participants.first(where: {
            $0.participantID == participantID
        }),
        let count = installed.baseMembershipCounts[participantID]
    else {
        throw WorkspaceArrangementSelectionPersistenceTestError.participantMissing(participantID)
    }
    for slotCursor in 0..<count {
        if case .item(let projectedItem, _, _, _) = participant.inspectBaseSlot(
            lease: installed.lease,
            slotCursor: slotCursor
        ), projectedItem.item == expectedItem {
            return
        }
    }
    throw WorkspaceArrangementSelectionPersistenceTestError.baseItemMissing(expectedItem)
}

@MainActor
private func expectArrangementSelectionBaseItemAbsent(
    _ unexpectedItemID: WorkspacePersistenceSnapshotItemID,
    participantID: WorkspacePersistenceSnapshotParticipantID,
    installed: InstalledArrangementSelectionParticipants
) throws {
    guard
        let participant = installed.participantSet.participants.first(where: {
            $0.participantID == participantID
        }),
        let count = installed.baseMembershipCounts[participantID]
    else {
        throw WorkspaceArrangementSelectionPersistenceTestError.participantMissing(participantID)
    }
    for slotCursor in 0..<count {
        if case .item(let projectedItem, _, _, _) = participant.inspectBaseSlot(
            lease: installed.lease,
            slotCursor: slotCursor
        ), projectedItem.item.snapshotItemID == unexpectedItemID {
            throw WorkspaceArrangementSelectionPersistenceTestError.unexpectedBaseItem(unexpectedItemID)
        }
    }
}

private func arrangementSelectionGatewayProductionSource() throws -> String {
    let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
    let sourceURL = projectRoot.appending(
        path:
            "Sources/AgentStudio/Core/State/MainActor/Persistence/"
            + "WorkspaceArrangementSelectionPersistenceGateway.swift"
    )
    return try String(contentsOf: sourceURL, encoding: .utf8)
}

@MainActor
private func closeArrangementSelectionParticipants(_ installed: InstalledArrangementSelectionParticipants) {
    for participant in installed.participantSet.participants {
        _ = participant.close(lease: installed.lease)
    }
}

private enum WorkspaceArrangementSelectionPersistenceTestError: Error {
    case baseItemMissing(WorkspacePersistenceSnapshotItem)
    case expectedChangedResult
    case installationFailed
    case leaseOpenFailed(WorkspacePersistenceSnapshotParticipantID)
    case participantMissing(WorkspacePersistenceSnapshotParticipantID)
    case unexpectedBaseItem(WorkspacePersistenceSnapshotItemID)
}
