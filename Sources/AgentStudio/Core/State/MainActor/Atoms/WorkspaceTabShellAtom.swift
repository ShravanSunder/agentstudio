import AgentStudioInfrastructure
import Foundation
import Observation
import os.log

private let workspaceTabShellLogger = Logger(subsystem: "com.agentstudio", category: "WorkspaceTabShellAtom")

enum WorkspaceTabShellAtomError: Error, Equatable {
    case tabNotFound(UUID)
    case invalidTabColorHex(String)
}

@MainActor
@Observable
package final class WorkspaceTabShellAtom {
    let cursorAtom: WorkspaceTabCursorAtom
    @ObservationIgnored private let shellFamily = AtomFamily<UUID, TabShell>(
        telemetryLabel: "workspace_tab_shell",
        isContentEqual: ==
    )
    @ObservationIgnored private let acceptedCommitRevision = AtomRevision()
    private var tabOrder: [UUID] = []
    private var tabIndexByID: [UUID: Int] = [:]

    package init(cursorAtom: WorkspaceTabCursorAtom = WorkspaceTabCursorAtom()) {
        self.cursorAtom = cursorAtom
    }

    package var activeTabId: UUID? {
        cursorAtom.activeTabId
    }

    package var orderedTabIds: [UUID] {
        tabOrder
    }

    var tabShells: [TabShell] {
        tabOrder.compactMap { shellFamily.value(for: $0) }
    }

    var tabCount: Int {
        tabOrder.count
    }

    func containsTab(_ id: UUID) -> Bool {
        tabIndexByID[id] != nil
    }

    func replaceTabShells(_ shells: [TabShell]) {
        let replacementIndex = Self.makeUniqueIndex(shells)
        guard tabShells != shells else { return }
        let mutation = AtomMutationContext(aggregateRevision: acceptedCommitRevision)
        shellFamily.replaceAll(
            Dictionary(uniqueKeysWithValues: shells.map { ($0.id, $0) }),
            mutation: mutation
        )
        tabOrder = shells.map(\.id)
        tabIndexByID = replacementIndex
        mutation.commit()
    }

    func tabShell(_ id: UUID) -> TabShell? {
        shellFamily.value(for: id)
    }

    func tabIndex(for tabID: UUID) -> Int? {
        tabIndexByID[tabID]
    }

    func appendTabShell(_ shell: TabShell) {
        guard tabIndexByID[shell.id] == nil else { return }
        let mutation = AtomMutationContext(aggregateRevision: acceptedCommitRevision)
        shellFamily.setValue(shell, for: shell.id, mutation: mutation)
        tabOrder.append(shell.id)
        tabIndexByID[shell.id] = tabOrder.count - 1
        mutation.commit()
        cursorAtom.selectTab(shell.id, availableTabIds: tabOrder)
    }

    func removeTabShell(_ tabId: UUID) {
        guard let removedIndex = tabIndexByID.removeValue(forKey: tabId) else { return }
        tabOrder.remove(at: removedIndex)
        reindexTabs(in: removedIndex..<tabOrder.count)
        let mutation = AtomMutationContext(aggregateRevision: acceptedCommitRevision)
        shellFamily.removeValue(for: tabId, mutation: mutation)
        mutation.commit()
        cursorAtom.removeTab(tabId, remainingTabIds: tabOrder)
    }

    func insertTabShell(_ shell: TabShell, at index: Int) {
        guard tabIndexByID[shell.id] == nil else { return }
        let clampedIndex = min(index, tabOrder.count)
        let mutation = AtomMutationContext(aggregateRevision: acceptedCommitRevision)
        shellFamily.setValue(shell, for: shell.id, mutation: mutation)
        tabOrder.insert(shell.id, at: clampedIndex)
        reindexTabs(in: clampedIndex..<tabOrder.count)
        mutation.commit()
    }

    func moveTab(fromId: UUID, insertionIndex: Int) {
        guard let fromIndex = tabIndexByID[fromId] else {
            workspaceTabShellLogger.warning("moveTab: tab \(fromId) not found")
            return
        }
        let tabId = tabOrder.remove(at: fromIndex)
        let adjustedIndex = insertionIndex > fromIndex ? insertionIndex - 1 : insertionIndex
        let clampedIndex = max(0, min(adjustedIndex, tabOrder.count))
        tabOrder.insert(tabId, at: clampedIndex)
        reindexTabs(in: min(fromIndex, clampedIndex)..<tabOrder.count)
    }

    func moveTabByDelta(tabId: UUID, delta: Int) {
        guard let fromIndex = tabIndexByID[tabId] else {
            workspaceTabShellLogger.warning("moveTabByDelta: tab \(tabId) not found")
            return
        }
        let count = tabOrder.count
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

        let movedTabId = tabOrder.remove(at: fromIndex)
        tabOrder.insert(movedTabId, at: finalIndex)
        reindexTabs(in: min(fromIndex, finalIndex)..<tabOrder.count)
    }

    func setActiveTab(_ tabId: UUID?) {
        cursorAtom.selectTab(tabId, availableTabIds: tabOrder)
    }

    func renameTab(_ tabId: UUID, name: String) {
        guard var shell = shellFamily.snapshotValue(for: tabId) else {
            workspaceTabShellLogger.warning("renameTab: tab \(tabId) not found")
            return
        }
        guard !Tab.normalizedName(name).isEmpty else {
            workspaceTabShellLogger.warning("renameTab: empty name rejected for tab \(tabId)")
            return
        }
        guard shell.name != Tab.normalizedName(name) else { return }
        shell.rename(to: name)
        let mutation = AtomMutationContext(aggregateRevision: acceptedCommitRevision)
        shellFamily.setValue(shell, for: tabId, mutation: mutation)
        mutation.commit()
    }

    func setTabColorHex(_ colorHex: String?, tabId: UUID) throws {
        guard var shell = shellFamily.snapshotValue(for: tabId) else {
            throw WorkspaceTabShellAtomError.tabNotFound(tabId)
        }
        let canonicalColorHex = try colorHex.map(Self.validatedTabColorHex(_:))
        guard shell.colorHex != canonicalColorHex else { return }
        shell.setColorHex(canonicalColorHex)
        let mutation = AtomMutationContext(aggregateRevision: acceptedCommitRevision)
        shellFamily.setValue(shell, for: tabId, mutation: mutation)
        mutation.commit()
    }

    private func reindexTabs(in range: Range<Int>) {
        for index in range { tabIndexByID[tabOrder[index]] = index }
    }

    private static func makeUniqueIndex(_ shells: [TabShell]) -> [UUID: Int] {
        var indexByID: [UUID: Int] = [:]
        indexByID.reserveCapacity(shells.count)
        for (index, shell) in shells.enumerated() {
            precondition(
                indexByID.updateValue(index, forKey: shell.id) == nil,
                "tab shell identity must be unique"
            )
        }
        return indexByID
    }

    private static func validatedTabColorHex(_ colorHex: String) throws -> String {
        let canonicalColorHex = colorHex.uppercased()
        guard canonicalColorHex.range(of: "^#[0-9A-F]{6}$", options: .regularExpression) != nil else {
            throw WorkspaceTabShellAtomError.invalidTabColorHex(colorHex)
        }
        return canonicalColorHex
    }
}
