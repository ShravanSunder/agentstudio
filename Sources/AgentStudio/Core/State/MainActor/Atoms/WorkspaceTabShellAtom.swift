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

    init(cursorAtom: WorkspaceTabCursorAtom = WorkspaceTabCursorAtom()) {
        self.cursorAtom = cursorAtom
    }

    var activeTabId: UUID? {
        cursorAtom.activeTabId
    }

    func hydrate(persistedTabs: [Tab], activeTabId: UUID?) {
        tabShells = persistedTabs.map { TabShell(id: $0.id, name: $0.name, colorHex: $0.colorHex) }
        cursorAtom.hydrate(activeTabId: activeTabId, availableTabIds: tabShells.map(\.id))
    }

    func tabShell(_ id: UUID) -> TabShell? {
        tabShells.first { $0.id == id }
    }

    func appendTabShell(_ shell: TabShell) {
        tabShells.append(shell)
        cursorAtom.selectTab(shell.id, availableTabIds: tabShells.map(\.id))
    }

    func removeTabShell(_ tabId: UUID) {
        tabShells.removeAll { $0.id == tabId }
        cursorAtom.removeTab(tabId, remainingTabIds: tabShells.map(\.id))
    }

    func insertTabShell(_ shell: TabShell, at index: Int) {
        let clampedIndex = min(index, tabShells.count)
        tabShells.insert(shell, at: clampedIndex)
    }

    func moveTab(fromId: UUID, toIndex: Int) {
        guard let fromIndex = tabShells.firstIndex(where: { $0.id == fromId }) else {
            workspaceTabShellLogger.warning("moveTab: tab \(fromId) not found")
            return
        }
        let shell = tabShells.remove(at: fromIndex)
        let adjustedIndex = toIndex > fromIndex ? toIndex - 1 : toIndex
        let clampedIndex = max(0, min(adjustedIndex, tabShells.count))
        tabShells.insert(shell, at: clampedIndex)
    }

    func moveTabByDelta(tabId: UUID, delta: Int) {
        guard let fromIndex = tabShells.firstIndex(where: { $0.id == tabId }) else {
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
    }

    func setActiveTab(_ tabId: UUID?) {
        cursorAtom.selectTab(tabId, availableTabIds: tabShells.map(\.id))
    }

    func renameTab(_ tabId: UUID, name: String) {
        guard let tabIndex = tabShells.firstIndex(where: { $0.id == tabId }) else {
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
        guard let tabIndex = tabShells.firstIndex(where: { $0.id == tabId }) else {
            throw WorkspaceTabShellAtomError.tabNotFound(tabId)
        }
        let canonicalColorHex = try colorHex.map(Self.validatedTabColorHex(_:))
        guard tabShells[tabIndex].colorHex != canonicalColorHex else { return }
        tabShells[tabIndex].setColorHex(canonicalColorHex)
    }

    private static func validatedTabColorHex(_ colorHex: String) throws -> String {
        let canonicalColorHex = colorHex.uppercased()
        guard canonicalColorHex.range(of: "^#[0-9A-F]{6}$", options: .regularExpression) != nil else {
            throw WorkspaceTabShellAtomError.invalidTabColorHex(colorHex)
        }
        return canonicalColorHex
    }
}
