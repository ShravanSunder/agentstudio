import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceIdentityPersistenceAdapter")
struct WorkspaceIdentityPersistenceAdapterTests {
    @Test("first post-base replacement retains the original identity")
    func firstPostBaseReplacementRetainsOriginalIdentity() throws {
        let originalID = UUIDv7.generate()
        let originalDate = Date(timeIntervalSince1970: 1_714_000_000)
        let atom = WorkspaceIdentityAtom(
            workspaceId: originalID,
            workspaceName: "Original",
            createdAt: originalDate
        )
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let adapter = WorkspaceIdentityPersistenceAdapter(atom: atom, revisionOwner: revisionOwner)
        let participant = try requireIdentityParticipant(adapter.makePersistenceSnapshotParticipant())
        let lease = WorkspaceStateSnapshotLease.open(pagerIdentity: .make(), revisionOwner: revisionOwner)
        #expect(participant.open(lease: lease) == .opened(baseMembershipCount: 1))

        _ = try revisionOwner.performSynchronousTransactionDecision { preparation in
            try adapter.prepareSetWorkspaceName(
                "First replacement",
                for: preparation
            )
        }
        _ = try revisionOwner.performSynchronousTransactionDecision { preparation in
            try adapter.prepareSetWorkspaceName(
                "Second replacement",
                for: preparation
            )
        }

        guard case .item(let typedItem, _, _, _) = participant.inspectBaseSlot(lease: lease, slotCursor: 0)
        else {
            Issue.record("expected retained workspace identity")
            return
        }
        #expect(
            typedItem.item
                == .workspaceIdentity(
                    .init(
                        workspaceID: originalID,
                        workspaceName: "Original",
                        createdAt: originalDate
                    )
                )
        )
        _ = participant.close(lease: lease)
    }

    @Test("duplicate preparation changes neither atom nor revision")
    func duplicatePreparationChangesNeitherAtomNorRevision() {
        let atom = WorkspaceIdentityAtom(workspaceId: UUIDv7.generate())
        let originalName = atom.workspaceName
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let adapter = WorkspaceIdentityPersistenceAdapter(atom: atom, revisionOwner: revisionOwner)
        guard case .constructed = adapter.makePersistenceSnapshotParticipant() else {
            Issue.record("identity snapshot participant construction failed")
            return
        }

        #expect(throws: WorkspaceIdentitySnapshotPreparationError.self) {
            try revisionOwner.performSynchronousTransactionDecision { preparation in
                _ = try adapter.prepareSetWorkspaceName(
                    "First",
                    for: preparation
                )
                return try adapter.prepareSetWorkspaceName(
                    "Rejected",
                    for: preparation
                )
            }
        }

        #expect(revisionOwner.committedRevision == .zero)
        #expect(atom.workspaceName == originalName)
    }

    @Test("unchanged workspace name mutates nothing and advances no revision")
    func unchangedWorkspaceNameMutatesNothingAndAdvancesNoRevision() throws {
        let atom = WorkspaceIdentityAtom(
            workspaceId: UUIDv7.generate(),
            workspaceName: "Unchanged"
        )
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let adapter = WorkspaceIdentityPersistenceAdapter(atom: atom, revisionOwner: revisionOwner)

        let revision = try revisionOwner.performSynchronousTransactionDecision { preparation in
            try adapter.prepareSetWorkspaceName(
                "Unchanged",
                for: preparation
            )
        }

        #expect(revision == .zero)
        #expect(revisionOwner.committedRevision == .zero)
        #expect(atom.workspaceName == "Unchanged")
    }

    @Test("registered replacement applies through the adapter")
    func registeredReplacementAppliesThroughAdapter() throws {
        let atom = WorkspaceIdentityAtom(workspaceId: UUIDv7.generate())
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let bundle = makeIdentityAdapterBundle(atom: atom, revisionOwner: revisionOwner)
        let adapter = bundle.workspaceIdentity
        let replacementID = UUIDv7.generate()
        let replacementDate = Date(timeIntervalSince1970: 1_720_000_000)

        let access = try bundle.withCompositionPreinstallAccess { token in
            try revisionOwner.performSynchronousTransaction { preparation in
                #expect(
                    adapter.registerInitialIdentityReplacement(
                        token: token,
                        workspaceId: replacementID,
                        workspaceName: "Prepared",
                        createdAt: replacementDate,
                        for: preparation
                    ) == .registered
                )
                return preparation.commit { preparation.transaction.proposedRevision }
            }
        }
        guard case .authorized(let revision) = access else {
            Issue.record("expected preinstall identity replacement access")
            return
        }

        #expect(revision == revisionOwner.committedRevision)
        #expect(atom.workspaceId == replacementID)
        #expect(atom.workspaceName == "Prepared")
        #expect(atom.createdAt == replacementDate)
    }

    @Test("bound adapter rejects a transaction preparation from a foreign revision owner")
    func boundAdapterRejectsForeignRevisionOwnerPreparation() {
        let atom = WorkspaceIdentityAtom(
            workspaceId: UUIDv7.generate(),
            workspaceName: "Original"
        )
        let boundRevisionOwner = WorkspacePersistenceRevisionOwner()
        let foreignRevisionOwner = WorkspacePersistenceRevisionOwner()
        let adapter = WorkspaceIdentityPersistenceAdapter(atom: atom, revisionOwner: boundRevisionOwner)
        guard case .constructed = adapter.makePersistenceSnapshotParticipant() else {
            Issue.record("identity snapshot participant construction failed")
            return
        }

        #expect(throws: WorkspaceIdentitySnapshotPreparationError.self) {
            try foreignRevisionOwner.performSynchronousTransactionDecision { preparation in
                try adapter.prepareSetWorkspaceName("Foreign", for: preparation)
            }
        }

        #expect(boundRevisionOwner.committedRevision == .zero)
        #expect(foreignRevisionOwner.committedRevision == .zero)
        #expect(atom.workspaceName == "Original")
    }
}

@MainActor
private func makeIdentityAdapterBundle(
    atom: WorkspaceIdentityAtom,
    revisionOwner: WorkspacePersistenceRevisionOwner
) -> WorkspacePersistenceAdapterBundle {
    WorkspacePersistenceAdapterBundle(
        revisionOwner: revisionOwner,
        workspaceIdentityAtom: atom,
        workspaceWindowMemoryAtom: WorkspaceWindowMemoryAtom(),
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
private func requireIdentityParticipant(
    _ result: SnapshotPagerParticipantConstructionResult<
        WorkspacePersistenceSnapshotParticipantID,
        WorkspacePersistenceSnapshotItem
    >
) throws -> WorkspacePersistenceSnapshotParticipantSet.Participant {
    switch result {
    case .constructed(let participant): participant
    case .rejected(let rejection):
        Issue.record("expected identity participant, received \(rejection)")
        throw WorkspaceIdentitySnapshotPreparationError(rejection: .participant(rejection))
    }
}
