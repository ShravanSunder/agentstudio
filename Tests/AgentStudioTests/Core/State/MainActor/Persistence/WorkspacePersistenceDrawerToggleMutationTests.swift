import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace persistence drawer toggle mutations")
struct WorkspacePersistenceDrawerToggleMutationTests {
    @Test("preinstall and invalid parent reject without mutation or revision")
    func preinstallAndInvalidParentReject() throws {
        // Arrange
        let fixture = makeDrawerTogglePersistenceFixture()

        // Act
        let preinstallResult = fixture.runtime.mutationCoordinator.toggleDrawer(
            .init(parentPaneID: fixture.firstParent.id)
        )
        _ = try installDrawerCursorParticipant(fixture.runtime, openingLease: false)
        let missingPaneID = UUIDv7.generate()
        let missingResult = fixture.runtime.mutationCoordinator.toggleDrawer(
            .init(parentPaneID: missingPaneID)
        )

        // Assert
        #expect(preinstallResult == .rejected(.compositionDomainNotInstalled(phase: .preinstall)))
        #expect(missingResult == .rejected(.drawerTogglePlanning(.parentPaneMissing(missingPaneID))))
        #expect(fixture.runtime.revisionOwner.committedRevision == .zero)
        #expect(fixture.atomRegistry.workspaceDrawerCursor.expandedDrawerId == nil)
    }

    @Test("expand commits once and excludes its post-base insertion")
    func expandExcludesPostBaseInsertion() throws {
        // Arrange
        let fixture = makeDrawerTogglePersistenceFixture()
        let installed = try installDrawerCursorParticipant(fixture.runtime, openingLease: true)
        defer { _ = installed.participant.close(lease: installed.lease) }

        // Act
        let result = fixture.runtime.mutationCoordinator.toggleDrawer(
            .init(parentPaneID: fixture.firstParent.id)
        )

        // Assert
        #expect(try requireDrawerToggleChangedRevision(result).rawValue == 1)
        #expect(fixture.atomRegistry.workspaceDrawerCursor.expandedDrawerId == fixture.firstDrawerID)
        guard case .exhausted = installed.participant.inspectBaseSlot(lease: installed.lease, slotCursor: 0)
        else {
            Issue.record("expected fixed base to exclude the post-base drawer insertion")
            return
        }
    }

    @Test("collapse commits once and retains the removed fixed-base drawer")
    func collapseRetainsRemovedDrawer() throws {
        // Arrange
        let fixture = makeDrawerTogglePersistenceFixture(expandedDrawerID: .first)
        let installed = try installDrawerCursorParticipant(fixture.runtime, openingLease: true)
        defer { _ = installed.participant.close(lease: installed.lease) }

        // Act
        let result = fixture.runtime.mutationCoordinator.toggleDrawer(
            .init(parentPaneID: fixture.firstParent.id)
        )

        // Assert
        #expect(try requireDrawerToggleChangedRevision(result).rawValue == 1)
        #expect(fixture.atomRegistry.workspaceDrawerCursor.expandedDrawerId == nil)
        try expectRetainedDrawer(fixture.firstDrawerID, installed: installed)
    }

    @Test("switch commits once and retains only the old fixed-base drawer")
    func switchRetainsOldDrawer() throws {
        // Arrange
        let fixture = makeDrawerTogglePersistenceFixture(expandedDrawerID: .first)
        let installed = try installDrawerCursorParticipant(fixture.runtime, openingLease: true)
        defer { _ = installed.participant.close(lease: installed.lease) }

        // Act
        let result = fixture.runtime.mutationCoordinator.toggleDrawer(
            .init(parentPaneID: fixture.secondParent.id)
        )

        // Assert
        #expect(try requireDrawerToggleChangedRevision(result).rawValue == 1)
        #expect(fixture.atomRegistry.workspaceDrawerCursor.expandedDrawerId == fixture.secondDrawerID)
        try expectRetainedDrawer(fixture.firstDrawerID, installed: installed)
        guard case .exhausted = installed.participant.inspectBaseSlot(lease: installed.lease, slotCursor: 1)
        else {
            Issue.record("expected fixed base to exclude the replacement drawer insertion")
            return
        }
    }
}

private enum InitialExpandedDrawer: Equatable {
    case first
}

private struct DrawerTogglePersistenceFixture {
    let atomRegistry: AtomRegistry
    let runtime: WorkspacePersistenceRuntime
    let firstParent: PaneGraphState
    let secondParent: PaneGraphState
    let firstDrawerID: UUID
    let secondDrawerID: UUID
}

private struct InstalledDrawerCursorParticipant {
    let participant: WorkspacePersistenceSnapshotParticipantSet.Participant
    let lease: WorkspaceStateSnapshotLease
}

@MainActor
private func makeDrawerTogglePersistenceFixture(
    expandedDrawerID: InitialExpandedDrawer? = nil
) -> DrawerTogglePersistenceFixture {
    let atomRegistry = AtomRegistry()
    let firstDrawerID = UUIDv7.generate()
    let secondDrawerID = UUIDv7.generate()
    let firstParent = makePersistenceDrawerParent(drawerID: firstDrawerID)
    let secondParent = makePersistenceDrawerParent(drawerID: secondDrawerID)
    atomRegistry.workspacePaneGraph.setCanonicalPaneState(firstParent)
    atomRegistry.workspacePaneGraph.setCanonicalPaneState(secondParent)
    if expandedDrawerID == .first {
        atomRegistry.workspaceDrawerCursor.replaceExpandedDrawer(firstDrawerID)
    }
    return DrawerTogglePersistenceFixture(
        atomRegistry: atomRegistry,
        runtime: WorkspacePersistenceRuntime(atomRegistry: atomRegistry),
        firstParent: firstParent,
        secondParent: secondParent,
        firstDrawerID: firstDrawerID,
        secondDrawerID: secondDrawerID
    )
}

private func makePersistenceDrawerParent(drawerID: UUID) -> PaneGraphState {
    let parentPaneID = UUIDv7.generate()
    return PaneGraphState(
        pane: Pane(
            id: parentPaneID,
            content: .webview(WebviewState(url: URL(string: "https://example.com")!)),
            metadata: PaneMetadata(title: "Drawer parent"),
            kind: .layout(drawer: Drawer(drawerId: drawerID, parentPaneId: parentPaneID))
        )
    )
}

@MainActor
private func installDrawerCursorParticipant(
    _ runtime: WorkspacePersistenceRuntime,
    openingLease: Bool
) throws -> InstalledDrawerCursorParticipant {
    guard
        case .constructed(let participantSet) = runtime.snapshotParticipantFactory
            .constructCompositionParticipantSet(),
        let participant = participantSet.participants.first(where: { $0.participantID == .expandedDrawer })
    else {
        throw WorkspacePersistenceDrawerToggleMutationTestError.installationFailed
    }
    let lease = WorkspaceStateSnapshotLease.open(
        pagerIdentity: .make(),
        revisionOwner: runtime.revisionOwner
    )
    if openingLease {
        let expectedCount = runtime.atomOwners.workspaceDrawerCursor.expandedDrawerId == nil ? 0 : 1
        guard participant.open(lease: lease) == .opened(baseMembershipCount: expectedCount) else {
            throw WorkspacePersistenceDrawerToggleMutationTestError.leaseOpenFailed
        }
    }
    return InstalledDrawerCursorParticipant(participant: participant, lease: lease)
}

@MainActor
private func expectRetainedDrawer(
    _ drawerID: UUID,
    installed: InstalledDrawerCursorParticipant
) throws {
    guard
        case .item(let projectedItem, _, _, _) = installed.participant.inspectBaseSlot(
            lease: installed.lease,
            slotCursor: 0
        )
    else {
        throw WorkspacePersistenceDrawerToggleMutationTestError.baseItemMissing
    }
    #expect(projectedItem.item == .expandedDrawer(drawerID))
}

private func requireDrawerToggleChangedRevision(
    _ result: WorkspacePersistenceMutationResult
) throws -> WorkspacePersistenceRevision {
    guard case .changed(let revision) = result else {
        throw WorkspacePersistenceDrawerToggleMutationTestError.expectedChangedResult
    }
    return revision
}

private enum WorkspacePersistenceDrawerToggleMutationTestError: Error {
    case baseItemMissing
    case expectedChangedResult
    case installationFailed
    case leaseOpenFailed
}
