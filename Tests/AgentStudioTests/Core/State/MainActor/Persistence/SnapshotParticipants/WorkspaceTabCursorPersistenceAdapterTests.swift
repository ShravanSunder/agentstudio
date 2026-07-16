import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceTabCursorPersistenceAdapter")
struct WorkspaceTabCursorPersistenceAdapterTests {
    @Test("first post-base replacement retains original active tab")
    func firstPostBaseReplacementRetainsOriginalActiveTab() throws {
        let originalTabID = UUIDv7.generate()
        let replacementTabID = UUIDv7.generate()
        let atom = WorkspaceTabCursorAtom(activeTabId: originalTabID)
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let adapter = WorkspaceTabCursorPersistenceAdapter(atom: atom, revisionOwner: revisionOwner)
        let participant = try requireTabCursorParticipant(adapter.makePersistenceSnapshotParticipant())
        let lease = WorkspaceStateSnapshotLease.open(pagerIdentity: .make(), revisionOwner: revisionOwner)
        #expect(participant.open(lease: lease) == .opened(baseMembershipCount: 1))

        _ = try revisionOwner.performSynchronousTransactionDecision { preparation in
            try adapter.prepareSelectTab(
                replacementTabID,
                availableTabIds: [originalTabID, replacementTabID],
                for: preparation
            )
        }

        guard case .item(let typedItem, _, _, _) = participant.inspectBaseSlot(lease: lease, slotCursor: 0)
        else {
            Issue.record("expected retained active tab")
            return
        }
        #expect(typedItem.item == .activeTab(originalTabID))
        #expect(atom.activeTabId == replacementTabID)
        _ = participant.close(lease: lease)
    }

    @Test("hydration fallback and duplicate rejection stay in the adapter")
    func hydrationFallbackAndDuplicateRejectionStayInAdapter() {
        let atom = WorkspaceTabCursorAtom()
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let adapter = WorkspaceTabCursorPersistenceAdapter(atom: atom, revisionOwner: revisionOwner)
        let fallbackTabID = UUIDv7.generate()
        let secondTabID = UUIDv7.generate()
        guard case .constructed = adapter.makePersistenceSnapshotParticipant() else {
            Issue.record("active-tab snapshot participant construction failed")
            return
        }

        #expect(throws: WorkspaceTabCursorSnapshotPreparationError.self) {
            try revisionOwner.performSynchronousTransactionDecision { preparation in
                _ = try adapter.prepareHydrate(
                    activeTabId: UUIDv7.generate(),
                    availableTabIds: [fallbackTabID],
                    for: preparation
                )
                return try adapter.prepareSelectTab(
                    secondTabID,
                    availableTabIds: [fallbackTabID, secondTabID],
                    for: preparation
                )
            }
        }

        #expect(revisionOwner.committedRevision == .zero)
        #expect(atom.activeTabId == nil)
    }

    @Test("unchanged active tab mutates nothing and advances no revision")
    func unchangedActiveTabMutatesNothingAndAdvancesNoRevision() throws {
        let tabID = UUIDv7.generate()
        let atom = WorkspaceTabCursorAtom(activeTabId: tabID)
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let adapter = WorkspaceTabCursorPersistenceAdapter(atom: atom, revisionOwner: revisionOwner)

        let revision = try revisionOwner.performSynchronousTransactionDecision { preparation in
            try adapter.prepareSelectTab(
                tabID,
                availableTabIds: [tabID],
                for: preparation
            )
        }

        #expect(revision == .zero)
        #expect(revisionOwner.committedRevision == .zero)
        #expect(atom.activeTabId == tabID)
    }

    @Test("registered replacement normalizes stale selection before commit")
    func registeredReplacementNormalizesStaleSelectionBeforeCommit() throws {
        let atom = WorkspaceTabCursorAtom()
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let bundle = makeTabCursorAdapterBundle(atom: atom, revisionOwner: revisionOwner)
        let adapter = bundle.workspaceTabCursor
        let availableTabID = UUIDv7.generate()

        let access = try bundle.withCompositionPreinstallAccess { token in
            try revisionOwner.performSynchronousTransaction { preparation in
                #expect(
                    adapter.registerInitialActiveTabReplacement(
                        token: token,
                        UUIDv7.generate(),
                        availableTabIds: [availableTabID],
                        for: preparation
                    ) == .registered
                )
                return preparation.commit { preparation.transaction.proposedRevision }
            }
        }
        guard case .authorized = access else {
            Issue.record("expected preinstall tab-cursor replacement access")
            return
        }

        #expect(atom.activeTabId == availableTabID)
    }
}

@MainActor
private func makeTabCursorAdapterBundle(
    atom: WorkspaceTabCursorAtom,
    revisionOwner: WorkspacePersistenceRevisionOwner
) -> WorkspacePersistenceAdapterBundle {
    WorkspacePersistenceAdapterBundle(
        revisionOwner: revisionOwner,
        workspaceIdentityAtom: WorkspaceIdentityAtom(),
        workspaceWindowMemoryAtom: WorkspaceWindowMemoryAtom(),
        repositoryTopologyAtom: RepositoryTopologyAtom(),
        workspacePaneGraphAtom: WorkspacePaneGraphAtom(),
        workspaceDrawerCursorAtom: WorkspaceDrawerCursorAtom(),
        workspaceTabShellAtom: WorkspaceTabShellAtom(),
        workspaceTabCursorAtom: atom,
        workspaceTabGraphAtom: WorkspaceTabGraphAtom(),
        workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom()
    )
}

@MainActor
private func requireTabCursorParticipant(
    _ result: SnapshotPagerParticipantConstructionResult<
        WorkspacePersistenceSnapshotParticipantID,
        WorkspacePersistenceSnapshotItem
    >
) throws -> WorkspacePersistenceSnapshotParticipantSet.Participant {
    switch result {
    case .constructed(let participant): participant
    case .rejected(let rejection):
        Issue.record("expected active-tab participant, received \(rejection)")
        throw WorkspaceTabCursorSnapshotPreparationError(rejection: .participant(rejection))
    }
}
