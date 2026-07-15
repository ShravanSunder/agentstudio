import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceTabGraphAtomTests {
    @Test("prepared graph insert update and remove preserve keyed indexes and nested order")
    func preparedGraphMutationsPreserveIndexesAndNestedOrder() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let atom = WorkspaceTabGraphAtom()
        let first = makeGraphState()
        let second = makeGraphState()
        atom.replaceStates([first])
        _ = try requireConstructedGraphParticipant(
            atom.makePersistenceSnapshotParticipant(limits: graphMembershipLimits)
        )
        var updatedFirst = first
        updatedFirst.allPaneIds.reverse()
        updatedFirst.arrangements.reverse()

        // Act
        try applyGraphOperations(
            [.insert(second, at: 1), .update(updatedFirst), .remove(second.tabId)],
            to: atom,
            revisionOwner: revisionOwner
        )

        // Assert
        #expect(atom.tabStates == [updatedFirst])
        #expect(atom.tabIndex(for: first.tabId) == 0)
        #expect(atom.tabState(first.tabId)?.allPaneIds == updatedFirst.allPaneIds)
        #expect(atom.tabState(first.tabId)?.arrangements.map(\.id) == updatedFirst.arrangements.map(\.id))
        #expect(revisionOwner.committedRevision.rawValue == 1)
    }

    @Test("last graph lookup uses the maintained ID index")
    func lastGraphLookupUsesMaintainedIndex() {
        // Arrange
        let atom = WorkspaceTabGraphAtom()
        let states = (0..<300).map { _ in makeGraphState() }
        atom.replaceStates(states)

        // Act
        let lastState = atom.tabState(states[299].tabId)

        // Assert
        #expect(lastState == states[299])
        #expect(atom.tabIndex(for: states[299].tabId) == 299)
    }

    @Test("active lease retains the base graph and excludes a post-base insertion")
    func activeLeaseRetainsBaseGraphAndExcludesPostBaseInsertion() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let atom = WorkspaceTabGraphAtom()
        let original = makeGraphState()
        atom.replaceStates([original])
        let participant = try requireConstructedGraphParticipant(
            atom.makePersistenceSnapshotParticipant(limits: graphMembershipLimits)
        )
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        #expect(participant.open(lease: lease, limits: graphMembershipLimits) == .opened(baseMembershipCount: 1))
        var updated = original
        updated.arrangements.reverse()
        let inserted = makeGraphState()

        // Act
        try applyGraphOperations(
            [.update(updated), .insert(inserted, at: 1)],
            to: atom,
            revisionOwner: revisionOwner
        )
        let baseInspection = participant.inspectBaseSlot(lease: lease, slotCursor: 0)
        let postBaseInspection = participant.inspectBaseSlot(lease: lease, slotCursor: 1)

        // Assert
        #expect(atom.tabStates == [updated, inserted])
        guard case .item(let projectedItem, let expectedItemID, _, _) = baseInspection else {
            Issue.record("expected retained tab graph item")
            return
        }
        #expect(expectedItemID == .tabGraph(original.tabId))
        #expect(projectedItem.item == .tabGraph(original))
        guard case .exhausted = postBaseInspection else {
            Issue.record("expected post-base graph insertion to remain outside fixed membership")
            return
        }
    }
}

@MainActor
private func applyGraphOperations(
    _ operations: [WorkspaceTabGraphPersistenceOperation],
    to atom: WorkspaceTabGraphAtom,
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

private let graphMembershipLimits = WorkspaceStateSnapshotMembershipLimits(
    maximumKeyCount: 512,
    maximumRawKeyBytes: 512 * 16
)

@MainActor
private func requireConstructedGraphParticipant(
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
    case .rejected(let rejection):
        Issue.record("expected graph participant, received \(rejection)")
        throw WorkspaceTabGraphPersistencePreparationError.snapshotParticipant(rejection)
    }
}

private func makeGraphState() -> TabGraphState {
    let firstPaneID = UUIDv7.generate()
    let secondPaneID = UUIDv7.generate()
    return TabGraphState(
        tabId: UUIDv7.generate(),
        allPaneIds: [firstPaneID, secondPaneID],
        arrangements: [
            PaneArrangementGraphState(
                id: UUIDv7.generate(),
                name: "Default",
                isDefault: true,
                layout: Layout(paneId: firstPaneID),
                minimizedPaneIds: [],
                showsMinimizedPanes: false,
                drawerViews: [:]
            ),
            PaneArrangementGraphState(
                id: UUIDv7.generate(),
                name: "Review",
                isDefault: false,
                layout: Layout(paneId: secondPaneID),
                minimizedPaneIds: [],
                showsMinimizedPanes: true,
                drawerViews: [:]
            ),
        ]
    )
}
