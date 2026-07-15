import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceArrangementCursorAtomTests {
    @Test("prepared cursor operations represent absent optional cursors as absent membership")
    func preparedCursorOperationsUseAbsentMembership() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let atom = WorkspaceArrangementCursorAtom()
        let tabID = UUIDv7.generate()
        let arrangementID = UUIDv7.generate()
        let paneID = UUIDv7.generate()
        let drawerKey = ArrangementDrawerCursorKey(
            arrangementId: arrangementID,
            drawerId: UUIDv7.generate()
        )
        _ = try requireConstructedCursorParticipants(
            atom.makePersistenceSnapshotParticipants(limits: cursorMembershipLimits)
        )

        // Act
        try applyCursorOperations(
            WorkspaceArrangementCursorPersistenceOperations(
                activeArrangements: [.set(tabID: tabID, arrangementID: arrangementID)],
                activePanes: [.set(arrangementID: arrangementID, paneID: paneID)],
                activeDrawerChildren: [.set(key: drawerKey, childPaneID: paneID)]
            ),
            to: atom,
            revisionOwner: revisionOwner
        )
        try applyCursorOperations(
            WorkspaceArrangementCursorPersistenceOperations(
                activeArrangements: [],
                activePanes: [.clearSelection(arrangementID: arrangementID)],
                activeDrawerChildren: [.clearSelection(key: drawerKey)]
            ),
            to: atom,
            revisionOwner: revisionOwner
        )

        // Assert
        #expect(atom.activeArrangementId(forTab: tabID) == arrangementID)
        #expect(atom.activePaneId(forArrangement: arrangementID) == nil)
        #expect(atom.activeChildId(forArrangement: arrangementID, drawerId: drawerKey.drawerId) == nil)
        #expect(atom.paneCursorsByArrangementId.keys.contains(arrangementID))
        #expect(atom.drawerCursorsByKey.keys.contains(drawerKey))
        #expect(revisionOwner.committedRevision.rawValue == 2)
    }

    @Test("active lease retains selected cursor values across canonical clear and removal")
    func activeLeaseRetainsSelectedCursorValuesAcrossClearAndRemoval() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let atom = WorkspaceArrangementCursorAtom()
        let tabID = UUIDv7.generate()
        let arrangementID = UUIDv7.generate()
        let paneID = UUIDv7.generate()
        let drawerKey = ArrangementDrawerCursorKey(
            arrangementId: arrangementID,
            drawerId: UUIDv7.generate()
        )
        let participants = try requireConstructedCursorParticipants(
            atom.makePersistenceSnapshotParticipants(limits: cursorMembershipLimits)
        )
        try applyCursorOperations(
            WorkspaceArrangementCursorPersistenceOperations(
                activeArrangements: [.set(tabID: tabID, arrangementID: arrangementID)],
                activePanes: [.set(arrangementID: arrangementID, paneID: paneID)],
                activeDrawerChildren: [.set(key: drawerKey, childPaneID: paneID)]
            ),
            to: atom,
            revisionOwner: revisionOwner
        )
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        #expect(
            participants.activeArrangements.open(lease: lease, limits: cursorMembershipLimits)
                == .opened(baseMembershipCount: 1))
        #expect(
            participants.activePanes.open(lease: lease, limits: cursorMembershipLimits)
                == .opened(baseMembershipCount: 1))
        #expect(
            participants.activeDrawerChildren.open(lease: lease, limits: cursorMembershipLimits)
                == .opened(baseMembershipCount: 1))

        // Act
        try applyCursorOperations(
            WorkspaceArrangementCursorPersistenceOperations(
                activeArrangements: [.remove(tabID: tabID)],
                activePanes: [.clearSelection(arrangementID: arrangementID)],
                activeDrawerChildren: [.removeCursor(key: drawerKey)]
            ),
            to: atom,
            revisionOwner: revisionOwner
        )
        let arrangementInspection = participants.activeArrangements.inspectBaseSlot(
            lease: lease,
            slotCursor: 0
        )
        let paneInspection = participants.activePanes.inspectBaseSlot(lease: lease, slotCursor: 0)
        let drawerInspection = participants.activeDrawerChildren.inspectBaseSlot(lease: lease, slotCursor: 0)

        // Assert
        #expect(atom.activeArrangementId(forTab: tabID) == nil)
        #expect(atom.activePaneId(forArrangement: arrangementID) == nil)
        #expect(atom.paneCursorsByArrangementId.keys.contains(arrangementID))
        #expect(!atom.drawerCursorsByKey.keys.contains(drawerKey))
        guard
            case .item(let arrangementItem, _, _, _) = arrangementInspection,
            case .item(let paneItem, _, _, _) = paneInspection,
            case .item(let drawerItem, _, _, _) = drawerInspection
        else {
            Issue.record("expected all cursor participants to retain their selected base values")
            return
        }
        #expect(arrangementItem.item == .activeArrangement(tabID: tabID, arrangementID: arrangementID))
        #expect(paneItem.item == .activePane(arrangementID: arrangementID, paneID: paneID))
        #expect(drawerItem.item == .activeDrawerChild(key: drawerKey, childPaneID: paneID))
    }
}

@MainActor
private func applyCursorOperations(
    _ operations: WorkspaceArrangementCursorPersistenceOperations,
    to atom: WorkspaceArrangementCursorAtom,
    revisionOwner: WorkspacePersistenceRevisionOwner
) throws {
    try revisionOwner.performSynchronousTransaction { preparation in
        try atom.preparePersistenceMutation(
            operations,
            for: preparation,
            revisionOwner: revisionOwner
        )
        return preparation.commit {}
    }
}

private let cursorMembershipLimits = WorkspaceStateSnapshotMembershipLimits(
    maximumKeyCount: 512,
    maximumRawKeyBytes: 512 * 32
)

@MainActor
private func requireConstructedCursorParticipants(
    _ result: ArrangementCursorParticipantsResult
) throws -> WorkspaceArrangementCursorSnapshotParticipants {
    switch result {
    case .constructed(let participants): participants
    case .rejected(let rejection):
        Issue.record("expected cursor participants, received \(rejection)")
        throw ArrangementCursorPreparationError.snapshotParticipant(rejection)
    }
}
