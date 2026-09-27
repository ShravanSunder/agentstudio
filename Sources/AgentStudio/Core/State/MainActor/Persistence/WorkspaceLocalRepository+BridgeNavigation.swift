import Foundation
import GRDB
import os.log

private let bridgeReceiverStorageLogger = Logger(subsystem: "com.agentstudio", category: "BridgeReceiverStorage")

struct BridgeReceiverReadback {
    let records: [BridgeReceiver: BridgeNavigationRecord]
    let presentPaneIDs: Set<UUID>
}

struct BridgeReceiverWriteChange {
    let workspaceID: UUID
    let receiver: BridgeReceiver
    let current: BridgeNavigationRecord
    let desired: BridgeNavigationRecord
    let generation: Int
    let includeItems: Bool
    let forceDependentDeletes: Bool
}

private enum BridgeReceiverOwnerDisposition {
    case current
    case staleOwner
    case staleReceiver
}

extension BridgeReceiverTopologySnapshot {
    fileprivate func ownerDisposition(for receiver: BridgeReceiver) -> BridgeReceiverOwnerDisposition {
        guard
            let resolved = BridgeReceiverResolution.receiver(
                forCommandPaneId: sourcePaneId,
                companionEntriesBySourceID: companionEntriesBySourceID,
                paneStatesByID: paneStatesByID
            )
        else { return .staleReceiver }
        guard resolved == receiver else { return .staleOwner }
        guard let owner = paneStatesByID[receiver.paneId] else { return .staleReceiver }
        switch (receiver.kind, owner.paneContent) {
        case (.terminalAssociated, .terminal), (.standaloneBridge, .bridgePanel): return .current
        default: return .staleReceiver
        }
    }

    func knownWorktree(_ worktreeID: UUID) -> Worktree? {
        guard let worktree = repositoryTopology.worktree(worktreeID) else { return nil }
        return repositoryTopology.validatedAssociation(
            repoId: worktree.repoId, worktreeId: worktreeID)?.worktree
    }

    package func memberRoots(in record: BridgeNavigationRecord) -> [UUID: String] {
        roots(for: record.committedMemberWorktreeIds)
    }

    package func effectiveMemberRoots(in record: BridgeNavigationRecord) -> [UUID: String] {
        roots(for: record.effectiveMemberWorktreeIds)
    }

    private func roots(for memberWorktreeIDs: [UUID]) -> [UUID: String] {
        Dictionary(
            uniqueKeysWithValues: memberWorktreeIDs.compactMap { worktreeID in
                guard let worktree = knownWorktree(worktreeID) else { return nil }
                return (worktreeID, DarwinFSEventPathCanonicalizer.canonicalURL(worktree.path).path)
            })
    }

    fileprivate func validatedCurrentCWDWorktreeID(receiver: BridgeReceiver) -> UUID? {
        guard receiver.kind == .terminalAssociated,
            let owner = paneStatesByID[receiver.paneId],
            let association = repositoryTopology.validatedAssociation(
                repoId: owner.metadata.facets.repoId,
                worktreeId: owner.metadata.facets.worktreeId)
        else { return nil }
        return association.worktree.id
    }

    fileprivate func protectedWorktreeID(in record: BridgeNavigationRecord, receiver: BridgeReceiver) -> UUID? {
        BridgeNavigationRules.protectedWorktreeId(
            in: record, currentKnownCWDWorktreeId: validatedCurrentCWDWorktreeID(receiver: receiver))
    }
}

extension WorkspaceLocalRepository {
    func readBridgeReceivers() throws -> BridgeReceiverReadback {
        try databaseWriter.read { database in
            try WorkspaceLocalRepositoryStorage.readBridgeReceivers(database, workspaceID: workspaceId)
        }
    }

    func latestBridgeGeneration() throws -> Int {
        try databaseWriter.read { database in
            let state =
                try Int.fetchOne(
                    database, sql: "SELECT MAX(generation) FROM bridge_receiver_state WHERE workspace_id = ?",
                    arguments: [workspaceId.uuidString]) ?? 0
            let item =
                try Int.fetchOne(
                    database, sql: "SELECT MAX(generation) FROM bridge_receiver_item WHERE workspace_id = ?",
                    arguments: [workspaceId.uuidString]) ?? 0
            return max(state, item)
        }
    }

    /// Import only when a pane has no receiver rows. The legacy core payload is
    /// rewritten only after this local transaction acknowledges the import.
    func insertBridgeReceiversIfAbsent(_ records: [BridgeReceiver: BridgeNavigationRecord]) throws -> Set<UUID> {
        try databaseWriter.write { database in
            var present = try WorkspaceLocalRepositoryStorage.readBridgeReceivers(database, workspaceID: workspaceId)
                .presentPaneIDs
            for (receiver, record) in records where !present.contains(receiver.paneId) {
                try WorkspaceLocalRepositoryStorage.writeChanges(
                    database,
                    change: .init(
                        workspaceID: workspaceId, receiver: receiver, current: .empty,
                        desired: record, generation: 0, includeItems: true,
                        forceDependentDeletes: false))
                present.insert(receiver.paneId)
            }
            return present
        }
    }

    func saveBridgeCurrentValues(
        _ records: [BridgeReceiver: BridgeNavigationRecord],
        retainedPaneIDs: Set<UUID>, generation: Int, now: Date
    ) throws {
        try databaseWriter.write { database in
            try WorkspaceLocalRepositoryStorage.saveBridgeCurrentValues(
                database, workspaceID: workspaceId, records: records,
                retainedPaneIDs: retainedPaneIDs, generation: generation, now: now)
        }
    }

    func commitBridgeMemberAddition(
        receiver: BridgeReceiver, worktreeID: UUID,
        contributor: BridgeLinkContributor, generation: Int, addedAt: Date,
        topologySnapshot: BridgeReceiverTopologySnapshot
    ) throws -> (BridgeNavigationRecord, BridgeMemberAddResult) {
        try databaseWriter.write { database in
            try WorkspaceLocalRepositoryStorage.requireActive(database, workspaceID: workspaceId, receiver: receiver)
            let current = try WorkspaceLocalRepositoryStorage.readRecord(
                database, workspaceID: workspaceId, receiver: receiver)
            switch topologySnapshot.ownerDisposition(for: receiver) {
            case .staleOwner: return (current, .staleOwner)
            case .staleReceiver: return (current, .staleReceiver)
            case .current: break
            }
            guard topologySnapshot.knownWorktree(worktreeID) != nil else {
                return (current, .refusedUnknownWorktree)
            }
            let (desired, result) = BridgeNavigationRules.addingMemberContribution(
                worktreeID,
                contributor: contributor, addedAt: addedAt, to: current)
            try WorkspaceLocalRepositoryStorage.writeChanges(
                database,
                change: .init(
                    workspaceID: workspaceId, receiver: receiver, current: current,
                    desired: desired, generation: generation, includeItems: true,
                    forceDependentDeletes: false))
            return (
                try WorkspaceLocalRepositoryStorage.readRecord(database, workspaceID: workspaceId, receiver: receiver),
                result
            )
        }
    }

    func commitBridgeMemberRemoval(
        receiver: BridgeReceiver, worktreeID: UUID,
        contributor: BridgeLinkContributor, generation: Int,
        topologySnapshot: BridgeReceiverTopologySnapshot
    ) throws -> (BridgeNavigationRecord, BridgeMemberContributionRemoval) {
        try databaseWriter.write { database in
            try WorkspaceLocalRepositoryStorage.requireActive(database, workspaceID: workspaceId, receiver: receiver)
            let current = try WorkspaceLocalRepositoryStorage.readRecord(
                database, workspaceID: workspaceId, receiver: receiver)
            switch topologySnapshot.ownerDisposition(for: receiver) {
            case .staleOwner: return (current, .staleOwner)
            case .staleReceiver: return (current, .staleReceiver)
            case .current: break
            }
            if topologySnapshot.validatedCurrentCWDWorktreeID(receiver: receiver) == worktreeID {
                return (current, .refusedProtectedCurrentDirectory)
            }
            let result = BridgeNavigationRules.removingMemberContribution(
                worktreeID,
                contributor: contributor, from: current,
                protectedWorktreeId: topologySnapshot.protectedWorktreeID(in: current, receiver: receiver),
                memberRootsByWorktreeId: topologySnapshot.memberRoots(in: current))
            if case .removed(let desired, _, _) = result {
                try WorkspaceLocalRepositoryStorage.writeChanges(
                    database,
                    change: .init(
                        workspaceID: workspaceId, receiver: receiver, current: current,
                        desired: desired, generation: generation, includeItems: true,
                        forceDependentDeletes: true))
            }
            return (
                try WorkspaceLocalRepositoryStorage.readRecord(database, workspaceID: workspaceId, receiver: receiver),
                result
            )
        }
    }

    func previewBridgeMemberRemoval(
        receiver: BridgeReceiver, worktreeID: UUID,
        contributor: BridgeLinkContributor, topologySnapshot: BridgeReceiverTopologySnapshot
    ) throws -> BridgeMemberContributionRemoval {
        try databaseWriter.read { database in
            try WorkspaceLocalRepositoryStorage.requireActive(database, workspaceID: workspaceId, receiver: receiver)
            let current = try WorkspaceLocalRepositoryStorage.readRecord(
                database, workspaceID: workspaceId, receiver: receiver)
            switch topologySnapshot.ownerDisposition(for: receiver) {
            case .staleOwner: return .staleOwner
            case .staleReceiver: return .staleReceiver
            case .current: break
            }
            if topologySnapshot.validatedCurrentCWDWorktreeID(receiver: receiver) == worktreeID {
                return .refusedProtectedCurrentDirectory
            }
            return BridgeNavigationRules.removingMemberContribution(
                worktreeID,
                contributor: contributor, from: current,
                protectedWorktreeId: topologySnapshot.protectedWorktreeID(in: current, receiver: receiver),
                memberRootsByWorktreeId: topologySnapshot.memberRoots(in: current))
        }
    }

    func commitBridgeCatalogMemberRemoval(
        receiver: BridgeReceiver, worktreeID: UUID, generation: Int,
        removedRoot: String, memberRootsByWorktreeID: [UUID: String]
    ) throws -> (
        record: BridgeNavigationRecord, result: BridgeMemberRemovalOutcome,
        deletedContributors: [BridgeLinkContributor]
    ) {
        try databaseWriter.write { database in
            try WorkspaceLocalRepositoryStorage.requireActive(
                database, workspaceID: workspaceId, receiver: receiver)
            let current = try WorkspaceLocalRepositoryStorage.readRecord(
                database, workspaceID: workspaceId, receiver: receiver)
            var roots = memberRootsByWorktreeID
            roots[worktreeID] = removedRoot
            let result = BridgeNavigationRules.removingMember(
                worktreeID, from: current, reason: .catalogUnregistration,
                memberRootsByWorktreeId: roots)
            var deletedContributors: [BridgeLinkContributor] = []
            if case .removed(let desired, _) = result {
                deletedContributors =
                    current.committedMemberLinks
                    .first(where: { $0.worktreeId == worktreeID })?
                    .contributions.map(\.addedBy) ?? []
                try WorkspaceLocalRepositoryStorage.writeChanges(
                    database,
                    change: .init(
                        workspaceID: workspaceId, receiver: receiver, current: current,
                        desired: desired, generation: generation, includeItems: true,
                        forceDependentDeletes: true))
            }
            return (
                try WorkspaceLocalRepositoryStorage.readRecord(
                    database, workspaceID: workspaceId, receiver: receiver),
                result,
                deletedContributors
            )
        }
    }

    func previewBridgeCatalogMemberRemoval(
        receiver: BridgeReceiver, worktreeID: UUID,
        removedRoot: String, memberRootsByWorktreeID: [UUID: String]
    ) throws -> BridgeMemberRemovalOutcome {
        try databaseWriter.read { database in
            try WorkspaceLocalRepositoryStorage.requireActive(
                database, workspaceID: workspaceId, receiver: receiver)
            let current = try WorkspaceLocalRepositoryStorage.readRecord(
                database, workspaceID: workspaceId, receiver: receiver)
            var roots = memberRootsByWorktreeID
            roots[worktreeID] = removedRoot
            return BridgeNavigationRules.removingMember(
                worktreeID, from: current, reason: .catalogUnregistration,
                memberRootsByWorktreeId: roots)
        }
    }

    func commitBridgePullRequestAddition(
        receiver: BridgeReceiver, identity: ForgePullRequestIdentity,
        contributor: BridgeLinkContributor, generation: Int, addedAt: Date,
        topologySnapshot: BridgeReceiverTopologySnapshot
    ) throws -> (BridgeNavigationRecord, BridgePullRequestReferenceAddResult) {
        try databaseWriter.write { database in
            try WorkspaceLocalRepositoryStorage.requireActive(database, workspaceID: workspaceId, receiver: receiver)
            let current = try WorkspaceLocalRepositoryStorage.readRecord(
                database, workspaceID: workspaceId, receiver: receiver)
            switch topologySnapshot.ownerDisposition(for: receiver) {
            case .staleOwner: return (current, .staleOwner)
            case .staleReceiver: return (current, .staleReceiver)
            case .current: break
            }
            let (desired, result) = BridgeNavigationRules.addingPullRequestContribution(
                identity,
                contributor: contributor, addedAt: addedAt, to: current)
            try WorkspaceLocalRepositoryStorage.writeChanges(
                database,
                change: .init(
                    workspaceID: workspaceId, receiver: receiver, current: current,
                    desired: desired, generation: generation, includeItems: true,
                    forceDependentDeletes: false))
            return (
                try WorkspaceLocalRepositoryStorage.readRecord(database, workspaceID: workspaceId, receiver: receiver),
                result
            )
        }
    }

    func commitBridgePullRequestRemoval(
        receiver: BridgeReceiver, identity: ForgePullRequestIdentity,
        contributor: BridgeLinkContributor, generation: Int,
        topologySnapshot: BridgeReceiverTopologySnapshot
    ) throws -> (BridgeNavigationRecord, BridgePullRequestContributionRemoval) {
        try databaseWriter.write { database in
            try WorkspaceLocalRepositoryStorage.requireActive(database, workspaceID: workspaceId, receiver: receiver)
            let current = try WorkspaceLocalRepositoryStorage.readRecord(
                database, workspaceID: workspaceId, receiver: receiver)
            switch topologySnapshot.ownerDisposition(for: receiver) {
            case .staleOwner: return (current, .staleOwner)
            case .staleReceiver: return (current, .staleReceiver)
            case .current: break
            }
            let result = BridgeNavigationRules.removingPullRequestContribution(
                identity,
                contributor: contributor, from: current)
            if case .removed(let desired, _) = result {
                try WorkspaceLocalRepositoryStorage.writeChanges(
                    database,
                    change: .init(
                        workspaceID: workspaceId, receiver: receiver, current: current,
                        desired: desired, generation: generation, includeItems: true,
                        forceDependentDeletes: false))
            }
            return (
                try WorkspaceLocalRepositoryStorage.readRecord(database, workspaceID: workspaceId, receiver: receiver),
                result
            )
        }
    }

    func retireBridgeReceiver<ClockType: Clock>(
        _ receiver: BridgeReceiver,
        time: BridgeReceiverRetirementTime<ClockType>
    ) throws where ClockType.Duration == Duration {
        try databaseWriter.write { database in
            try WorkspaceLocalRepositoryStorage.retire(
                database, workspaceID: workspaceId, receiver: receiver, now: time.now)
        }
    }

    func purgeRetiredBridgeReceivers<ClockType: Clock>(time: BridgeReceiverRetirementTime<ClockType>) throws
    where ClockType.Duration == Duration {
        try databaseWriter.write { database in
            try WorkspaceLocalRepositoryStorage.purgeDue(database, workspaceID: workspaceId, now: time.now)
        }
    }
}

extension WorkspaceLocalRepositoryStorage {
    static func saveBridgeCurrentValues(
        _ database: Database, workspaceID: UUID,
        records: [BridgeReceiver: BridgeNavigationRecord],
        retainedPaneIDs: Set<UUID>, generation: Int, now: Date
    ) throws {
        let readback = try readBridgeReceivers(database, workspaceID: workspaceID)
        for (receiver, desired) in records where retainedPaneIDs.contains(receiver.paneId) {
            guard try !isRetired(database, workspaceID: workspaceID, receiver: receiver) else {
                continue
            }
            try writeChanges(
                database,
                change: .init(
                    workspaceID: workspaceID, receiver: receiver,
                    current: readback.records[receiver] ?? .empty,
                    desired: desired, generation: generation, includeItems: false,
                    forceDependentDeletes: false))
        }
        for receiver in readback.records.keys where !retainedPaneIDs.contains(receiver.paneId) {
            try retire(database, workspaceID: workspaceID, receiver: receiver, now: now)
        }
        try purgeDue(database, workspaceID: workspaceID, now: now)
    }

    static func isRetired(_ database: Database, workspaceID: UUID, receiver: BridgeReceiver) throws -> Bool {
        try Int.fetchOne(
            database, sql: "SELECT 1 FROM bridge_receiver_retirement WHERE workspace_id = ? AND receiver_pane_id = ?",
            arguments: [workspaceID.uuidString, receiver.paneId.uuidString]) != nil
    }

    static func requireActive(_ database: Database, workspaceID: UUID, receiver: BridgeReceiver) throws {
        if try isRetired(database, workspaceID: workspaceID, receiver: receiver) {
            throw BridgeReceiverStorageError.retiredReceiver
        }
    }

    static func retire(_ database: Database, workspaceID: UUID, receiver: BridgeReceiver, now: Date) throws {
        try database.execute(
            sql: """
                INSERT OR IGNORE INTO bridge_receiver_retirement(workspace_id, receiver_pane_id, retired_at, purge_after)
                VALUES (?, ?, ?, ?)
                """,
            arguments: [
                workspaceID.uuidString, receiver.paneId.uuidString,
                now.timeIntervalSince1970, now.addingTimeInterval(86_400).timeIntervalSince1970,
            ])
    }

    static func purgeDue(_ database: Database, workspaceID: UUID, now: Date) throws {
        let paneIDs = try String.fetchAll(
            database,
            sql: """
                SELECT receiver_pane_id FROM bridge_receiver_retirement
                WHERE workspace_id = ? AND purge_after <= ?
                """, arguments: [workspaceID.uuidString, now.timeIntervalSince1970])
        for paneID in paneIDs {
            for table in ["bridge_receiver_state", "bridge_receiver_item", "bridge_receiver_retirement"] {
                try database.execute(
                    sql: "DELETE FROM \(table) WHERE workspace_id = ? AND receiver_pane_id = ?",
                    arguments: [workspaceID.uuidString, paneID])
            }
        }
    }

    static func readBridgeReceivers(_ database: Database, workspaceID: UUID) throws -> BridgeReceiverReadback {
        let states = try fetchStates(database, workspaceID: workspaceID)
        let items = try fetchItems(database, workspaceID: workspaceID)
        let retired = Set(
            try String.fetchAll(
                database,
                sql: "SELECT receiver_pane_id FROM bridge_receiver_retirement WHERE workspace_id = ?",
                arguments: [workspaceID.uuidString]))
        let receivers = Set(states.map(\.receiver)).union(items.map(\.receiver))
        var records: [BridgeReceiver: BridgeNavigationRecord] = [:]
        for receiver in receivers where !retired.contains(receiver.paneId.uuidString) {
            do {
                records[receiver] = try BridgeReceiverRecordRows.record(
                    states: states.filter { $0.receiver == receiver }, items: items.filter { $0.receiver == receiver })
            } catch {
                // A malformed receiver defaults alone; the row is left intact
                // so a later diagnosis can inspect the original typed columns.
                bridgeReceiverStorageLogger.error("Bridge receiver typed row rejected; receiver defaults")
                continue
            }
        }
        return BridgeReceiverReadback(records: records, presentPaneIDs: Set(receivers.map(\.paneId)))
    }

    static func readRecord(_ database: Database, workspaceID: UUID, receiver: BridgeReceiver) throws
        -> BridgeNavigationRecord
    {
        let states = try fetchStates(database, workspaceID: workspaceID).filter { $0.receiver == receiver }
        let items = try fetchItems(database, workspaceID: workspaceID).filter { $0.receiver == receiver }
        return try BridgeReceiverRecordRows.record(states: states, items: items)
    }

    static func writeChanges(_ database: Database, change: BridgeReceiverWriteChange) throws {
        let workspaceID = change.workspaceID
        let receiver = change.receiver
        let current = change.current
        let desired = change.desired
        let generation = change.generation
        let includeItems = change.includeItems
        let forceDependentDeletes = change.forceDependentDeletes
        let storedStates = Dictionary(
            uniqueKeysWithValues: try fetchStates(database, workspaceID: workspaceID)
                .filter { $0.receiver == receiver }.map { ($0.kind + "\u{1f}" + $0.itemKey, $0) })
        let desiredStates = Dictionary(
            uniqueKeysWithValues: BridgeReceiverRecordRows.states(
                desired,
                receiver: receiver, generation: generation
            ).map { ($0.kind + "\u{1f}" + $0.itemKey, $0) })
        let currentStates = Dictionary(
            uniqueKeysWithValues: BridgeReceiverRecordRows.states(
                current,
                receiver: receiver, generation: generation
            ).map { ($0.kind + "\u{1f}" + $0.itemKey, $0) })
        for key in Set(currentStates.keys).union(desiredStates.keys) {
            let before = currentStates[key]
            let after = desiredStates[key]
            if !includeItems, (after ?? before)?.kind == "itemOrder" { continue }
            let stored = storedStates[key]
            guard before != after || (stored == nil && after != nil) else { continue }
            let effectiveGeneration =
                forceDependentDeletes
                ? max(generation, (stored?.generation ?? -1) + 1) : generation
            guard effectiveGeneration > (stored?.generation ?? -1) else { continue }
            if let after {
                try requireMemberReference(
                    after, members: includeItems ? desired : current,
                    desired: desired)
                try upsertState(
                    database, workspaceID: workspaceID,
                    row: after.withGeneration(effectiveGeneration))
            } else if let before {
                try upsertState(
                    database, workspaceID: workspaceID,
                    row: before.withGeneration(effectiveGeneration, isDeleted: true))
            }
        }
        guard includeItems else { return }
        let storedItems = Dictionary(
            uniqueKeysWithValues: try fetchItems(database, workspaceID: workspaceID)
                .filter { $0.receiver == receiver }.map {
                    ($0.kind + "\u{1f}" + $0.itemKey + "\u{1f}" + $0.contributorKey, $0)
                })
        let desiredItems = Dictionary(
            uniqueKeysWithValues: BridgeReceiverRecordRows.items(
                desired,
                receiver: receiver, generation: generation
            ).map { ($0.kind + "\u{1f}" + $0.itemKey + "\u{1f}" + $0.contributorKey, $0) })
        let currentItems = Dictionary(
            uniqueKeysWithValues: BridgeReceiverRecordRows.items(
                current,
                receiver: receiver, generation: generation
            ).map { ($0.kind + "\u{1f}" + $0.itemKey + "\u{1f}" + $0.contributorKey, $0) })
        for key in Set(currentItems.keys).union(desiredItems.keys) {
            let before = currentItems[key]
            let after = desiredItems[key]
            guard before != after else { continue }
            let stored = storedItems[key]
            guard generation > (stored?.generation ?? -1) else { throw BridgeReceiverStorageError.staleGeneration }
            if let after {
                try upsertItem(database, workspaceID: workspaceID, row: after)
            } else if let before {
                try upsertItem(
                    database, workspaceID: workspaceID,
                    row: before.withGeneration(generation, isDeleted: true))
            }
        }
    }

    private static func requireMemberReference(
        _ row: BridgeReceiverStateRow,
        members: BridgeNavigationRecord, desired: BridgeNavigationRecord
    ) throws {
        let referenced: UUID?
        switch row.kind {
        case "filesFilter", "reviewSelection": referenced = row.worktreeID
        case "reviewComparison": referenced = row.worktreeID
        case "openedDocument": referenced = row.provenanceWorktreeID
        default: referenced = nil
        }
        if let referenced, !members.containsMember(referenced) {
            throw BridgeReceiverStorageError.missingMemberReference
        }
        if row.kind == "selectedFilesDocument", let path = row.documentPath,
            let selected = BridgeDocumentLocation(canonicalPath: path)
        {
            guard let document = desired.openedDocument(at: selected) else {
                throw BridgeReceiverStorageError.malformedRow("selection outside inventory")
            }
            if let worktreeID = document.provenance?.worktreeId,
                !members.containsMember(worktreeID)
            {
                throw BridgeReceiverStorageError.missingMemberReference
            }
        }
    }

    private static func upsertState(_ database: Database, workspaceID: UUID, row: BridgeReceiverStateRow) throws {
        try database.execute(
            sql: """
                INSERT INTO bridge_receiver_state (
                    workspace_id, receiver_pane_id, receiver_kind, kind, item_key, generation, is_deleted,
                    text_value, worktree_id, forge_host, forge_owner, forge_repository, forge_number,
                    document_path, provenance_repo_id, provenance_worktree_id,
                    provenance_relative_path, comparison_kind, comparison_basis, comparison_name,
                    comparison_branch, comparison_remote, comparison_oid, ordinal, imported_variant, imported_payload
                ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(workspace_id, receiver_pane_id, kind, item_key) DO UPDATE SET
                    receiver_kind=excluded.receiver_kind, generation=excluded.generation,
                    is_deleted=excluded.is_deleted, text_value=excluded.text_value,
                    worktree_id=excluded.worktree_id, forge_host=excluded.forge_host,
                    forge_owner=excluded.forge_owner, forge_repository=excluded.forge_repository,
                    forge_number=excluded.forge_number, document_path=excluded.document_path,
                    provenance_repo_id=excluded.provenance_repo_id,
                    provenance_worktree_id=excluded.provenance_worktree_id,
                    provenance_relative_path=excluded.provenance_relative_path,
                    comparison_kind=excluded.comparison_kind, comparison_basis=excluded.comparison_basis,
                    comparison_name=excluded.comparison_name, comparison_branch=excluded.comparison_branch,
                    comparison_remote=excluded.comparison_remote, comparison_oid=excluded.comparison_oid,
                    ordinal=excluded.ordinal, imported_variant=excluded.imported_variant,
                    imported_payload=excluded.imported_payload
                WHERE excluded.generation > bridge_receiver_state.generation
                """,
            arguments: [
                workspaceID.uuidString, row.receiver.paneId.uuidString, row.receiver.kind.rawValue,
                row.kind, row.itemKey, row.generation, row.isDeleted ? 1 : 0, row.textValue,
                row.worktreeID?.uuidString, row.forgeHost, row.forgeOwner,
                row.forgeRepository, row.forgeNumber, row.documentPath, row.provenanceRepoID?.uuidString,
                row.provenanceWorktreeID?.uuidString, row.provenanceRelativePath, row.comparisonKind,
                row.comparisonBasis, row.comparisonName, row.comparisonBranch, row.comparisonRemote,
                row.comparisonOID, row.ordinal, row.importedVariant, row.importedPayload,
            ])
    }

    private static func upsertItem(_ database: Database, workspaceID: UUID, row: BridgeReceiverItemRow) throws {
        try database.execute(
            sql: """
                INSERT INTO bridge_receiver_item (
                    workspace_id, receiver_pane_id, receiver_kind, kind, item_key, contributor_key,
                    generation, is_deleted, worktree_id, forge_host, forge_owner, forge_repository,
                    forge_number, contributor_kind, contributor_provider, contributor_session_ref, added_at
                ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(workspace_id, receiver_pane_id, kind, item_key, contributor_key) DO UPDATE SET
                    receiver_kind=excluded.receiver_kind, generation=excluded.generation,
                    is_deleted=excluded.is_deleted, worktree_id=excluded.worktree_id,
                    forge_host=excluded.forge_host, forge_owner=excluded.forge_owner,
                    forge_repository=excluded.forge_repository, forge_number=excluded.forge_number,
                    contributor_kind=excluded.contributor_kind,
                    contributor_provider=excluded.contributor_provider,
                    contributor_session_ref=excluded.contributor_session_ref, added_at=excluded.added_at
                WHERE excluded.generation > bridge_receiver_item.generation
                """,
            arguments: [
                workspaceID.uuidString, row.receiver.paneId.uuidString, row.receiver.kind.rawValue,
                row.kind, row.itemKey, row.contributorKey, row.generation, row.isDeleted ? 1 : 0,
                row.worktreeID?.uuidString, row.forgeHost, row.forgeOwner, row.forgeRepository,
                row.forgeNumber, row.contributorKind, row.contributorProvider,
                row.contributorSessionRef, row.addedAt?.timeIntervalSince1970,
            ])
    }

    private static func fetchStates(_ database: Database, workspaceID: UUID) throws -> [BridgeReceiverStateRow] {
        let rows = try Row.fetchAll(
            database,
            sql: "SELECT * FROM bridge_receiver_state WHERE workspace_id = ?", arguments: [workspaceID.uuidString])
        return try rows.map { stored in
            let receiver = try decodeReceiver(stored)
            let deleted: Int = stored["is_deleted"]
            var row = BridgeReceiverStateRow(
                receiver: receiver, kind: stored["kind"],
                itemKey: stored["item_key"], generation: stored["generation"], isDeleted: deleted == 1)
            row.textValue = stored["text_value"]
            row.worktreeID = try optionalUUID(stored["worktree_id"])
            row.forgeHost = stored["forge_host"]
            row.forgeOwner = stored["forge_owner"]
            row.forgeRepository = stored["forge_repository"]
            row.forgeNumber = stored["forge_number"]
            row.documentPath = stored["document_path"]
            row.provenanceRepoID = try optionalUUID(stored["provenance_repo_id"])
            row.provenanceWorktreeID = try optionalUUID(stored["provenance_worktree_id"])
            row.provenanceRelativePath = stored["provenance_relative_path"]
            row.comparisonKind = stored["comparison_kind"]
            row.comparisonBasis = stored["comparison_basis"]
            row.comparisonName = stored["comparison_name"]
            row.comparisonBranch = stored["comparison_branch"]
            row.comparisonRemote = stored["comparison_remote"]
            row.comparisonOID = stored["comparison_oid"]
            row.ordinal = stored["ordinal"]
            row.importedVariant = stored["imported_variant"]
            row.importedPayload = stored["imported_payload"]
            return row
        }
    }

    private static func fetchItems(_ database: Database, workspaceID: UUID) throws -> [BridgeReceiverItemRow] {
        let rows = try Row.fetchAll(
            database,
            sql: "SELECT * FROM bridge_receiver_item WHERE workspace_id = ?", arguments: [workspaceID.uuidString])
        return try rows.map { stored in
            let receiver = try decodeReceiver(stored)
            let deleted: Int = stored["is_deleted"]
            var row = BridgeReceiverItemRow(
                receiver: receiver, kind: stored["kind"],
                itemKey: stored["item_key"], contributorKey: stored["contributor_key"],
                generation: stored["generation"], isDeleted: deleted == 1)
            row.worktreeID = try optionalUUID(stored["worktree_id"])
            row.forgeHost = stored["forge_host"]
            row.forgeOwner = stored["forge_owner"]
            row.forgeRepository = stored["forge_repository"]
            row.forgeNumber = stored["forge_number"]
            row.contributorKind = stored["contributor_kind"]
            row.contributorProvider = stored["contributor_provider"]
            row.contributorSessionRef = stored["contributor_session_ref"]
            let addedAt: Double? = stored["added_at"]
            row.addedAt = addedAt.map(Date.init(timeIntervalSince1970:))
            return row
        }
    }

    private static func decodeReceiver(_ stored: Row) throws -> BridgeReceiver {
        let paneIDText: String = stored["receiver_pane_id"]
        let kindText: String = stored["receiver_kind"]
        guard let paneID = UUID(uuidString: paneIDText), let kind = BridgeReceiverKind(rawValue: kindText) else {
            throw BridgeReceiverStorageError.malformedRow("receiver")
        }
        return BridgeReceiver(paneId: paneID, kind: kind)
    }

    private static func optionalUUID(_ text: String?) throws -> UUID? {
        guard let text else { return nil }
        guard let id = UUID(uuidString: text) else { throw BridgeReceiverStorageError.malformedRow("UUID") }
        return id
    }
}
