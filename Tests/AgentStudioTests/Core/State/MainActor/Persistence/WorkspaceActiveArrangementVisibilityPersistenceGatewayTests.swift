import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace active arrangement visibility persistence gateway")
struct WorkspaceVisibilityGatewayTests {
    @Test("planning captures only keyed target witnesses")
    func planningCapturesOnlyKeyedTargetWitnesses() throws {
        // Arrange
        let projectRoot = TestPathResolver.projectRoot(from: #filePath)
        let gatewayPath = URL(fileURLWithPath: projectRoot)
            .appendingPathComponent(
                "Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceActiveArrangementVisibilityPersistenceGateway.swift"
            )
        let source = try String(contentsOf: gatewayPath, encoding: .utf8)
        let forbiddenFleetReads = [
            ".tabStates",
            ".activeArrangementIdsByTabId",
            ".paneCursorsByArrangementId",
            ".zoomedPaneIdsByTabId",
        ]

        // Act
        let presentFleetReads = forbiddenFleetReads.filter(source.contains)

        // Assert
        #expect(presentFleetReads.isEmpty)
    }

    @Test("preinstall mutation rejects without state or revision")
    func preinstallRejects() {
        // Arrange
        let fixture = makeVisibilityPersistenceFixture()

        // Act
        let result = fixture.runtime.mutationCoordinator.minimizePane(
            .init(tabID: fixture.visibility.tabID, paneID: fixture.visibility.paneIDs[0])
        )

        // Assert
        #expect(result == .rejected(.compositionDomainNotInstalled(phase: .preinstall)))
        #expect(fixture.runtime.revisionOwner.committedRevision == .zero)
        #expect(
            fixture.atomRegistry.workspaceArrangementCursor.activePaneId(
                forArrangement: fixture.visibility.defaultArrangementID
            ) == fixture.visibility.paneIDs[0]
        )
        #expect(
            fixture.atomRegistry.workspacePanePresentation.zoomedPaneId(forTab: fixture.visibility.tabID)
                == fixture.visibility.paneIDs[0]
        )
    }

    @Test("minimize captures graph and pane cursor in one fixed revision")
    func minimizeCapturesGraphAndPaneCursorAtomically() throws {
        // Arrange
        let fixture = makeVisibilityPersistenceFixture()
        let installed = try installVisibilityParticipants(fixture.runtime)

        // Act
        let result = fixture.runtime.mutationCoordinator.minimizePane(
            .init(tabID: fixture.visibility.tabID, paneID: fixture.visibility.paneIDs[0])
        )

        // Assert
        let receipt = try requireVisibilityChangedReceipt(result)
        #expect(receipt.revision.rawValue == 1)
        #expect(receipt.effect == .minimizePane(paneID: fixture.visibility.paneIDs[0]))
        #expect(
            fixture.atomRegistry.workspaceTabGraph.tabState(fixture.visibility.tabID)?
                .arrangements[0].minimizedPaneIds
                == [fixture.visibility.paneIDs[0], fixture.visibility.paneIDs[2]]
        )
        #expect(
            fixture.atomRegistry.workspaceArrangementCursor.activePaneId(
                forArrangement: fixture.visibility.defaultArrangementID
            ) == fixture.visibility.paneIDs[1]
        )
        #expect(
            fixture.atomRegistry.workspacePanePresentation.zoomedPaneId(forTab: fixture.visibility.tabID) == nil
        )
        try expectVisibilityBaseItem(
            .tabGraph(fixture.visibility.tabState),
            participantID: .tabGraphs,
            installed: installed
        )
        try expectVisibilityBaseItem(
            .activePane(
                arrangementID: fixture.visibility.defaultArrangementID,
                paneID: fixture.visibility.paneIDs[0]
            ),
            participantID: .activePanes,
            installed: installed
        )
        closeVisibilityParticipants(installed)
    }

    @Test("switch captures active arrangement and repaired pane cursor in one revision")
    func switchCapturesCursorParticipantsAtomically() throws {
        // Arrange
        let fixture = makeVisibilityPersistenceFixture(invalidCustomSelection: true)
        let installed = try installVisibilityParticipants(fixture.runtime)

        // Act
        let result = fixture.runtime.mutationCoordinator.switchArrangement(
            .init(
                tabID: fixture.visibility.tabID,
                arrangementID: fixture.visibility.customArrangementID
            )
        )

        // Assert
        let receipt = try requireVisibilityChangedReceipt(result)
        #expect(receipt.revision.rawValue == 1)
        guard case .switchArrangement = receipt.effect else {
            Issue.record("expected switch-arrangement effect")
            return
        }
        #expect(
            fixture.atomRegistry.workspaceArrangementCursor.activeArrangementId(forTab: fixture.visibility.tabID)
                == fixture.visibility.customArrangementID
        )
        #expect(
            fixture.atomRegistry.workspaceArrangementCursor.activePaneId(
                forArrangement: fixture.visibility.customArrangementID
            ) == fixture.visibility.paneIDs[1]
        )
        try expectVisibilityBaseItem(
            .activeArrangement(
                tabID: fixture.visibility.tabID,
                arrangementID: fixture.visibility.defaultArrangementID
            ),
            participantID: .activeArrangements,
            installed: installed
        )
        try expectVisibilityBaseItem(
            .activePane(
                arrangementID: fixture.visibility.customArrangementID,
                paneID: fixture.visibility.paneIDs[2]
            ),
            participantID: .activePanes,
            installed: installed
        )
        closeVisibilityParticipants(installed)
    }

    @Test("shows-minimized and expand retain typed effects and exact revisions")
    func showsMinimizedAndExpandReturnTypedEffects() throws {
        // Arrange
        let showsFixture = makeVisibilityPersistenceFixture()
        _ = try installVisibilityParticipants(showsFixture.runtime, openLease: false)
        let expandFixture = makeVisibilityPersistenceFixture()
        _ = try installVisibilityParticipants(expandFixture.runtime, openLease: false)

        // Act
        let showsResult = showsFixture.runtime.mutationCoordinator.setShowsMinimizedPanes(
            .init(tabID: showsFixture.visibility.tabID, showsMinimizedPanes: false)
        )
        let expandResult = expandFixture.runtime.mutationCoordinator.expandPane(
            .init(tabID: expandFixture.visibility.tabID, paneID: expandFixture.visibility.paneIDs[2])
        )

        // Assert
        let showsReceipt = try requireVisibilityChangedReceipt(showsResult)
        let expandReceipt = try requireVisibilityChangedReceipt(expandResult)
        #expect(showsReceipt.revision.rawValue == 1)
        guard case .setShowsMinimizedPanes = showsReceipt.effect else {
            Issue.record("expected set-shows-minimized effect")
            return
        }
        #expect(expandReceipt.revision.rawValue == 1)
        #expect(expandReceipt.effect == .expandPane(paneID: expandFixture.visibility.paneIDs[2]))
    }

    @Test("semantic no-ops and planning rejections do not advance revision")
    func noOpsAndRejectionsDoNotAdvanceRevision() throws {
        // Arrange
        let fixture = makeVisibilityPersistenceFixture()
        _ = try installVisibilityParticipants(fixture.runtime, openLease: false)
        let missingPaneID = UUIDv7.generate()

        // Act
        let switchResult = fixture.runtime.mutationCoordinator.switchArrangement(
            .init(
                tabID: fixture.visibility.tabID,
                arrangementID: fixture.visibility.defaultArrangementID
            )
        )
        let showsResult = fixture.runtime.mutationCoordinator.setShowsMinimizedPanes(
            .init(tabID: fixture.visibility.tabID, showsMinimizedPanes: true)
        )
        let expandResult = fixture.runtime.mutationCoordinator.expandPane(
            .init(tabID: fixture.visibility.tabID, paneID: fixture.visibility.paneIDs[1])
        )
        let rejection = fixture.runtime.mutationCoordinator.minimizePane(
            .init(tabID: fixture.visibility.tabID, paneID: missingPaneID)
        )

        // Assert
        #expect(switchResult == .unchanged(revision: .zero))
        #expect(showsResult == .unchanged(revision: .zero))
        #expect(expandResult == .unchanged(revision: .zero))
        #expect(
            rejection
                == .rejected(
                    .planning(
                        .paneNotOwnedByTab(
                            tabID: fixture.visibility.tabID,
                            paneID: missingPaneID
                        )
                    )
                )
        )
        #expect(fixture.runtime.revisionOwner.committedRevision == .zero)
    }
}

private struct VisibilityPersistenceFixture {
    let atomRegistry: AtomRegistry
    let runtime: WorkspacePersistenceRuntime
    let visibility: ActiveArrangementVisibilityFixture
}

private struct InstalledVisibilityParticipants {
    let participantSet: WorkspacePersistenceSnapshotParticipantSet
    let lease: WorkspaceStateSnapshotLease
    let baseMembershipCounts: [WorkspacePersistenceSnapshotParticipantID: Int]
}

@MainActor
private func makeVisibilityPersistenceFixture(
    invalidCustomSelection: Bool = false
) -> VisibilityPersistenceFixture {
    let visibility = makeVisibilityFixture()
    let atomRegistry = AtomRegistry()
    atomRegistry.workspaceTabGraph.replaceTabStates([visibility.tabState])
    var paneCursors = visibility.paneCursorsByArrangementID
    if invalidCustomSelection {
        paneCursors[visibility.customArrangementID] = .init(activePaneId: visibility.paneIDs[2])
    }
    atomRegistry.workspaceArrangementCursor.replaceCursors(
        activeArrangementIdsByTabId: [visibility.tabID: visibility.defaultArrangementID],
        paneCursorsByArrangementId: paneCursors,
        drawerCursorsByKey: [:]
    )
    atomRegistry.workspacePanePresentation.setZoomedPaneId(
        visibility.paneIDs[0],
        forTab: visibility.tabID
    )
    return VisibilityPersistenceFixture(
        atomRegistry: atomRegistry,
        runtime: WorkspacePersistenceRuntime(atomRegistry: atomRegistry),
        visibility: visibility
    )
}

@MainActor
private func installVisibilityParticipants(
    _ runtime: WorkspacePersistenceRuntime,
    openLease: Bool = true
) throws -> InstalledVisibilityParticipants {
    guard
        case .constructed(let participantSet) = runtime.snapshotParticipantFactory
            .constructCompositionParticipantSet()
    else {
        throw WorkspaceVisibilityPersistenceTestError.installationFailed
    }
    let lease = WorkspaceStateSnapshotLease.open(
        pagerIdentity: .make(),
        revisionOwner: runtime.revisionOwner
    )
    var baseMembershipCounts: [WorkspacePersistenceSnapshotParticipantID: Int] = [:]
    if openLease {
        for participant in participantSet.participants {
            guard case .opened(let count) = participant.open(lease: lease) else {
                throw WorkspaceVisibilityPersistenceTestError.leaseOpenFailed(participant.participantID)
            }
            baseMembershipCounts[participant.participantID] = count
        }
    }
    return InstalledVisibilityParticipants(
        participantSet: participantSet,
        lease: lease,
        baseMembershipCounts: baseMembershipCounts
    )
}

@MainActor
private func expectVisibilityBaseItem(
    _ expectedItem: WorkspacePersistenceSnapshotItem,
    participantID: WorkspacePersistenceSnapshotParticipantID,
    installed: InstalledVisibilityParticipants
) throws {
    guard
        let participant = installed.participantSet.participants.first(where: {
            $0.participantID == participantID
        }),
        let count = installed.baseMembershipCounts[participantID]
    else {
        throw WorkspaceVisibilityPersistenceTestError.participantMissing(participantID)
    }
    for slotCursor in 0..<count {
        if case .item(let projectedItem, _, _, _) = participant.inspectBaseSlot(
            lease: installed.lease,
            slotCursor: slotCursor
        ), projectedItem.item == expectedItem {
            return
        }
    }
    throw WorkspaceVisibilityPersistenceTestError.baseItemMissing(expectedItem)
}

@MainActor
private func closeVisibilityParticipants(_ installed: InstalledVisibilityParticipants) {
    for participant in installed.participantSet.participants {
        _ = participant.close(lease: installed.lease)
    }
}

private func requireVisibilityChangedReceipt(
    _ result: WorkspaceVisibilityPersistenceResult
) throws -> (revision: WorkspacePersistenceRevision, effect: WorkspaceActiveArrangementVisibilityEffect) {
    guard case .changed(let revision, let effect) = result else {
        throw WorkspaceVisibilityPersistenceTestError.expectedChangedReceipt
    }
    return (revision, effect)
}

private enum WorkspaceVisibilityPersistenceTestError: Error {
    case baseItemMissing(WorkspacePersistenceSnapshotItem)
    case expectedChangedReceipt
    case installationFailed
    case leaseOpenFailed(WorkspacePersistenceSnapshotParticipantID)
    case participantMissing(WorkspacePersistenceSnapshotParticipantID)
}
