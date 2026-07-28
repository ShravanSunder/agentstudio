import Foundation

package enum WorkspacePaneRecencyEligibility {
    package static func isEligibleForRecording(
        pane: Pane?,
        workspaceMatches: Bool,
        tabs: [Tab],
        targetableTabID: UUID?
    ) -> Bool {
        guard workspaceMatches else { return false }
        guard
            let pane,
            pane.residency == .active,
            pane.parentPaneId == nil
        else {
            return false
        }

        let canonicalTabs = tabs.filter { $0.activePaneIds.contains(pane.id) }
        guard canonicalTabs.count == 1, let canonicalTab = canonicalTabs.first else {
            return false
        }
        return targetableTabID == canonicalTab.id
    }
}
