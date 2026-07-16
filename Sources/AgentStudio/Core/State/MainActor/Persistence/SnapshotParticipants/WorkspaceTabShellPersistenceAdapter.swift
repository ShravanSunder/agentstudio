import Foundation

enum WorkspaceTabShellPersistenceOperation: Equatable, Sendable {
    case insert(TabShell, at: Int)
    case update(TabShell)
    case remove(tabID: UUID)
    case move(tabID: UUID, toIndex: Int)
}

enum WorkspaceTabShellPersistencePreparationError: Error, Equatable {
    case duplicateTabID(UUID)
    case emptyCapture
    case invalidInsertionIndex(Int)
    case invalidMoveIndex(Int)
    case missingTabID(UUID)
    case ownerRegistration(WorkspaceParticipantRegistrationRejection)
    case snapshotParticipant(WorkspaceStateSnapshotParticipantRejection)
    case snapshotPreparation(WorkspaceSnapshotPreparationRejection)
}

private struct WorkspaceTabShellPreparedPersistenceMutation {
    let transaction: WorkspacePersistenceTransaction
    let tabShells: [TabShell]
}

@MainActor
final class WorkspaceTabShellPersistenceAdapter {
    private let atom: WorkspaceTabShellAtom
    private let revisionOwner: WorkspacePersistenceRevisionOwner
    private let snapshotParticipant = WorkspaceStateSnapshotKeyedParticipant<
        UUID,
        WorkspacePersistenceSnapshotTabShell
    >()

    init(atom: WorkspaceTabShellAtom, revisionOwner: WorkspacePersistenceRevisionOwner) {
        self.atom = atom
        self.revisionOwner = revisionOwner
    }

    func makeSnapshotParticipant(
        limits: WorkspaceStateSnapshotMembershipLimits
    ) -> SnapshotPagerParticipantConstructionResult<
        WorkspacePersistenceSnapshotParticipantID,
        WorkspacePersistenceSnapshotItem
    > {
        WorkspaceStateSnapshotPagerParticipant<
            WorkspacePersistenceSnapshotParticipantID,
            WorkspacePersistenceSnapshotItem
        >.typed(
            participantID: .tabShells,
            keyedParticipant: snapshotParticipant,
            membershipLimits: limits,
            orderedBaseKeys: { [atom] in atom.tabShells.map(\.id) },
            currentValue: { [atom] tabID in
                guard let index = atom.tabIndex(for: tabID) else { return .absent }
                return .value(
                    WorkspacePersistenceSnapshotTabShell(
                        shell: atom.tabShells[index],
                        sortIndex: index
                    )
                )
            },
            projection: WorkspaceStateSnapshotItemProjection(
                itemIDForKey: { .tabShell($0) },
                projectItem: { _, snapshot in
                    WorkspaceStateSnapshotPagerTypedItem(
                        item: .tabShell(snapshot),
                        estimatedByteCount: Self.estimatedSnapshotByteCount(snapshot)
                    )
                }
            ),
            rawKeyByteCount: { _ in 16 }
        )
    }

    func preparePersistenceMutation(
        _ operations: [WorkspaceTabShellPersistenceOperation],
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        var nextTabShells = atom.tabShells
        for operation in operations {
            switch operation {
            case .insert(let shell, let index):
                guard !nextTabShells.contains(where: { $0.id == shell.id }) else {
                    throw WorkspaceTabShellPersistencePreparationError.duplicateTabID(shell.id)
                }
                guard index >= 0, index <= nextTabShells.count else {
                    throw WorkspaceTabShellPersistencePreparationError.invalidInsertionIndex(index)
                }
                nextTabShells.insert(shell, at: index)
            case .update(let shell):
                guard let index = nextTabShells.firstIndex(where: { $0.id == shell.id }) else {
                    throw WorkspaceTabShellPersistencePreparationError.missingTabID(shell.id)
                }
                nextTabShells[index] = shell
            case .remove(let tabID):
                guard let index = nextTabShells.firstIndex(where: { $0.id == tabID }) else {
                    throw WorkspaceTabShellPersistencePreparationError.missingTabID(tabID)
                }
                nextTabShells.remove(at: index)
            case .move(let tabID, let toIndex):
                guard let index = nextTabShells.firstIndex(where: { $0.id == tabID }) else {
                    throw WorkspaceTabShellPersistencePreparationError.missingTabID(tabID)
                }
                guard toIndex >= 0, toIndex < nextTabShells.count else {
                    throw WorkspaceTabShellPersistencePreparationError.invalidMoveIndex(toIndex)
                }
                let shell = nextTabShells.remove(at: index)
                nextTabShells.insert(shell, at: toIndex)
            }
        }

        try prepareReplacement(nextTabShells, for: preparation)
    }

    func capturePersistencePreimages(
        _ capture: WorkspaceTabShellPersistenceCapture,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        guard !capture.operations.isEmpty else {
            throw WorkspaceTabShellPersistencePreparationError.emptyCapture
        }
        var capturedTabIDs = Set<UUID>()
        capturedTabIDs.reserveCapacity(capture.operations.count)
        var mutations: [WorkspaceStateSnapshotParticipantMutation<UUID, WorkspacePersistenceSnapshotTabShell>] = []
        mutations.reserveCapacity(capture.operations.count)

        for operation in capture.operations {
            let tabID: UUID
            switch operation {
            case .insertion(let id), .valueChange(let id), .removal(let id):
                tabID = id
            }
            guard capturedTabIDs.insert(tabID).inserted else {
                throw WorkspaceTabShellPersistencePreparationError.duplicateTabID(tabID)
            }
            switch operation {
            case .insertion:
                guard atom.tabIndex(for: tabID) == nil else {
                    throw WorkspaceTabShellPersistencePreparationError.duplicateTabID(tabID)
                }
                mutations.append(.insert(.init(key: tabID, rawKeyByteCount: 16)))
            case .valueChange:
                guard let currentIndex = atom.tabIndex(for: tabID) else {
                    throw WorkspaceTabShellPersistencePreparationError.missingTabID(tabID)
                }
                mutations.append(
                    .replaceValue(
                        key: tabID,
                        currentValue: .value(
                            WorkspacePersistenceSnapshotTabShell(
                                shell: atom.tabShells[currentIndex],
                                sortIndex: currentIndex
                            )
                        )
                    )
                )
            case .removal:
                guard let currentIndex = atom.tabIndex(for: tabID) else {
                    throw WorkspaceTabShellPersistencePreparationError.missingTabID(tabID)
                }
                mutations.append(
                    .remove(
                        .init(
                            key: tabID,
                            currentValue: .value(
                                WorkspacePersistenceSnapshotTabShell(
                                    shell: atom.tabShells[currentIndex],
                                    sortIndex: currentIndex
                                )
                            )
                        )
                    )
                )
            }
        }
        try prepareSnapshotParticipant(mutations, preparation: preparation)
    }

    func prepareReplacement(
        _ nextTabShells: [TabShell],
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        let nextTabIndexByID = try Self.makeUniqueIndex(nextTabShells)
        let snapshotMutations = makeSnapshotMutations(
            nextTabShells: nextTabShells,
            nextTabIndexByID: nextTabIndexByID
        )
        try prepareSnapshotParticipant(
            snapshotMutations,
            preparation: preparation
        )
        try registerPreparedReplacement(
            nextTabShells,
            for: preparation
        )
    }

    func registerInitialReplacement(
        token _: borrowing WorkspaceCompositionPreinstallToken,
        _ tabShells: [TabShell],
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        _ = try Self.makeUniqueIndex(tabShells)
        try registerPreparedReplacement(
            tabShells,
            for: preparation
        )
    }

    private func registerPreparedReplacement(
        _ tabShells: [TabShell],
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        let preparedMutation = WorkspaceTabShellPreparedPersistenceMutation(
            transaction: preparation.transaction,
            tabShells: tabShells
        )
        switch revisionOwner.registerPreparedParticipantMutation(
            participant: self,
            preparation: preparation,
            apply: { [atom, revisionOwner = self.revisionOwner] in
                precondition(
                    revisionOwner.validateActiveCommit(preparedMutation.transaction) == .active,
                    "tab shell prepared mutation requires its exact active transaction"
                )
                atom.replaceTabShells(preparedMutation.tabShells)
            },
            cancel: {}
        ) {
        case .registered:
            break
        case .rejected(let rejection):
            throw WorkspaceTabShellPersistencePreparationError.ownerRegistration(rejection)
        }
    }

    private func makeSnapshotMutations(
        nextTabShells: [TabShell],
        nextTabIndexByID: [UUID: Int]
    ) -> [WorkspaceStateSnapshotParticipantMutation<UUID, WorkspacePersistenceSnapshotTabShell>] {
        var mutations: [WorkspaceStateSnapshotParticipantMutation<UUID, WorkspacePersistenceSnapshotTabShell>] = []
        mutations.reserveCapacity(atom.tabShells.count + nextTabShells.count)
        for (oldIndex, oldShell) in atom.tabShells.enumerated() {
            let oldValue = WorkspacePersistenceSnapshotTabShell(shell: oldShell, sortIndex: oldIndex)
            guard let nextIndex = nextTabIndexByID[oldShell.id] else {
                mutations.append(.remove(.init(key: oldShell.id, currentValue: .value(oldValue))))
                continue
            }
            if nextIndex != oldIndex || nextTabShells[nextIndex] != oldShell {
                mutations.append(.replaceValue(key: oldShell.id, currentValue: .value(oldValue)))
            }
        }
        let currentIDs = Set(atom.tabShells.map(\.id))
        for shell in nextTabShells where !currentIDs.contains(shell.id) {
            mutations.append(.insert(.init(key: shell.id, rawKeyByteCount: 16)))
        }
        return mutations
    }

    private func prepareSnapshotParticipant(
        _ mutations: [WorkspaceStateSnapshotParticipantMutation<UUID, WorkspacePersistenceSnapshotTabShell>],
        preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        guard !mutations.isEmpty else { return }
        switch snapshotParticipant.prepare(mutations, for: preparation, revisionOwner: revisionOwner) {
        case .prepared:
            break
        case .rejected(let rejection):
            throw WorkspaceTabShellPersistencePreparationError.snapshotPreparation(rejection)
        }
    }

    private static func makeUniqueIndex(_ shells: [TabShell]) throws -> [UUID: Int] {
        var indexByID: [UUID: Int] = [:]
        indexByID.reserveCapacity(shells.count)
        for (index, shell) in shells.enumerated() {
            guard indexByID.updateValue(index, forKey: shell.id) == nil else {
                throw WorkspaceTabShellPersistencePreparationError.duplicateTabID(shell.id)
            }
        }
        return indexByID
    }

    private static func estimatedSnapshotByteCount(
        _ snapshot: WorkspacePersistenceSnapshotTabShell
    ) -> Int {
        16 + MemoryLayout<Int>.size + snapshot.shell.name.utf8.count
            + (snapshot.shell.colorHex?.utf8.count ?? 0) + 1
    }
}
