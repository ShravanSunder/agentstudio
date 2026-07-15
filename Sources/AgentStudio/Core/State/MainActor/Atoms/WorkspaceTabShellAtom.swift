import Foundation
import Observation
import os.log

private let workspaceTabShellLogger = Logger(subsystem: "com.agentstudio", category: "WorkspaceTabShellAtom")

enum WorkspaceTabShellAtomError: Error, Equatable {
    case tabNotFound(UUID)
    case invalidTabColorHex(String)
}

enum WorkspaceTabShellPersistenceOperation: Equatable, Sendable {
    case insert(TabShell, at: Int)
    case update(TabShell)
    case remove(tabID: UUID)
    case move(tabID: UUID, toIndex: Int)
}

enum WorkspaceTabShellPersistencePreparationError: Error, Equatable {
    case duplicateTabID(UUID)
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
    let tabIndexByID: [UUID: Int]
}

@MainActor
@Observable
final class WorkspaceTabShellAtom {
    let cursorAtom: WorkspaceTabCursorAtom
    private(set) var tabShells: [TabShell] = []
    private var tabIndexByID: [UUID: Int] = [:]
    private let snapshotParticipant = WorkspaceStateSnapshotKeyedParticipant<
        UUID,
        WorkspacePersistenceSnapshotTabShell
    >()

    init(cursorAtom: WorkspaceTabCursorAtom = WorkspaceTabCursorAtom()) {
        self.cursorAtom = cursorAtom
    }

    var activeTabId: UUID? {
        cursorAtom.activeTabId
    }

    func hydrate(persistedTabs: [Tab], activeTabId: UUID?) {
        tabShells = persistedTabs.map { TabShell(id: $0.id, name: $0.name, colorHex: $0.colorHex) }
        rebuildTabIndex()
        cursorAtom.hydrate(activeTabId: activeTabId, availableTabIds: tabShells.map(\.id))
    }

    func tabShell(_ id: UUID) -> TabShell? {
        tabIndexByID[id].map { tabShells[$0] }
    }

    func tabIndex(for tabID: UUID) -> Int? {
        tabIndexByID[tabID]
    }

    func appendTabShell(_ shell: TabShell) {
        guard tabIndexByID[shell.id] == nil else { return }
        tabShells.append(shell)
        tabIndexByID[shell.id] = tabShells.count - 1
        cursorAtom.selectTab(shell.id, availableTabIds: tabShells.map(\.id))
    }

    func removeTabShell(_ tabId: UUID) {
        guard let removedIndex = tabIndexByID.removeValue(forKey: tabId) else { return }
        tabShells.remove(at: removedIndex)
        reindexTabs(in: removedIndex..<tabShells.count)
        cursorAtom.removeTab(tabId, remainingTabIds: tabShells.map(\.id))
    }

    func insertTabShell(_ shell: TabShell, at index: Int) {
        guard tabIndexByID[shell.id] == nil else { return }
        let clampedIndex = min(index, tabShells.count)
        tabShells.insert(shell, at: clampedIndex)
        reindexTabs(in: clampedIndex..<tabShells.count)
    }

    func moveTab(fromId: UUID, toIndex: Int) {
        guard let fromIndex = tabIndexByID[fromId] else {
            workspaceTabShellLogger.warning("moveTab: tab \(fromId) not found")
            return
        }
        let shell = tabShells.remove(at: fromIndex)
        let adjustedIndex = toIndex > fromIndex ? toIndex - 1 : toIndex
        let clampedIndex = max(0, min(adjustedIndex, tabShells.count))
        tabShells.insert(shell, at: clampedIndex)
        reindexTabs(in: min(fromIndex, clampedIndex)..<tabShells.count)
    }

    func moveTabByDelta(tabId: UUID, delta: Int) {
        guard let fromIndex = tabIndexByID[tabId] else {
            workspaceTabShellLogger.warning("moveTabByDelta: tab \(tabId) not found")
            return
        }
        let count = tabShells.count
        guard count > 1 else { return }

        let finalIndex: Int
        if delta < 0 {
            let magnitude = delta == Int.min ? Int.max : -delta
            finalIndex = fromIndex - min(fromIndex, magnitude)
        } else {
            let remaining = count - 1 - fromIndex
            finalIndex = fromIndex + min(remaining, delta)
        }
        guard finalIndex != fromIndex else { return }

        let shell = tabShells.remove(at: fromIndex)
        tabShells.insert(shell, at: finalIndex)
        reindexTabs(in: min(fromIndex, finalIndex)..<tabShells.count)
    }

    func setActiveTab(_ tabId: UUID?) {
        cursorAtom.selectTab(tabId, availableTabIds: tabShells.map(\.id))
    }

    func renameTab(_ tabId: UUID, name: String) {
        guard let tabIndex = tabIndexByID[tabId] else {
            workspaceTabShellLogger.warning("renameTab: tab \(tabId) not found")
            return
        }
        guard !Tab.normalizedName(name).isEmpty else {
            workspaceTabShellLogger.warning("renameTab: empty name rejected for tab \(tabId)")
            return
        }
        guard tabShells[tabIndex].name != Tab.normalizedName(name) else { return }
        tabShells[tabIndex].rename(to: name)
    }

    func setTabColorHex(_ colorHex: String?, tabId: UUID) throws {
        guard let tabIndex = tabIndexByID[tabId] else {
            throw WorkspaceTabShellAtomError.tabNotFound(tabId)
        }
        let canonicalColorHex = try colorHex.map(Self.validatedTabColorHex(_:))
        guard tabShells[tabIndex].colorHex != canonicalColorHex else { return }
        tabShells[tabIndex].setColorHex(canonicalColorHex)
    }

    func makePersistenceSnapshotParticipant(
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
            orderedBaseKeys: { [self] in tabShells.map(\.id) },
            currentValue: { [self] tabID in
                guard let index = tabIndexByID[tabID] else { return .absent }
                return .value(
                    WorkspacePersistenceSnapshotTabShell(
                        shell: tabShells[index],
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
        for preparation: WorkspacePersistenceTransactionPreparation,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) throws {
        var nextTabShells = tabShells
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

        let nextTabIndexByID = try Self.makeUniqueIndex(nextTabShells)
        var snapshotMutations: [WorkspaceStateSnapshotParticipantMutation<UUID, WorkspacePersistenceSnapshotTabShell>] =
            []
        snapshotMutations.reserveCapacity(tabShells.count + nextTabShells.count)
        for (oldIndex, oldShell) in tabShells.enumerated() {
            let oldValue = WorkspacePersistenceSnapshotTabShell(shell: oldShell, sortIndex: oldIndex)
            guard let nextIndex = nextTabIndexByID[oldShell.id] else {
                snapshotMutations.append(
                    .remove(.init(key: oldShell.id, currentValue: .value(oldValue)))
                )
                continue
            }
            if nextIndex != oldIndex || nextTabShells[nextIndex] != oldShell {
                snapshotMutations.append(.replaceValue(key: oldShell.id, currentValue: .value(oldValue)))
            }
        }
        for shell in nextTabShells where tabIndexByID[shell.id] == nil {
            snapshotMutations.append(.insert(.init(key: shell.id, rawKeyByteCount: 16)))
        }

        try prepareSnapshotParticipant(
            snapshotMutations,
            preparation: preparation,
            revisionOwner: revisionOwner
        )
        let preparedMutation = WorkspaceTabShellPreparedPersistenceMutation(
            transaction: preparation.transaction,
            tabShells: nextTabShells,
            tabIndexByID: nextTabIndexByID
        )
        switch revisionOwner.registerPreparedParticipantMutation(
            participant: self,
            preparation: preparation,
            apply: { [self] in applyPreparedPersistenceMutation(preparedMutation, revisionOwner: revisionOwner) },
            cancel: {}
        ) {
        case .registered:
            break
        case .rejected(let rejection):
            throw WorkspaceTabShellPersistencePreparationError.ownerRegistration(rejection)
        }
    }

    private func prepareSnapshotParticipant(
        _ mutations: [WorkspaceStateSnapshotParticipantMutation<UUID, WorkspacePersistenceSnapshotTabShell>],
        preparation: WorkspacePersistenceTransactionPreparation,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) throws {
        guard !mutations.isEmpty else { return }
        switch snapshotParticipant.prepare(mutations, for: preparation, revisionOwner: revisionOwner) {
        case .prepared:
            break
        case .rejected(let rejection):
            throw WorkspaceTabShellPersistencePreparationError.snapshotPreparation(rejection)
        }
    }

    private func applyPreparedPersistenceMutation(
        _ mutation: WorkspaceTabShellPreparedPersistenceMutation,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) {
        precondition(
            revisionOwner.validateActiveCommit(mutation.transaction) == .active,
            "tab shell prepared mutation requires its exact active transaction"
        )
        tabShells = mutation.tabShells
        tabIndexByID = mutation.tabIndexByID
    }

    private func rebuildTabIndex() {
        tabIndexByID = Dictionary(uniqueKeysWithValues: tabShells.enumerated().map { ($0.element.id, $0.offset) })
    }

    private func reindexTabs(in range: Range<Int>) {
        for index in range { tabIndexByID[tabShells[index].id] = index }
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

    private static func validatedTabColorHex(_ colorHex: String) throws -> String {
        let canonicalColorHex = colorHex.uppercased()
        guard canonicalColorHex.range(of: "^#[0-9A-F]{6}$", options: .regularExpression) != nil else {
            throw WorkspaceTabShellAtomError.invalidTabColorHex(colorHex)
        }
        return canonicalColorHex
    }
}
