import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace persistence tab leaf mutations")
struct WorkspacePersistenceTabLeafMutationTests {
    @Test("preinstall tab leaf mutation rejects without state or revision")
    func preinstallMutationRejects() {
        // Arrange
        let fixture = makeTabLeafPersistenceFixture()

        // Act
        let result = fixture.runtime.mutationCoordinator.selectTab(.init(tabID: fixture.shells[1].id))

        // Assert
        #expect(result == .rejected(.compositionDomainNotInstalled(phase: .preinstall)))
        #expect(fixture.runtime.revisionOwner.committedRevision == .zero)
        #expect(fixture.atomRegistry.workspaceTabCursor.activeTabId == fixture.shells[0].id)
    }

    @Test("installed select retains the fixed-base cursor preimage")
    func installedSelectRetainsCursorPreimage() throws {
        // Arrange
        let fixture = makeTabLeafPersistenceFixture()
        let installed = try installTabLeafParticipants(fixture.runtime, opening: [.activeTab])

        // Act
        let result = fixture.runtime.mutationCoordinator.selectTab(.init(tabID: fixture.shells[1].id))

        // Assert
        #expect(try requireChangedRevision(result).rawValue == 1)
        #expect(fixture.atomRegistry.workspaceTabCursor.activeTabId == fixture.shells[1].id)
        try expectBaseItems(
            [.activeTab(fixture.shells[0].id)],
            participantID: .activeTab,
            installed: installed
        )
    }

    @Test("installed rename retains the exact shell and sort-index preimage")
    func installedRenameRetainsShellPreimage() throws {
        // Arrange
        let fixture = makeTabLeafPersistenceFixture()
        let installed = try installTabLeafParticipants(fixture.runtime, opening: [.tabShells])

        // Act
        let result = fixture.runtime.mutationCoordinator.renameTab(
            .init(tabID: fixture.shells[1].id, name: "  Renamed  ")
        )

        // Assert
        #expect(try requireChangedRevision(result).rawValue == 1)
        #expect(fixture.atomRegistry.workspaceTabShell.tabShells[1].name == "Renamed")
        try expectBaseItems(
            fixture.shells.enumerated().map { .tabShell(.init(shell: $0.element, sortIndex: $0.offset)) },
            participantID: .tabShells,
            installed: installed
        )
    }

    @Test("installed delta move captures every shifted sort-index key")
    func installedMoveCapturesEveryShiftedShell() throws {
        // Arrange
        let fixture = makeTabLeafPersistenceFixture()
        let installed = try installTabLeafParticipants(fixture.runtime, opening: [.tabShells])

        // Act
        let result = fixture.runtime.mutationCoordinator.moveTabByDelta(
            .init(tabID: fixture.shells[0].id, delta: 2)
        )

        // Assert
        #expect(try requireChangedRevision(result).rawValue == 1)
        #expect(
            fixture.atomRegistry.workspaceTabShell.tabShells == [
                fixture.shells[1], fixture.shells[2], fixture.shells[0],
            ])
        try expectBaseItems(
            fixture.shells.enumerated().map { .tabShell(.init(shell: $0.element, sortIndex: $0.offset)) },
            participantID: .tabShells,
            installed: installed
        )
    }

    @Test("combined reorder and selection commits both owners in one revision")
    func combinedReorderAndSelectCommitsOneRevision() throws {
        // Arrange
        let fixture = makeTabLeafPersistenceFixture(activeTabIndex: 2)
        let installed = try installTabLeafParticipants(fixture.runtime, opening: [.tabShells, .activeTab])

        // Act
        let result = fixture.runtime.mutationCoordinator.reorderAndSelectTab(
            .init(tabID: fixture.shells[0].id, toIndex: 2)
        )

        // Assert
        #expect(try requireChangedRevision(result).rawValue == 1)
        #expect(fixture.runtime.revisionOwner.committedRevision.rawValue == 1)
        #expect(
            fixture.atomRegistry.workspaceTabShell.tabShells == [
                fixture.shells[1], fixture.shells[0], fixture.shells[2],
            ])
        #expect(fixture.atomRegistry.workspaceTabCursor.activeTabId == fixture.shells[0].id)
        try expectBaseItems(
            fixture.shells.enumerated().map { .tabShell(.init(shell: $0.element, sortIndex: $0.offset)) },
            participantID: .tabShells,
            installed: installed
        )
        try expectBaseItems(
            [.activeTab(fixture.shells[2].id)],
            participantID: .activeTab,
            installed: installed
        )
    }

    @Test("installed semantic no-ops do not advance the revision")
    func installedNoOpsDoNotAdvanceRevision() throws {
        // Arrange
        let fixture = makeTabLeafPersistenceFixture()
        _ = try installTabLeafParticipants(fixture.runtime, opening: [])

        // Act
        let selectResult = fixture.runtime.mutationCoordinator.selectTab(.init(tabID: fixture.shells[0].id))
        let renameResult = fixture.runtime.mutationCoordinator.renameTab(
            .init(tabID: fixture.shells[0].id, name: " A ")
        )
        let moveResult = fixture.runtime.mutationCoordinator.moveTabByDelta(
            .init(tabID: fixture.shells[0].id, delta: -1)
        )
        let reorderResult = fixture.runtime.mutationCoordinator.reorderAndSelectTab(
            .init(tabID: fixture.shells[0].id, toIndex: 0)
        )

        // Assert
        #expect(selectResult == .unchanged(revision: .zero))
        #expect(renameResult == .unchanged(revision: .zero))
        #expect(moveResult == .unchanged(revision: .zero))
        #expect(reorderResult == .unchanged(revision: .zero))
        #expect(fixture.runtime.revisionOwner.committedRevision == .zero)
    }
}

private struct TabLeafPersistenceFixture {
    let atomRegistry: AtomRegistry
    let runtime: WorkspacePersistenceRuntime
    let shells: [TabShell]
}

private struct InstalledTabLeafParticipants {
    let participantSet: WorkspacePersistenceSnapshotParticipantSet
    let lease: WorkspaceStateSnapshotLease
}

@MainActor
private func makeTabLeafPersistenceFixture(activeTabIndex: Int = 0) -> TabLeafPersistenceFixture {
    let atomRegistry = AtomRegistry()
    let shells = ["A", "B", "C"].map { TabShell(id: UUIDv7.generate(), name: $0) }
    atomRegistry.workspaceTabShell.replaceTabShells(shells)
    atomRegistry.workspaceTabCursor.replaceActiveTab(shells[activeTabIndex].id)
    return TabLeafPersistenceFixture(
        atomRegistry: atomRegistry,
        runtime: WorkspacePersistenceRuntime(atomRegistry: atomRegistry),
        shells: shells
    )
}

@MainActor
private func installTabLeafParticipants(
    _ runtime: WorkspacePersistenceRuntime,
    opening participantIDs: Set<WorkspacePersistenceSnapshotParticipantID>
) throws -> InstalledTabLeafParticipants {
    guard
        case .constructed(let participantSet) = runtime.snapshotParticipantFactory
            .constructCompositionParticipantSet()
    else {
        throw WorkspacePersistenceTabLeafMutationTestError.installationFailed
    }
    let lease = WorkspaceStateSnapshotLease.open(
        pagerIdentity: .make(),
        revisionOwner: runtime.revisionOwner
    )
    for participantID in participantIDs {
        let participant = try requireTabLeafParticipant(participantID, from: participantSet)
        let expectedCount = participantID == .tabShells ? 3 : 1
        guard participant.open(lease: lease) == .opened(baseMembershipCount: expectedCount) else {
            throw WorkspacePersistenceTabLeafMutationTestError.leaseOpenFailed(participantID)
        }
    }
    return InstalledTabLeafParticipants(participantSet: participantSet, lease: lease)
}

@MainActor
private func expectBaseItems(
    _ expectedItems: [WorkspacePersistenceSnapshotItem],
    participantID: WorkspacePersistenceSnapshotParticipantID,
    installed: InstalledTabLeafParticipants
) throws {
    let participant = try requireTabLeafParticipant(participantID, from: installed.participantSet)
    for (slotIndex, expectedItem) in expectedItems.enumerated() {
        guard
            case .item(let projectedItem, _, _, _) = participant.inspectBaseSlot(
                lease: installed.lease,
                slotCursor: slotIndex
            )
        else {
            throw WorkspacePersistenceTabLeafMutationTestError.baseItemMissing(participantID, slotIndex)
        }
        #expect(projectedItem.item == expectedItem)
    }
    _ = participant.close(lease: installed.lease)
}

@MainActor
private func requireTabLeafParticipant(
    _ participantID: WorkspacePersistenceSnapshotParticipantID,
    from participantSet: WorkspacePersistenceSnapshotParticipantSet
) throws -> WorkspacePersistenceSnapshotParticipantSet.Participant {
    guard let participant = participantSet.participants.first(where: { $0.participantID == participantID }) else {
        throw WorkspacePersistenceTabLeafMutationTestError.participantMissing(participantID)
    }
    return participant
}

private func requireChangedRevision(
    _ result: WorkspacePersistenceMutationResult
) throws -> WorkspacePersistenceRevision {
    guard case .changed(let revision) = result else {
        throw WorkspacePersistenceTabLeafMutationTestError.expectedChangedResult
    }
    return revision
}

private enum WorkspacePersistenceTabLeafMutationTestError: Error {
    case baseItemMissing(WorkspacePersistenceSnapshotParticipantID, Int)
    case expectedChangedResult
    case installationFailed
    case leaseOpenFailed(WorkspacePersistenceSnapshotParticipantID)
    case participantMissing(WorkspacePersistenceSnapshotParticipantID)
}
