import Foundation

/// Build the receiver's Files input from copied navigation and topology facts.
/// Callers capture those facts and a ticket before leaving MainActor; neither
/// ordering nor worktree resolution runs at the publication hop.
package enum BridgeFilesBindingPreparation {
    @concurrent nonisolated package static func prepareOffMain(
        receiver: BridgeReceiver, record: BridgeNavigationRecord,
        topology: BridgeReceiverTopologySnapshot, ticket: Int
    ) async -> BridgePreparedFilesBinding {
        let members = record.effectiveMemberWorktreeIds.compactMap(topology.knownWorktree)
        return makeBinding(
            receiver: receiver, record: record, members: members, ticket: ticket)
    }

    @concurrent nonisolated package static func prepareAllOffMain(
        records: [BridgeReceiver: BridgeNavigationRecord],
        repositoryTopology: RepositoryTopologyReadSnapshot, ticket: Int
    ) async -> [BridgeReceiver: BridgePreparedFilesBinding] {
        Dictionary(
            uniqueKeysWithValues: records.map { receiver, record in
                let members: [Worktree] = record.effectiveMemberWorktreeIds.compactMap { worktreeID -> Worktree? in
                    guard let worktree = repositoryTopology.worktree(worktreeID) else { return nil }
                    return repositoryTopology.validatedAssociation(
                        repoId: worktree.repoId, worktreeId: worktreeID)?.worktree
                }
                return (
                    receiver,
                    makeBinding(
                        receiver: receiver, record: record,
                        members: members, ticket: ticket)
                )
            })
    }

    package static func prepare(
        receiver: BridgeReceiver,
        record: BridgeNavigationRecord,
        knownWorktreesByID: [UUID: Worktree],
        ticket: Int
    ) -> BridgePreparedFilesBinding {
        let members = record.effectiveMemberWorktreeIds.compactMap { knownWorktreesByID[$0] }
        return makeBinding(
            receiver: receiver, record: record, members: members, ticket: ticket)
    }

    private static func makeBinding(
        receiver: BridgeReceiver, record: BridgeNavigationRecord,
        members: [Worktree], ticket: Int
    ) -> BridgePreparedFilesBinding {
        let orderedLocations = record.openedDocuments.sorted { lhs, rhs in
            let leftKey = lhs.value.sortKey.uuidString
            let rightKey = rhs.value.sortKey.uuidString
            return leftKey == rightKey ? lhs.key < rhs.key : leftKey < rightKey
        }.map(\.key)
        return BridgePreparedFilesBinding(
            ticket: ticket,
            binding: BridgeFilesSourceBinding(
                collectionToken: BridgeFilesSourceBinding.collectionToken(forReceiverPaneId: receiver.paneId),
                members: members,
                openedDocuments: orderedLocations
            )
        )
    }

    @concurrent nonisolated static func prepareAllOffMain(
        records: [BridgeReceiver: BridgeNavigationRecord],
        topology: RepositoryTopologyReplacement, ticket: Int
    ) async -> [BridgeReceiver: BridgePreparedFilesBinding] {
        let snapshot = RepositoryTopologyReadSnapshot(replacement: topology)
        let worktreesByID = Dictionary(
            topology.repositories.flatMap(\.worktrees).compactMap { worktree in
                snapshot.validatedAssociation(
                    repoId: worktree.repoId, worktreeId: worktree.id
                )
                .map { (worktree.id, $0.worktree) }
            },
            uniquingKeysWith: { first, _ in first })
        return Dictionary(
            uniqueKeysWithValues: records.map { receiver, record in
                (
                    receiver,
                    prepare(
                        receiver: receiver, record: record,
                        knownWorktreesByID: worktreesByID, ticket: ticket)
                )
            })
    }
}
