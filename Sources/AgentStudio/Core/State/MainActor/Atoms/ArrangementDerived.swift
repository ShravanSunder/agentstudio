import Foundation
import os.log

private let arrangementDerivedLogger = Logger(subsystem: "com.agentstudio", category: "ArrangementDerived")

@MainActor
struct ArrangementDerived {
    func paneVisibilityItems(for tabId: UUID) -> [PaneVisibilityInfo] {
        let tabLayout = atom(\.workspaceTabLayout)
        let paneDisplay = atom(\.paneDisplay)
        guard let tab = tabLayout.tab(tabId) else {
            arrangementDerivedLogger.warning("paneVisibilityItems: tab \(tabId) not found")
            return []
        }

        return tab.activePaneIds.map { paneId in
            PaneVisibilityInfo(
                id: paneId,
                title: paneDisplay.displayLabel(for: paneId),
                isMinimized: tab.minimizedPaneIds.contains(paneId)
            )
        }
    }

    func arrangementItems(for tabId: UUID) -> [ArrangementInfo] {
        let tabLayout = atom(\.workspaceTabLayout)
        guard let tab = tabLayout.tab(tabId) else {
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
}
