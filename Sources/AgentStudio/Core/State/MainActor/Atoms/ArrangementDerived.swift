import Foundation
import os.log

private let arrangementDerivedLogger = Logger(subsystem: "com.agentstudio", category: "ArrangementDerived")

@MainActor
struct ArrangementDerived {
    static func nextCustomArrangementName(existing: [PaneArrangement]) -> String {
        let existingNames = Set(existing.map(\.name))
        var index = 1
        while existingNames.contains("Layout \(index)") {
            index += 1
        }
        return "Layout \(index)"
    }

    func paneVisibilityItems(for tabId: UUID) -> [PaneVisibilityInfo] {
        let workspaceTab = atom(\.workspaceTab)
        let paneDisplay = atom(\.paneDisplay)
        guard let tab = workspaceTab.tab(tabId) else {
            arrangementDerivedLogger.warning("paneVisibilityItems: tab \(tabId) not found")
            return []
        }

        return tab.activePaneIds.map { paneId in
            PaneVisibilityInfo(
                id: paneId,
                title: paneDisplay.displayLabel(for: paneId),
                isMinimized: tab.activeMinimizedPaneIds.contains(paneId)
            )
        }
    }

    func arrangementItems(for tabId: UUID) -> [ArrangementInfo] {
        let workspaceTab = atom(\.workspaceTab)
        guard let tab = workspaceTab.tab(tabId) else {
            arrangementDerivedLogger.warning("arrangementItems: tab \(tabId) not found")
            return []
        }

        return tab.arrangements.map { arrangement in
            ArrangementInfo(
                id: arrangement.id,
                name: arrangement.name,
                isDefault: arrangement.isDefault,
                isActive: arrangement.id == tab.activeArrangementId
            )
        }
    }

    func nextCustomArrangementName(for tabId: UUID) -> String? {
        let workspaceTab = atom(\.workspaceTab)
        guard let tab = workspaceTab.tab(tabId) else {
            arrangementDerivedLogger.warning("nextCustomArrangementName: tab \(tabId) not found")
            return nil
        }
        return Self.nextCustomArrangementName(existing: tab.arrangements)
    }
}
