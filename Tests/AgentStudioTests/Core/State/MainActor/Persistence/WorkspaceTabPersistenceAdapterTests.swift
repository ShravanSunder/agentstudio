import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceTabPersistenceAdapterTests {
    @Test("initial replacements register before snapshot participants exist")
    func initialReplacementsRegisterBeforeParticipantsExist() throws {
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let shellAtom = WorkspaceTabShellAtom()
        let graphAtom = WorkspaceTabGraphAtom()
        let cursorAtom = WorkspaceArrangementCursorAtom()
        let bundle = makeTabAdapterBundle(
            revisionOwner: revisionOwner,
            shellAtom: shellAtom,
            graphAtom: graphAtom,
            arrangementCursorAtom: cursorAtom
        )
        let shellAdapter = bundle.workspaceTabShell
        let graphAdapter = bundle.workspaceTabGraph
        let cursorAdapter = bundle.workspaceArrangementCursor
        let graphState = makeAdapterGraphState()
        let shell = TabShell(id: graphState.tabId, name: "Initial")
        let arrangementID = graphState.arrangements[0].id

        let access = try bundle.withCompositionPreinstallAccess { token in
            try revisionOwner.performSynchronousTransaction { preparation in
                try shellAdapter.registerInitialReplacement(
                    token: token,
                    [shell],
                    for: preparation
                )
                try graphAdapter.registerInitialReplacement(
                    token: token,
                    [graphState],
                    for: preparation
                )
                try cursorAdapter.registerInitialReplacement(
                    token: token,
                    activeArrangementIdsByTabId: [shell.id: arrangementID],
                    paneCursorsByArrangementId: [arrangementID: .init(activePaneId: graphState.allPaneIds[0])],
                    drawerCursorsByKey: [:],
                    for: preparation
                )
                return preparation.commit {}
            }
        }
        guard case .authorized = access else {
            Issue.record("expected preinstall tab replacement access")
            return
        }

        #expect(shellAtom.tabShells == [shell])
        #expect(graphAtom.tabStates == [graphState])
        #expect(cursorAtom.activeArrangementId(forTab: shell.id) == arrangementID)
        #expect(revisionOwner.committedRevision.rawValue == 1)
    }

    @Test("shell reorder retains exact base sort indexes")
    func shellReorderRetainsBaseSortIndexes() throws {
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let atom = WorkspaceTabShellAtom()
        let adapter = WorkspaceTabShellPersistenceAdapter(atom: atom, revisionOwner: revisionOwner)
        let shells = (0..<3).map { TabShell(id: UUIDv7.generate(), name: "Tab \($0)") }
        atom.replaceTabShells(shells)
        let participant = try requireConstructedParticipant(
            adapter.makeSnapshotParticipant(limits: .init(maximumKeyCount: 16, maximumRawKeyBytes: 256))
        )
        let lease = WorkspaceStateSnapshotLease.open(pagerIdentity: .make(), revisionOwner: revisionOwner)
        #expect(participant.open(lease: lease) == .opened(baseMembershipCount: 3))

        try revisionOwner.performSynchronousTransaction { preparation in
            try adapter.preparePersistenceMutation(
                [.move(tabID: shells[2].id, toIndex: 0)],
                for: preparation
            )
            return preparation.commit {}
        }

        let retainedSortIndexes = (0..<3).compactMap { slotIndex -> (UUID, Int)? in
            guard
                case .item(let typedItem, _, _, _) = participant.inspectBaseSlot(
                    lease: lease,
                    slotCursor: slotIndex
                ), case .tabShell(let snapshot) = typedItem.item
            else { return nil }
            return (snapshot.shell.id, snapshot.sortIndex)
        }
        #expect(atom.tabShells.map(\.id) == [shells[2].id, shells[0].id, shells[1].id])
        #expect(
            Dictionary(uniqueKeysWithValues: retainedSortIndexes) == [
                shells[0].id: 0,
                shells[1].id: 1,
                shells[2].id: 2,
            ])
    }

    @Test("graph lease retains base graph and excludes post-base insertion")
    func graphLeaseRetainsFixedMembership() throws {
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let atom = WorkspaceTabGraphAtom()
        let adapter = WorkspaceTabGraphPersistenceAdapter(atom: atom, revisionOwner: revisionOwner)
        let original = makeAdapterGraphState()
        atom.replaceTabStates([original])
        let participant = try requireConstructedParticipant(
            adapter.makeSnapshotParticipant(limits: .init(maximumKeyCount: 512, maximumRawKeyBytes: 8192))
        )
        let lease = WorkspaceStateSnapshotLease.open(pagerIdentity: .make(), revisionOwner: revisionOwner)
        #expect(participant.open(lease: lease) == .opened(baseMembershipCount: 1))
        var updated = original
        updated.arrangements.reverse()
        let inserted = makeAdapterGraphState()

        try revisionOwner.performSynchronousTransaction { preparation in
            try adapter.preparePersistenceMutation(
                [.update(updated), .insert(inserted, at: 1)],
                for: preparation
            )
            return preparation.commit {}
        }

        guard
            case .item(let projectedItem, let expectedItemID, _, _) = participant.inspectBaseSlot(
                lease: lease,
                slotCursor: 0
            )
        else {
            Issue.record("expected retained tab graph item")
            return
        }
        #expect(expectedItemID == .tabGraph(original.tabId))
        #expect(projectedItem.item == .tabGraph(original))
        guard case .exhausted = participant.inspectBaseSlot(lease: lease, slotCursor: 1) else {
            Issue.record("expected post-base insertion outside fixed membership")
            return
        }
    }

    @Test("cursor lease retains selected values across clear and removal")
    func cursorLeaseRetainsSelectedValues() throws {
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let atom = WorkspaceArrangementCursorAtom()
        let adapter = WorkspaceArrangementCursorPersistenceAdapter(atom: atom, revisionOwner: revisionOwner)
        let tabID = UUIDv7.generate()
        let arrangementID = UUIDv7.generate()
        let paneID = UUIDv7.generate()
        let drawerKey = ArrangementDrawerCursorKey(arrangementId: arrangementID, drawerId: UUIDv7.generate())
        let participants = try requireConstructedCursorParticipants(
            adapter.makeSnapshotParticipants(limits: .init(maximumKeyCount: 512, maximumRawKeyBytes: 16_384))
        )
        try applyCursorOperations(
            .init(
                activeArrangements: [.set(tabID: tabID, arrangementID: arrangementID)],
                activePanes: [.set(arrangementID: arrangementID, paneID: paneID)],
                activeDrawerChildren: [.set(key: drawerKey, childPaneID: paneID)]
            ),
            adapter: adapter,
            revisionOwner: revisionOwner
        )
        let lease = WorkspaceStateSnapshotLease.open(pagerIdentity: .make(), revisionOwner: revisionOwner)
        #expect(participants.activeArrangements.open(lease: lease) == .opened(baseMembershipCount: 1))
        #expect(participants.activePanes.open(lease: lease) == .opened(baseMembershipCount: 1))
        #expect(participants.activeDrawerChildren.open(lease: lease) == .opened(baseMembershipCount: 1))

        try applyCursorOperations(
            .init(
                activeArrangements: [.remove(tabID: tabID)],
                activePanes: [.clearSelection(arrangementID: arrangementID)],
                activeDrawerChildren: [.removeCursor(key: drawerKey)]
            ),
            adapter: adapter,
            revisionOwner: revisionOwner
        )

        guard
            case .item(let arrangementItem, _, _, _) = participants.activeArrangements.inspectBaseSlot(
                lease: lease,
                slotCursor: 0
            ),
            case .item(let paneItem, _, _, _) = participants.activePanes.inspectBaseSlot(
                lease: lease,
                slotCursor: 0
            ),
            case .item(let drawerItem, _, _, _) = participants.activeDrawerChildren.inspectBaseSlot(
                lease: lease,
                slotCursor: 0
            )
        else {
            Issue.record("expected all cursor participants to retain base values")
            return
        }
        #expect(arrangementItem.item == .activeArrangement(tabID: tabID, arrangementID: arrangementID))
        #expect(paneItem.item == .activePane(arrangementID: arrangementID, paneID: paneID))
        #expect(drawerItem.item == .activeDrawerChild(key: drawerKey, childPaneID: paneID))
    }
}

@MainActor
private func makeTabAdapterBundle(
    revisionOwner: WorkspacePersistenceRevisionOwner,
    shellAtom: WorkspaceTabShellAtom,
    graphAtom: WorkspaceTabGraphAtom,
    arrangementCursorAtom: WorkspaceArrangementCursorAtom
) -> WorkspacePersistenceAdapterBundle {
    WorkspacePersistenceAdapterBundle(
        revisionOwner: revisionOwner,
        workspaceIdentityAtom: WorkspaceIdentityAtom(workspaceId: UUIDv7.generate()),
        workspaceWindowMemoryAtom: WorkspaceWindowMemoryAtom(),
        repositoryTopologyAtom: RepositoryTopologyAtom(),
        workspacePaneGraphAtom: WorkspacePaneGraphAtom(),
        workspaceDrawerCursorAtom: WorkspaceDrawerCursorAtom(),
        workspaceTabShellAtom: shellAtom,
        workspaceTabCursorAtom: WorkspaceTabCursorAtom(),
        workspaceTabGraphAtom: graphAtom,
        workspaceArrangementCursorAtom: arrangementCursorAtom
    )
}

@MainActor
private func applyCursorOperations(
    _ operations: WorkspaceArrangementCursorPersistenceOperations,
    adapter: WorkspaceArrangementCursorPersistenceAdapter,
    revisionOwner: WorkspacePersistenceRevisionOwner
) throws {
    try revisionOwner.performSynchronousTransaction { preparation in
        try adapter.preparePersistenceMutation(operations, for: preparation)
        return preparation.commit {}
    }
}

@MainActor
private func requireConstructedParticipant(
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
        throw WorkspaceTabShellPersistencePreparationError.snapshotParticipant(rejection)
    }
}

@MainActor
private func requireConstructedCursorParticipants(
    _ result: ArrangementCursorParticipantsResult
) throws -> WorkspaceArrangementCursorSnapshotParticipants {
    switch result {
    case .constructed(let participants): participants
    case .rejected(let rejection): throw ArrangementCursorPreparationError.snapshotParticipant(rejection)
    }
}

private func makeAdapterGraphState() -> TabGraphState {
    let firstPaneID = UUIDv7.generate()
    let secondPaneID = UUIDv7.generate()
    return TabGraphState(
        tabId: UUIDv7.generate(),
        allPaneIds: [firstPaneID, secondPaneID],
        arrangements: [
            .init(
                id: UUIDv7.generate(),
                name: "Default",
                isDefault: true,
                layout: Layout(paneId: firstPaneID),
                minimizedPaneIds: [],
                showsMinimizedPanes: false,
                drawerViews: [:]
            ),
            .init(
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
