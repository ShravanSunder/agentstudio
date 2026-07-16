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
final class WorkspaceTabShellAtom {
    let cursorAtom: WorkspaceTabCursorAtom
    private(set) var tabShells: [TabShell] = []
    private var tabIndexByID: [UUID: Int] = [:]
    init(cursorAtom: WorkspaceTabCursorAtom = WorkspaceTabCursorAtom()) {
        self.cursorAtom = cursorAtom
    }

    var activeTabId: UUID? {
        cursorAtom.activeTabId
    }

    func replaceTabShells(_ shells: [TabShell]) {
        let replacementIndex = Self.makeUniqueIndex(shells)
        guard tabShells != shells else { return }
        tabShells = shells
        tabIndexByID = replacementIndex
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

    private func reindexTabs(in range: Range<Int>) {
        for index in range { tabIndexByID[tabShells[index].id] = index }
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
