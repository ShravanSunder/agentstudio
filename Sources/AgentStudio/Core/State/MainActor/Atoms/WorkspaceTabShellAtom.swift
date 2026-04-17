import Foundation
import Observation
import os.log

private let workspaceTabShellLogger = Logger(subsystem: "com.agentstudio", category: "WorkspaceTabShellAtom")

@MainActor
@Observable
final class WorkspaceTabShellAtom {
    private(set) var tabShells: [TabShell] = []
    private(set) var activeTabId: UUID?

    func hydrate(persistedTabs: [Tab], activeTabId: UUID?) {
        tabShells = persistedTabs.map { TabShell(id: $0.id, name: $0.name) }
        self.activeTabId = activeTabId
        if self.activeTabId == nil || !tabShells.contains(where: { $0.id == self.activeTabId }) {
            self.activeTabId = tabShells.first?.id
        }
    }

    func tabShell(_ id: UUID) -> TabShell? {
        tabShells.first { $0.id == id }
    }

    func appendTabShell(_ shell: TabShell) {
        tabShells.append(shell)
        activeTabId = shell.id
    }

    func removeTabShell(_ tabId: UUID) {
        tabShells.removeAll { $0.id == tabId }
        if activeTabId == tabId {
            activeTabId = tabShells.last?.id
        }
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
        activeTabId = tabId
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
}
