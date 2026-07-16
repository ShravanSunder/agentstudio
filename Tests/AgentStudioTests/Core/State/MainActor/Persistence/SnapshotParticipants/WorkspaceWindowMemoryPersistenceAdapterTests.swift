import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceWindowMemoryPersistenceAdapter")
struct WorkspaceWindowMemoryPersistenceAdapterTests {
    @Test("first post-base replacement retains original window memory")
    func firstPostBaseReplacementRetainsOriginalWindowMemory() throws {
        let originalFrame = CGRect(x: 1, y: 2, width: 900, height: 700)
        let atom = WorkspaceWindowMemoryAtom(sidebarWidth: 280, windowFrame: originalFrame)
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let adapter = WorkspaceWindowMemoryPersistenceAdapter(atom: atom, revisionOwner: revisionOwner)
        let participant = try requireWindowMemoryParticipant(adapter.makePersistenceSnapshotParticipant())
        let lease = WorkspaceStateSnapshotLease.open(pagerIdentity: .make(), revisionOwner: revisionOwner)
        #expect(participant.open(lease: lease) == .opened(baseMembershipCount: 1))

        _ = try revisionOwner.performSynchronousTransactionDecision { preparation in
            try adapter.prepareSetSidebarWidth(
                333,
                for: preparation
            )
        }

        guard case .item(let typedItem, _, _, _) = participant.inspectBaseSlot(lease: lease, slotCursor: 0)
        else {
            Issue.record("expected retained window memory")
            return
        }
        #expect(
            typedItem.item
                == .windowMemory(.init(sidebarWidth: 280, windowFrame: originalFrame))
        )
        _ = participant.close(lease: lease)
    }

    @Test("duplicate preparation changes neither atom nor revision")
    func duplicatePreparationChangesNeitherAtomNorRevision() {
        let atom = WorkspaceWindowMemoryAtom()
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let adapter = WorkspaceWindowMemoryPersistenceAdapter(atom: atom, revisionOwner: revisionOwner)
        guard case .constructed = adapter.makePersistenceSnapshotParticipant() else {
            Issue.record("window-memory snapshot participant construction failed")
            return
        }

        #expect(throws: WorkspaceWindowMemorySnapshotPreparationError.self) {
            try revisionOwner.performSynchronousTransactionDecision { preparation in
                _ = try adapter.prepareSetSidebarWidth(
                    300,
                    for: preparation
                )
                return try adapter.prepareSetWindowFrame(
                    CGRect(x: 1, y: 2, width: 3, height: 4),
                    for: preparation
                )
            }
        }

        #expect(revisionOwner.committedRevision == .zero)
        #expect(atom.sidebarWidth == 250)
        #expect(atom.windowFrame == nil)
    }

    @Test("unchanged window memory mutates nothing and advances no revision")
    func unchangedWindowMemoryMutatesNothingAndAdvancesNoRevision() throws {
        let frame = CGRect(x: 1, y: 2, width: 800, height: 600)
        let atom = WorkspaceWindowMemoryAtom(sidebarWidth: 333, windowFrame: frame)
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let adapter = WorkspaceWindowMemoryPersistenceAdapter(atom: atom, revisionOwner: revisionOwner)

        let revision = try revisionOwner.performSynchronousTransactionDecision { preparation in
            try adapter.prepareHydrate(
                sidebarWidth: 333,
                windowFrame: frame,
                for: preparation
            )
        }

        #expect(revision == .zero)
        #expect(revisionOwner.committedRevision == .zero)
        #expect(atom.sidebarWidth == 333)
        #expect(atom.windowFrame == frame)
    }

    @Test("registered replacement applies through the adapter")
    func registeredReplacementAppliesThroughAdapter() throws {
        let atom = WorkspaceWindowMemoryAtom()
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let bundle = makeWindowMemoryAdapterBundle(atom: atom, revisionOwner: revisionOwner)
        let adapter = bundle.workspaceWindowMemory
        let frame = CGRect(x: 8, y: 13, width: 987, height: 654)

        let access = try bundle.withCompositionPreinstallAccess { token in
            try revisionOwner.performSynchronousTransaction { preparation in
                #expect(
                    adapter.registerInitialWindowMemoryReplacement(
                        token: token,
                        sidebarWidth: 333,
                        windowFrame: frame,
                        for: preparation
                    ) == .registered
                )
                return preparation.commit { preparation.transaction.proposedRevision }
            }
        }
        guard case .authorized = access else {
            Issue.record("expected preinstall window-memory replacement access")
            return
        }

        #expect(atom.sidebarWidth == 333)
        #expect(atom.windowFrame == frame)
    }
}

@MainActor
private func makeWindowMemoryAdapterBundle(
    atom: WorkspaceWindowMemoryAtom,
    revisionOwner: WorkspacePersistenceRevisionOwner
) -> WorkspacePersistenceAdapterBundle {
    WorkspacePersistenceAdapterBundle(
        revisionOwner: revisionOwner,
        workspaceIdentityAtom: WorkspaceIdentityAtom(),
        workspaceWindowMemoryAtom: atom,
        repositoryTopologyAtom: RepositoryTopologyAtom(),
        workspacePaneGraphAtom: WorkspacePaneGraphAtom(),
        workspaceDrawerCursorAtom: WorkspaceDrawerCursorAtom(),
        workspaceTabShellAtom: WorkspaceTabShellAtom(),
        workspaceTabCursorAtom: WorkspaceTabCursorAtom(),
        workspaceTabGraphAtom: WorkspaceTabGraphAtom(),
        workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom()
    )
}

@MainActor
private func requireWindowMemoryParticipant(
    _ result: SnapshotPagerParticipantConstructionResult<
        WorkspacePersistenceSnapshotParticipantID,
        WorkspacePersistenceSnapshotItem
    >
) throws -> WorkspacePersistenceSnapshotParticipantSet.Participant {
    switch result {
    case .constructed(let participant): participant
    case .rejected(let rejection):
        Issue.record("expected window-memory participant, received \(rejection)")
        throw WorkspaceWindowMemorySnapshotPreparationError(rejection: .participant(rejection))
    }
}
