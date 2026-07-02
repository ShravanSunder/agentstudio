import Foundation
import os.log

@MainActor
struct WorkspaceTabLayoutDerived {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "WorkspaceTabLayoutDerived")
    let shellAtom: WorkspaceTabShellAtom
    let arrangementAtom: WorkspaceTabArrangementAtom

    init(shellAtom: WorkspaceTabShellAtom, arrangementAtom: WorkspaceTabArrangementAtom) {
        self.shellAtom = shellAtom
        self.arrangementAtom = arrangementAtom
    }

    static func assembleTab(shell: TabShell, arrangementState: TabArrangementState) -> Tab {
        Tab(
            id: shell.id,
            name: shell.name,
            allPaneIds: arrangementState.allPaneIds,
            arrangements: arrangementState.arrangements,
            activeArrangementId: arrangementState.activeArrangementId,
            colorHex: shell.colorHex,
            zoomedPaneId: arrangementState.zoomedPaneId
        )
    }

    var tabs: [Tab] {
        shellAtom.tabShells.compactMap { shell in
            guard let arrangementState = arrangementAtom.arrangementState(shell.id) else {
                Self.logger.warning("tabs: missing arrangement state for shell \(shell.id)")
                return nil
            }
            return Self.assembleTab(shell: shell, arrangementState: arrangementState)
        }
    }

    var activeTab: Tab? {
        guard let activeTabId = shellAtom.activeTabId else { return nil }
        return tab(activeTabId)
    }

    func tab(_ id: UUID) -> Tab? {
        guard let shell = shellAtom.tabShell(id), let arrangementState = arrangementAtom.arrangementState(id) else {
            return nil
        }
        return Self.assembleTab(shell: shell, arrangementState: arrangementState)
    }

    func tabContaining(paneId: UUID) -> Tab? {
        guard let arrangementState = arrangementAtom.tabContaining(paneId: paneId),
            let shell = shellAtom.tabShell(arrangementState.tabId)
        else {
            return nil
        }
        return Self.assembleTab(shell: shell, arrangementState: arrangementState)
    }

    var allPaneIds: Set<UUID> {
        arrangementAtom.allPaneIds
    }

    var activePaneIds: Set<UUID> {
        Set(activeTab?.activePaneIds ?? [])
    }
}
