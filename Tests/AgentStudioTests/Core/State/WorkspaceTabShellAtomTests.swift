import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceTabShellAtomTests {
    @Test("prepared reorder retains exact base sort indexes and maintains the ID index")
    func preparedReorderRetainsBaseSortIndexes() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let atom = WorkspaceTabShellAtom()
        let shells = (0..<3).map { TabShell(id: UUIDv7.generate(), name: "Tab \($0)") }
        shells.forEach(atom.appendTabShell)
        let participant = try requireConstructedTabShellParticipant(
            atom.makePersistenceSnapshotParticipant(
                limits: .init(maximumKeyCount: 16, maximumRawKeyBytes: 16 * 16)
            )
        )
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        #expect(
            participant.open(
                lease: lease,
                limits: .init(maximumKeyCount: 16, maximumRawKeyBytes: 16 * 16)
            ) == .opened(baseMembershipCount: 3)
        )

        // Act
        try revisionOwner.performSynchronousTransaction { preparation in
            try atom.preparePersistenceMutation(
                [.move(tabID: shells[2].id, toIndex: 0)],
                for: preparation,
                revisionOwner: revisionOwner
            )
            return preparation.commit {}
        }
        let baseSortIndexes = (0..<3).compactMap { slotIndex -> (UUID, Int)? in
            guard
                case .item(let typedItem, _, _, _) = participant.inspectBaseSlot(
                    lease: lease,
                    slotCursor: slotIndex
                ), case .tabShell(let snapshot) = typedItem.item
            else { return nil }
            return (snapshot.shell.id, snapshot.sortIndex)
        }

        // Assert
        #expect(atom.tabShells.map(\.id) == [shells[2].id, shells[0].id, shells[1].id])
        #expect(atom.tabIndex(for: shells[2].id) == 0)
        #expect(
            Dictionary(uniqueKeysWithValues: baseSortIndexes) == [
                shells[0].id: 0,
                shells[1].id: 1,
                shells[2].id: 2,
            ])
    }

    @Test
    func appendTabShell_setsActiveTabId() {
        let atom = WorkspaceTabShellAtom()
        let shell = TabShell(id: UUID(), name: "One")

        atom.appendTabShell(shell)

        #expect(atom.tabShells == [shell])
        #expect(atom.activeTabId == shell.id)
    }

    @Test
    func removeTabShell_removesAndUpdatesActiveTabId() {
        let atom = WorkspaceTabShellAtom()
        let first = TabShell(id: UUID(), name: "One")
        let second = TabShell(id: UUID(), name: "Two")
        atom.appendTabShell(first)
        atom.appendTabShell(second)

        atom.removeTabShell(second.id)

        #expect(atom.tabShells == [first])
        #expect(atom.activeTabId == first.id)
    }

    @Test
    func moveTabShell_reordersShells() {
        let atom = WorkspaceTabShellAtom()
        let first = TabShell(id: UUID(), name: "One")
        let second = TabShell(id: UUID(), name: "Two")
        atom.appendTabShell(first)
        atom.appendTabShell(second)

        atom.moveTab(fromId: second.id, toIndex: 0)

        #expect(atom.tabShells.map { $0.id } == [second.id, first.id])
    }

    @Test
    func renameTabShell_updatesName() {
        let atom = WorkspaceTabShellAtom()
        let shell = TabShell(id: UUID(), name: "One")
        atom.appendTabShell(shell)

        atom.renameTab(shell.id, name: "Review Queue")

        #expect(atom.tabShells.first?.name == "Review Queue")
    }

    @Test
    func setTabColorHex_canonicalizesAndClearsColor() throws {
        let atom = WorkspaceTabShellAtom()
        let shell = TabShell(id: UUID(), name: "One")
        atom.appendTabShell(shell)

        try atom.setTabColorHex("#22cc88", tabId: shell.id)
        #expect(atom.tabShell(shell.id)?.colorHex == "#22CC88")

        try atom.setTabColorHex(nil, tabId: shell.id)
        #expect(atom.tabShell(shell.id)?.colorHex == nil)
    }

    @Test
    func setTabColorHex_rejectsInvalidColor() {
        let atom = WorkspaceTabShellAtom()
        let shell = TabShell(id: UUID(), name: "One")
        atom.appendTabShell(shell)

        #expect(throws: WorkspaceTabShellAtomError.invalidTabColorHex("22cc88")) {
            try atom.setTabColorHex("22cc88", tabId: shell.id)
        }
    }

    @Test
    func removeTabShell_middleActiveRemoval_activatesLastRemainingTab() {
        let atom = WorkspaceTabShellAtom()
        let first = TabShell(id: UUID(), name: "One")
        let second = TabShell(id: UUID(), name: "Two")
        let third = TabShell(id: UUID(), name: "Three")
        atom.appendTabShell(first)
        atom.appendTabShell(second)
        atom.appendTabShell(third)
        atom.setActiveTab(second.id)

        atom.removeTabShell(second.id)

        #expect(atom.tabShells.map(\.id) == [first.id, third.id])
        #expect(atom.activeTabId == third.id)
    }

    @Test
    func moveTabByDelta_reordersShells() {
        let atom = WorkspaceTabShellAtom()
        let first = TabShell(id: UUID(), name: "One")
        let second = TabShell(id: UUID(), name: "Two")
        let third = TabShell(id: UUID(), name: "Three")
        atom.appendTabShell(first)
        atom.appendTabShell(second)
        atom.appendTabShell(third)

        atom.moveTabByDelta(tabId: first.id, delta: 2)

        #expect(atom.tabShells.map(\.id) == [second.id, third.id, first.id])
    }

    @Test
    func insertTabShell_preservesExistingActiveTab() {
        let atom = WorkspaceTabShellAtom()
        let first = TabShell(id: UUID(), name: "One")
        let second = TabShell(id: UUID(), name: "Two")
        atom.appendTabShell(first)
        atom.setActiveTab(first.id)

        atom.insertTabShell(second, at: 0)

        #expect(atom.tabShells.map(\.id) == [second.id, first.id])
        #expect(atom.activeTabId == first.id)
    }

    @Test
    func setActiveTab_rejectsMissingTabId() {
        let atom = WorkspaceTabShellAtom()
        let first = TabShell(id: UUID(), name: "One")
        atom.appendTabShell(first)

        atom.setActiveTab(UUID())

        #expect(atom.activeTabId == first.id)
    }

    @Test
    func hydrate_withStaleActiveTabId_fallsBackToFirstTab() {
        let pane = UUID()
        let arrangement = PaneArrangement(name: "Default", isDefault: true, layout: Layout(paneId: pane))
        let tab = Tab(
            name: "One",
            allPaneIds: [pane],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: pane
        )
        let atom = WorkspaceTabShellAtom()

        atom.hydrate(persistedTabs: [tab], activeTabId: UUID())

        #expect(atom.activeTabId == tab.id)
    }
}

@MainActor
private func requireConstructedTabShellParticipant(
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
        Issue.record("expected tab shell participant, received \(rejection)")
        throw WorkspaceTabShellPersistencePreparationError.snapshotParticipant(rejection)
    }
}
