import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace pane graph persistence adapter")
struct WorkspacePaneGraphPersistenceAdapterTests {
    private let membershipLimits = WorkspaceStateSnapshotMembershipLimits(
        maximumKeyCount: 20_000,
        maximumRawKeyBytes: 320_000
    )

    @Test("prepared insert update and remove keep canonical state and participant membership aligned")
    func preparedInsertUpdateAndRemoveStayAligned() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let atom = WorkspacePaneGraphAtom()
        let adapter = WorkspacePaneGraphPersistenceAdapter(atom: atom, revisionOwner: revisionOwner)
        let original = makePaneGraphState(title: "Original")
        let insertedAlongsideUpdate = makePaneGraphState(title: "Inserted alongside update")
        let participant = requireParticipant(
            adapter.makeSnapshotParticipant(
                membershipLimits: membershipLimits,
                estimatedByteCount: { _ in 1 }
            ))

        // Act
        try performMutation(.insert(original), adapter: adapter, revisionOwner: revisionOwner)
        var updated = original
        updated.metadata.title = "Updated"
        try performMutation(
            .init(operations: [.update(updated), .insert(insertedAlongsideUpdate)]),
            adapter: adapter,
            revisionOwner: revisionOwner
        )
        try performMutation(
            .init(operations: [.remove(original.id), .remove(insertedAlongsideUpdate.id)]),
            adapter: adapter,
            revisionOwner: revisionOwner
        )
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )

        // Assert
        #expect(atom.paneState(original.id) == nil)
        #expect(atom.paneState(insertedAlongsideUpdate.id) == nil)
        #expect(participant.open(lease: lease) == .opened(baseMembershipCount: 0))
        #expect(participant.slotUpperBound(for: lease) == .upperBound(2))
    }

    @Test("active lease retains the fixed base pane across a prepared update")
    func activeLeaseRetainsFixedBaseAcrossUpdate() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let atom = WorkspacePaneGraphAtom()
        let adapter = WorkspacePaneGraphPersistenceAdapter(atom: atom, revisionOwner: revisionOwner)
        let original = makePaneGraphState(title: "Fixed base")
        atom.addPane(original.pane(isDrawerExpanded: false))
        let participant = requireParticipant(
            adapter.makeSnapshotParticipant(
                membershipLimits: membershipLimits,
                estimatedByteCount: { _ in 1 }
            ))
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        #expect(participant.open(lease: lease) == .opened(baseMembershipCount: 1))
        var updated = original
        updated.metadata.title = "Current"

        // Act
        try performMutation(.update(updated), adapter: adapter, revisionOwner: revisionOwner)
        let inspection = participant.inspectBaseSlot(lease: lease, slotCursor: 0)

        // Assert
        #expect(atom.paneState(original.id)?.metadata.title == "Current")
        guard case .item(let projectedItem, let expectedItemID, _, _) = inspection else {
            Issue.record("expected retained pane graph item")
            return
        }
        #expect(expectedItemID == .paneGraph(original.id))
        #expect(projectedItem.item == WorkspacePersistenceSnapshotItem.paneGraph(original))
    }

    @Test("initial pane replacement installs only during its registered revision commit")
    func initialReplacementInstallsAtCommit() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let atom = WorkspacePaneGraphAtom()
        let bundle = makePaneGraphAdapterBundle(atom: atom, revisionOwner: revisionOwner)
        let adapter = bundle.workspacePaneGraph
        let replacementState = makePaneGraphState(title: "Replacement")
        let replacement = try requireReplacement([replacementState.id: replacementState])

        // Act
        let access = try bundle.withCompositionPreinstallAccess { token in
            try revisionOwner.performSynchronousTransaction { preparation in
                #expect(
                    adapter.registerInitialReplacement(
                        token: token,
                        replacement,
                        for: preparation
                    ) == .registered
                )
                #expect(atom.paneState(replacementState.id) == nil)
                return preparation.commit {}
            }
        }
        guard case .authorized = access else {
            Issue.record("expected preinstall pane-graph replacement access")
            return
        }

        // Assert
        #expect(atom.paneState(replacementState.id) == replacementState)
        #expect(revisionOwner.committedRevision.rawValue == 1)
    }

    @Test("replacement rejects a dictionary key that does not match pane identity")
    func replacementRejectsKeyIdentityMismatch() {
        // Arrange
        let paneState = makePaneGraphState(title: "Mismatched key")
        let wrongKey = UUIDv7.generate()

        // Act
        let result = WorkspacePaneGraphReplacement.prepare([wrongKey: paneState])

        // Assert
        #expect(result == .failure(.paneKeyIdentityMismatch(key: wrongKey, paneID: paneState.id)))
    }

    @Test("replacement rejects duplicate drawer identity")
    func replacementRejectsDuplicateDrawerIdentity() {
        // Arrange
        let duplicateDrawerID = UUIDv7.generate()
        let firstParent = makeLayoutPaneGraphState(title: "First", drawerID: duplicateDrawerID)
        let secondParent = makeLayoutPaneGraphState(title: "Second", drawerID: duplicateDrawerID)

        // Act
        let result = WorkspacePaneGraphReplacement.prepare([
            firstParent.id: firstParent,
            secondParent.id: secondParent,
        ])

        // Assert
        #expect(result == .failure(.duplicateDrawerIdentity(duplicateDrawerID)))
    }

    @Test("replacement rejects an orphan drawer child")
    func replacementRejectsOrphanDrawerChild() {
        // Arrange
        let parent = makeLayoutPaneGraphState(title: "Parent")
        let child = makeDrawerChildPaneGraphState(title: "Child", parentPaneID: parent.id)

        // Act
        let result = WorkspacePaneGraphReplacement.prepare([
            parent.id: parent,
            child.id: child,
        ])

        // Assert
        #expect(result == .failure(.orphanDrawerChild(childPaneID: child.id, parentPaneID: parent.id)))
    }

    @Test("replacement rejects parent and member disagreement")
    func replacementRejectsParentMemberMismatch() {
        // Arrange
        var firstParent = makeLayoutPaneGraphState(title: "First parent")
        let secondParent = makeLayoutPaneGraphState(title: "Second parent")
        let child = makeDrawerChildPaneGraphState(title: "Child", parentPaneID: secondParent.id)
        firstParent.withDrawer { $0.paneIds = [child.id] }

        // Act
        let result = WorkspacePaneGraphReplacement.prepare([
            firstParent.id: firstParent,
            secondParent.id: secondParent,
            child.id: child,
        ])

        // Assert
        #expect(
            result
                == .failure(
                    .drawerChildParentMismatch(
                        childPaneID: child.id,
                        expectedParentPaneID: firstParent.id,
                        actualParentPaneID: secondParent.id
                    )
                )
        )
    }

    @Test("replacement rejects duplicate drawer child membership")
    func replacementRejectsDuplicateDrawerChildMembership() {
        // Arrange
        var parent = makeLayoutPaneGraphState(title: "Parent")
        let child = makeDrawerChildPaneGraphState(title: "Child", parentPaneID: parent.id)
        parent.withDrawer { $0.paneIds = [child.id, child.id] }

        // Act
        let result = WorkspacePaneGraphReplacement.prepare([
            parent.id: parent,
            child.id: child,
        ])

        // Assert
        #expect(result == .failure(.duplicateDrawerChildMembership(child.id)))
    }

    @Test("legacy replacement removes missing drawer members but retains repository-independent panes")
    func legacyReplacementNormalizesMembershipWithoutTopologyFiltering() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let adapter = WorkspacePaneGraphPersistenceAdapter(
            atom: WorkspacePaneGraphAtom(),
            revisionOwner: revisionOwner
        )
        let unavailableWorktreeID = UUIDv7.generate()
        let missingPaneID = UUIDv7.generate()
        var parent = makeLayoutPaneGraphState(title: "Parent")
        parent.metadata.facets.worktreeId = unavailableWorktreeID
        parent.withDrawer { $0.paneIds = [missingPaneID] }

        // Act
        let replacement = try requireReplacement(
            adapter.makeLegacyHydrationReplacement(
                persistedPanes: [parent.pane(isDrawerExpanded: false)]
            )
        )

        // Assert
        #expect(replacement.paneStates[parent.id]?.metadata.facets.worktreeId == unavailableWorktreeID)
        #expect(replacement.paneStates[parent.id]?.drawer?.paneIds.isEmpty == true)
    }

    @Test("post-install full replacement preserves base updates removals and insertion exclusion")
    func postInstallReplacementCapturesEveryKeyedChange() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let atom = WorkspacePaneGraphAtom()
        let adapter = WorkspacePaneGraphPersistenceAdapter(atom: atom, revisionOwner: revisionOwner)
        let retained = makePaneGraphState(title: "Retained base")
        let removed = makePaneGraphState(title: "Removed base")
        atom.addPane(retained.pane(isDrawerExpanded: false))
        atom.addPane(removed.pane(isDrawerExpanded: false))
        let participant = requireParticipant(
            adapter.makeSnapshotParticipant(
                membershipLimits: membershipLimits,
                estimatedByteCount: { _ in 1 }
            )
        )
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        #expect(participant.open(lease: lease) == .opened(baseMembershipCount: 2))
        var updated = retained
        updated.metadata.title = "Updated current"
        let inserted = makePaneGraphState(title: "Post-base insertion")
        let replacement = try requireReplacement([
            updated.id: updated,
            inserted.id: inserted,
        ])

        // Act
        try revisionOwner.performSynchronousTransaction { preparation in
            try adapter.prepareReplacement(
                replacement,
                for: preparation
            )
            return preparation.commit {}
        }
        let baseItems = (0..<2).compactMap { slot -> PaneGraphState? in
            guard case .item(let projected, _, _, _) = participant.inspectBaseSlot(lease: lease, slotCursor: slot),
                case .paneGraph(let paneState) = projected.item
            else { return nil }
            return paneState
        }

        // Assert
        #expect(atom.paneState(updated.id) == updated)
        #expect(atom.paneState(removed.id) == nil)
        #expect(atom.paneState(inserted.id) == inserted)
        #expect(Set(baseItems) == Set([retained, removed]))
        #expect(!baseItems.contains(inserted))
    }

    @Test("failed later preparation cancels pane bookkeeping and leaves canonical state atomic")
    func failedLaterPreparationIsAtomicAndPermitsRetry() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let atom = WorkspacePaneGraphAtom()
        let adapter = WorkspacePaneGraphPersistenceAdapter(atom: atom, revisionOwner: revisionOwner)
        let original = makePaneGraphState(title: "Original")
        atom.addPane(original.pane(isDrawerExpanded: false))
        _ = requireParticipant(
            adapter.makeSnapshotParticipant(
                membershipLimits: membershipLimits,
                estimatedByteCount: { _ in 1 }
            ))
        var updated = original
        updated.metadata.title = "Should not commit"
        let laterParticipant = WorkspaceStateSnapshotKeyedParticipant<UUID, String>()
        #expect(
            laterParticipant.configureMembershipLimits(
                .init(maximumKeyCount: 0, maximumRawKeyBytes: 0)
            ) == .configured
        )
        func failAfterSecondPreparation(
            _ preparation: WorkspacePersistenceTransactionPreparation
        ) throws -> WorkspacePersistencePreparedMutation<Bool> {
            let firstPrepared = try requirePrepared(
                adapter.prepareMutation(
                    .update(updated),
                    for: preparation
                )
            )
            _ = firstPrepared
            guard
                case .rejected = laterParticipant.prepare(
                    [
                        .insert(
                            .init(
                                key: UUIDv7.generate(),
                                rawKeyByteCount: 1
                            )
                        )
                    ],
                    for: preparation,
                    revisionOwner: revisionOwner
                )
            else {
                throw PanePreparationTestError.expectedRejection
            }
            throw PanePreparationTestError.expectedRejection
        }

        // Act
        #expect(throws: PanePreparationTestError.self) {
            _ = try revisionOwner.performSynchronousTransaction(failAfterSecondPreparation)
        }
        try revisionOwner.performSynchronousTransaction { preparation in
            let prepared = try requirePrepared(
                adapter.prepareMutation(
                    .update(updated),
                    for: preparation
                )
            )
            return preparation.commit {
                adapter.applyPreparedMutation(prepared)
            }
        }

        // Assert
        #expect(atom.paneState(original.id)?.metadata.title == "Should not commit")
        #expect(revisionOwner.committedRevision.rawValue == 1)
        #expect(
            adapter.preparationDiagnostics()
                == WorkspaceSnapshotPreparationDiagnostics(
                    status: .available,
                    appliedReservationCount: 1,
                    cancelledReservationCount: 1
                )
        )
    }

    @Test("last-key current read performs one keyed lookup without raw-key recomputation")
    func lastKeyCurrentReadIsBounded() {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let atom = WorkspacePaneGraphAtom()
        let adapter = WorkspacePaneGraphPersistenceAdapter(atom: atom, revisionOwner: revisionOwner)
        let paneCount = 10_000
        for index in 0..<paneCount {
            let pane = makePaneGraphState(title: "Pane \(index)")
            atom.addPane(pane.pane(isDrawerExpanded: false))
        }
        let participant = requireParticipant(
            adapter.makeSnapshotParticipant(
                membershipLimits: membershipLimits,
                estimatedByteCount: { _ in 1 }
            ))
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        #expect(
            participant.open(lease: lease)
                == .opened(baseMembershipCount: paneCount)
        )
        let beforeRead = adapter.participantDiagnostics()
        guard case .upperBound(let slotUpperBound) = participant.slotUpperBound(for: lease) else {
            Issue.record("expected pane participant slot upper bound")
            return
        }

        // Act
        let inspection = participant.inspectBaseSlot(
            lease: lease,
            slotCursor: slotUpperBound - 1
        )
        let afterRead = adapter.participantDiagnostics()

        // Assert
        guard case .item(let projectedItem, _, _, _) = inspection,
            case .paneGraph(let inspectedPane) = projectedItem.item
        else {
            Issue.record("expected final pane participant item")
            return
        }
        #expect(atom.paneState(inspectedPane.id) != nil)
        #expect(afterRead.currentValueLookupCount - beforeRead.currentValueLookupCount == 1)
        #expect(afterRead.rawKeyByteCacheLookupCount == beforeRead.rawKeyByteCacheLookupCount)
        #expect(afterRead.membershipBootstrapPaneCount == UInt64(paneCount))
    }

    private func performMutation(
        _ mutation: WorkspacePaneGraphPersistenceMutation,
        adapter: WorkspacePaneGraphPersistenceAdapter,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) throws {
        try revisionOwner.performSynchronousTransaction { preparation in
            let prepared = try requirePrepared(
                adapter.prepareMutation(
                    mutation,
                    for: preparation
                )
            )
            return preparation.commit {
                adapter.applyPreparedMutation(prepared)
            }
        }
    }

    private func requirePrepared(
        _ result: WorkspacePaneGraphPersistencePreparationResult
    ) throws -> WorkspacePaneGraphPreparedPersistenceMutation {
        guard case .prepared(let prepared) = result else {
            throw PanePreparationTestError.expectedPreparedMutation
        }
        return prepared
    }

    private func requireParticipant(
        _ result: SnapshotPagerParticipantConstructionResult<
            WorkspacePersistenceSnapshotParticipantID,
            WorkspacePersistenceSnapshotItem
        >
    ) -> WorkspaceStateSnapshotPagerParticipant<
        WorkspacePersistenceSnapshotParticipantID,
        WorkspacePersistenceSnapshotItem
    > {
        guard case .constructed(let participant) = result else {
            Issue.record("expected pane graph participant construction")
            preconditionFailure("expected pane graph participant construction")
        }
        return participant
    }

    private func makePaneGraphState(title: String) -> PaneGraphState {
        PaneGraphState(
            pane: Pane(
                content: .terminal(
                    TerminalState(provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7())),
                metadata: PaneMetadata(title: title)
            )
        )
    }

    private func makeLayoutPaneGraphState(
        title: String,
        drawerID: UUID = UUIDv7.generate()
    ) -> PaneGraphState {
        let paneID = UUIDv7.generate()
        return PaneGraphState(
            pane: Pane(
                id: paneID,
                content: .terminal(
                    TerminalState(provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7())),
                metadata: PaneMetadata(title: title),
                kind: .layout(drawer: Drawer(drawerId: drawerID, parentPaneId: paneID))
            )
        )
    }

    private func makeDrawerChildPaneGraphState(title: String, parentPaneID: UUID) -> PaneGraphState {
        PaneGraphState(
            pane: Pane(
                content: .terminal(
                    TerminalState(provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7())),
                metadata: PaneMetadata(title: title),
                kind: .drawerChild(parentPaneId: parentPaneID)
            )
        )
    }

    private func requireReplacement(
        _ result: Result<WorkspacePaneGraphReplacement, WorkspacePaneGraphReplacementRejection>
    ) throws -> WorkspacePaneGraphReplacement {
        switch result {
        case .success(let replacement):
            return replacement
        case .failure:
            throw PanePreparationTestError.expectedReplacement
        }
    }

    private func requireReplacement(
        _ statesByID: [UUID: PaneGraphState]
    ) throws -> WorkspacePaneGraphReplacement {
        try requireReplacement(WorkspacePaneGraphReplacement.prepare(statesByID))
    }
}

@MainActor
private func makePaneGraphAdapterBundle(
    atom: WorkspacePaneGraphAtom,
    revisionOwner: WorkspacePersistenceRevisionOwner
) -> WorkspacePersistenceAdapterBundle {
    WorkspacePersistenceAdapterBundle(
        revisionOwner: revisionOwner,
        workspaceIdentityAtom: WorkspaceIdentityAtom(),
        workspaceWindowMemoryAtom: WorkspaceWindowMemoryAtom(),
        repositoryTopologyAtom: RepositoryTopologyAtom(),
        workspacePaneGraphAtom: atom,
        workspaceDrawerCursorAtom: WorkspaceDrawerCursorAtom(),
        workspaceTabShellAtom: WorkspaceTabShellAtom(),
        workspaceTabCursorAtom: WorkspaceTabCursorAtom(),
        workspaceTabGraphAtom: WorkspaceTabGraphAtom(),
        workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom()
    )
}

private enum PanePreparationTestError: Error {
    case expectedPreparedMutation
    case expectedRejection
    case expectedReplacement
}
