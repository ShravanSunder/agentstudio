import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace persistence capture-only adapters")
struct WorkspacePersistenceCaptureOnlyAdapterTests {
    @Test("pane capture preserves canonical state until one outer facade-style commit")
    func paneCapturePreservesCanonicalStateAndFixedLease() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let atom = WorkspacePaneGraphAtom()
        let adapter = WorkspacePaneGraphPersistenceAdapter(atom: atom, revisionOwner: revisionOwner)
        let changedBase = makeCapturePaneState(title: "Changed base")
        let removedBase = makeCapturePaneState(title: "Removed base")
        let inserted = makeCapturePaneState(title: "Inserted after base")
        atom.setCanonicalPaneState(changedBase)
        atom.setCanonicalPaneState(removedBase)
        let canonicalBeforeCapture = atom.paneStates
        let participant = try requireCaptureParticipant(
            adapter.makeSnapshotParticipant(
                membershipLimits: .init(maximumKeyCount: 32, maximumRawKeyBytes: 512),
                estimatedByteCount: { _ in 1 }
            )
        )
        let lease = WorkspaceStateSnapshotLease.open(pagerIdentity: .make(), revisionOwner: revisionOwner)
        #expect(participant.open(lease: lease) == .opened(baseMembershipCount: 2))
        var changedCurrent = changedBase
        changedCurrent.metadata.title = "Current"

        // Act
        try revisionOwner.performSynchronousTransaction { preparation in
            try adapter.capturePersistencePreimages(
                .init(
                    operations: [
                        .valueChange(changedBase.id),
                        .removal(removedBase.id),
                        .insertion(inserted.id),
                    ]
                ),
                for: preparation
            )
            #expect(atom.paneStates == canonicalBeforeCapture)
            return preparation.commit {
                atom.setCanonicalPaneState(changedCurrent)
                atom.removeCanonicalPaneState(for: removedBase.id)
                atom.setCanonicalPaneState(inserted)
            }
        }

        // Assert
        #expect(revisionOwner.committedRevision.rawValue == 1)
        #expect(atom.paneState(changedBase.id) == changedCurrent)
        #expect(atom.paneState(removedBase.id) == nil)
        #expect(atom.paneState(inserted.id) == inserted)
        let fixedBaseStates = (0..<2).compactMap { slotIndex -> PaneGraphState? in
            guard
                case .item(let projectedItem, _, _, _) = participant.inspectBaseSlot(
                    lease: lease,
                    slotCursor: slotIndex
                ), case .paneGraph(let paneState) = projectedItem.item
            else { return nil }
            return paneState
        }
        #expect(Set(fixedBaseStates) == Set([changedBase, removedBase]))
        guard case .exhausted = participant.inspectBaseSlot(lease: lease, slotCursor: 2) else {
            Issue.record("expected post-base pane insertion to remain outside the fixed lease")
            return
        }
    }

    @Test("conflicting pane capture rejects without revision or canonical mutation")
    func conflictingPaneCaptureRejectsWithoutMutation() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let atom = WorkspacePaneGraphAtom()
        let adapter = WorkspacePaneGraphPersistenceAdapter(atom: atom, revisionOwner: revisionOwner)
        let paneState = makeCapturePaneState(title: "Unchanged")
        atom.setCanonicalPaneState(paneState)
        let canonicalBeforeCapture = atom.paneStates

        // Act
        var capturedError: WorkspacePaneGraphPersistenceCaptureError?
        do {
            _ = try revisionOwner.performSynchronousTransaction { preparation in
                try adapter.capturePersistencePreimages(
                    .init(operations: [.valueChange(paneState.id), .removal(paneState.id)]),
                    for: preparation
                )
                return preparation.commit {
                    Issue.record("rejected capture must not reach its commit body")
                }
            }
        } catch let error as WorkspacePaneGraphPersistenceCaptureError {
            capturedError = error
        }

        // Assert
        #expect(capturedError == .duplicateOrConflictingPaneID(paneState.id))
        #expect(revisionOwner.committedRevision == .zero)
        #expect(atom.paneStates == canonicalBeforeCapture)
    }

    @Test("identity and window captures share one revision and retain literal preimages")
    func scalarAdaptersShareOneOuterTransaction() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let identityAtom = WorkspaceIdentityAtom()
        let windowAtom = WorkspaceWindowMemoryAtom()
        let identityAdapter = WorkspaceIdentityPersistenceAdapter(atom: identityAtom, revisionOwner: revisionOwner)
        let windowAdapter = WorkspaceWindowMemoryPersistenceAdapter(atom: windowAtom, revisionOwner: revisionOwner)
        let identityBeforeCapture = WorkspacePersistenceSnapshotWorkspaceIdentity(
            workspaceID: identityAtom.workspaceId,
            workspaceName: identityAtom.workspaceName,
            createdAt: identityAtom.createdAt
        )
        let windowBeforeCapture = WorkspacePersistenceSnapshotWindowMemory(
            sidebarWidth: windowAtom.sidebarWidth,
            windowFrame: windowAtom.windowFrame
        )
        let identityParticipant = try requireCaptureParticipant(identityAdapter.makePersistenceSnapshotParticipant())
        let windowParticipant = try requireCaptureParticipant(windowAdapter.makePersistenceSnapshotParticipant())
        let lease = WorkspaceStateSnapshotLease.open(pagerIdentity: .make(), revisionOwner: revisionOwner)
        #expect(identityParticipant.open(lease: lease) == .opened(baseMembershipCount: 1))
        #expect(windowParticipant.open(lease: lease) == .opened(baseMembershipCount: 1))

        // Act
        try revisionOwner.performSynchronousTransaction { preparation in
            try identityAdapter.capturePersistencePreimage(.currentIdentity, for: preparation)
            try windowAdapter.capturePersistencePreimage(.currentWindowMemory, for: preparation)
            #expect(identityAtom.workspaceName == identityBeforeCapture.workspaceName)
            #expect(windowAtom.sidebarWidth == windowBeforeCapture.sidebarWidth)
            return preparation.commit {
                identityAtom.setWorkspaceName("Captured once")
                windowAtom.setSidebarWidth(windowBeforeCapture.sidebarWidth + 40)
            }
        }

        // Assert
        #expect(revisionOwner.committedRevision.rawValue == 1)
        guard
            case .item(let identityItem, _, _, _) = identityParticipant.inspectBaseSlot(
                lease: lease,
                slotCursor: 0
            ), case .workspaceIdentity(let retainedIdentity) = identityItem.item,
            case .item(let windowItem, _, _, _) = windowParticipant.inspectBaseSlot(
                lease: lease,
                slotCursor: 0
            ), case .windowMemory(let retainedWindow) = windowItem.item
        else {
            Issue.record("expected both scalar participants to retain their literal base values")
            return
        }
        #expect(retainedIdentity == identityBeforeCapture)
        #expect(retainedWindow == windowBeforeCapture)
    }

    @Test("arrangement capture maps reservation rejection and releases earlier custody")
    func arrangementCaptureMapsRejectionAndReleasesCustody() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let atom = WorkspaceArrangementCursorAtom()
        let adapter = WorkspaceArrangementCursorPersistenceAdapter(
            atom: atom,
            revisionOwner: revisionOwner
        )
        guard
            case .constructed = adapter.makeSnapshotParticipants(
                limits: .init(maximumKeyCount: 32, maximumRawKeyBytes: 512)
            )
        else {
            Issue.record("expected arrangement snapshot participants to construct")
            return
        }
        let firstTabID = UUIDv7.generate()
        let secondTabID = UUIDv7.generate()
        let arrangementID = UUIDv7.generate()

        // Act
        var capturedError: WorkspaceArrangementCursorPersistenceCaptureError?
        do {
            _ = try revisionOwner.performSynchronousTransaction { preparation in
                try adapter.capturePersistencePreimages(
                    .init(
                        activeArrangements: [.insertion(tabID: firstTabID)],
                        activePanes: [],
                        activeDrawerChildren: []
                    ),
                    for: preparation
                )
                try adapter.capturePersistencePreimages(
                    .init(
                        activeArrangements: [.insertion(tabID: secondTabID)],
                        activePanes: [],
                        activeDrawerChildren: []
                    ),
                    for: preparation
                )
                return preparation.commit {
                    Issue.record("rejected arrangement capture must not reach its commit body")
                }
            }
        } catch let error as WorkspaceArrangementCursorPersistenceCaptureError {
            capturedError = error
        }

        let retryRevision = try revisionOwner.performSynchronousTransaction { preparation in
            try adapter.capturePersistencePreimages(
                .init(
                    activeArrangements: [.insertion(tabID: firstTabID)],
                    activePanes: [],
                    activeDrawerChildren: []
                ),
                for: preparation
            )
            return preparation.commit {
                atom.insertActiveArrangementId(arrangementID, forTab: firstTabID)
                return preparation.transaction.proposedRevision
            }
        }

        // Assert
        #expect(
            capturedError
                == .snapshotPreparation(
                    .participant(.participantReserved)
                )
        )
        #expect(retryRevision.rawValue == 1)
        #expect(revisionOwner.committedRevision == retryRevision)
        #expect(atom.activeArrangementId(forTab: firstTabID) == arrangementID)
        #expect(atom.activeArrangementId(forTab: secondTabID) == nil)
    }
}

@MainActor
private func requireCaptureParticipant(
    _ result: SnapshotPagerParticipantConstructionResult<
        WorkspacePersistenceSnapshotParticipantID,
        WorkspacePersistenceSnapshotItem
    >
) throws -> WorkspaceStateSnapshotPagerParticipant<
    WorkspacePersistenceSnapshotParticipantID,
    WorkspacePersistenceSnapshotItem
> {
    switch result {
    case .constructed(let participant): participant
    case .rejected(let rejection): throw CaptureOnlyAdapterTestError.participantConstruction(rejection)
    }
}

private enum CaptureOnlyAdapterTestError: Error {
    case participantConstruction(WorkspaceStateSnapshotParticipantRejection)
}

private func makeCapturePaneState(title: String) -> PaneGraphState {
    PaneGraphState(
        pane: Pane(
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(title: title)
        )
    )
}
