import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceDrawerCursorPersistenceAdapter")
struct WorkspaceDrawerCursorPersistenceAdapterTests {
    @Test("first post-base replacement retains original drawer membership")
    func firstPostBaseReplacementRetainsOriginalDrawerMembership() throws {
        let originalDrawerID = UUIDv7.generate()
        let replacementDrawerID = UUIDv7.generate()
        let atom = WorkspaceDrawerCursorAtom(expandedDrawerId: originalDrawerID)
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let adapter = WorkspaceDrawerCursorPersistenceAdapter(atom: atom, revisionOwner: revisionOwner)
        let participant = try requireDrawerCursorParticipant(adapter.makePersistenceSnapshotParticipant())
        let lease = WorkspaceStateSnapshotLease.open(pagerIdentity: .make(), revisionOwner: revisionOwner)
        #expect(participant.open(lease: lease) == .opened(baseMembershipCount: 1))

        _ = try revisionOwner.performSynchronousTransactionDecision { preparation in
            try adapter.prepareExpandDrawer(
                drawerId: replacementDrawerID,
                for: preparation
            )
        }

        guard case .item(let typedItem, _, _, _) = participant.inspectBaseSlot(lease: lease, slotCursor: 0)
        else {
            Issue.record("expected retained expanded drawer")
            return
        }
        #expect(typedItem.item == .expandedDrawer(originalDrawerID))
        #expect(atom.expandedDrawerId == replacementDrawerID)
        _ = participant.close(lease: lease)
    }

    @Test("duplicate preparation changes neither atom nor revision")
    func duplicatePreparationChangesNeitherAtomNorRevision() {
        let atom = WorkspaceDrawerCursorAtom()
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let adapter = WorkspaceDrawerCursorPersistenceAdapter(atom: atom, revisionOwner: revisionOwner)
        let firstDrawerID = UUIDv7.generate()
        let secondDrawerID = UUIDv7.generate()
        guard case .constructed = adapter.makePersistenceSnapshotParticipant() else {
            Issue.record("expanded-drawer snapshot participant construction failed")
            return
        }

        #expect(throws: WorkspaceDrawerCursorSnapshotPreparationError.self) {
            try revisionOwner.performSynchronousTransactionDecision { preparation in
                _ = try adapter.prepareExpandDrawer(
                    drawerId: firstDrawerID,
                    for: preparation
                )
                return try adapter.prepareExpandDrawer(
                    drawerId: secondDrawerID,
                    for: preparation
                )
            }
        }

        #expect(revisionOwner.committedRevision == .zero)
        #expect(atom.expandedDrawerId == nil)
    }

    @Test("unchanged expanded drawer mutates nothing and advances no revision")
    func unchangedExpandedDrawerMutatesNothingAndAdvancesNoRevision() throws {
        let drawerID = UUIDv7.generate()
        let atom = WorkspaceDrawerCursorAtom(expandedDrawerId: drawerID)
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let adapter = WorkspaceDrawerCursorPersistenceAdapter(atom: atom, revisionOwner: revisionOwner)

        let revision = try revisionOwner.performSynchronousTransactionDecision { preparation in
            try adapter.prepareExpandDrawer(
                drawerId: drawerID,
                for: preparation
            )
        }

        #expect(revision == .zero)
        #expect(revisionOwner.committedRevision == .zero)
        #expect(atom.expandedDrawerId == drawerID)
    }

    @Test("registered replacement applies through the adapter")
    func registeredReplacementAppliesThroughAdapter() throws {
        let atom = WorkspaceDrawerCursorAtom()
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let bundle = makeDrawerCursorAdapterBundle(atom: atom, revisionOwner: revisionOwner)
        let adapter = bundle.workspaceDrawerCursor
        let drawerID = UUIDv7.generate()

        let access = try bundle.withCompositionPreinstallAccess { token in
            try revisionOwner.performSynchronousTransaction { preparation in
                #expect(
                    adapter.registerInitialExpandedDrawerReplacement(
                        token: token,
                        drawerID,
                        for: preparation
                    ) == .registered
                )
                return preparation.commit { preparation.transaction.proposedRevision }
            }
        }
        guard case .authorized = access else {
            Issue.record("expected preinstall drawer-cursor replacement access")
            return
        }

        #expect(atom.expandedDrawerId == drawerID)
    }
}

@MainActor
private func makeDrawerCursorAdapterBundle(
    atom: WorkspaceDrawerCursorAtom,
    revisionOwner: WorkspacePersistenceRevisionOwner
) -> WorkspacePersistenceAdapterBundle {
    WorkspacePersistenceAdapterBundle(
        revisionOwner: revisionOwner,
        workspaceIdentityAtom: WorkspaceIdentityAtom(),
        workspaceWindowMemoryAtom: WorkspaceWindowMemoryAtom(),
        repositoryTopologyAtom: RepositoryTopologyAtom(),
        workspacePaneGraphAtom: WorkspacePaneGraphAtom(),
        workspaceDrawerCursorAtom: atom,
        workspaceTabShellAtom: WorkspaceTabShellAtom(),
        workspaceTabCursorAtom: WorkspaceTabCursorAtom(),
        workspaceTabGraphAtom: WorkspaceTabGraphAtom(),
        workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom()
    )
}

@MainActor
private func requireDrawerCursorParticipant(
    _ result: SnapshotPagerParticipantConstructionResult<
        WorkspacePersistenceSnapshotParticipantID,
        WorkspacePersistenceSnapshotItem
    >
) throws -> WorkspacePersistenceSnapshotParticipantSet.Participant {
    switch result {
    case .constructed(let participant): participant
    case .rejected(let rejection):
        Issue.record("expected expanded-drawer participant, received \(rejection)")
        throw WorkspaceDrawerCursorSnapshotPreparationError(rejection: .participant(rejection))
    }
}
