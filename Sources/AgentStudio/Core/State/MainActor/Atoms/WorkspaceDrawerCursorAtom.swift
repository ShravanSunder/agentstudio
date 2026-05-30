import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceDrawerCursorAtom {
    private(set) var expandedDrawerId: UUID?

    func isExpanded(drawerId: UUID) -> Bool {
        expandedDrawerId == drawerId
    }

    func toggleDrawer(drawerId: UUID) {
        expandedDrawerId = expandedDrawerId == drawerId ? nil : drawerId
    }

    func expandDrawer(drawerId: UUID) {
        expandedDrawerId = drawerId
    }

    func collapseAllDrawers() {
        expandedDrawerId = nil
    }

    func hydrate(persistedPanes: [Pane], validDrawerIds: Set<UUID>) {
        let expandedDrawerIds: [UUID] = persistedPanes.compactMap { pane in
            guard let drawer = pane.drawer, drawer.isExpanded, validDrawerIds.contains(drawer.drawerId) else {
                return nil
            }
            return drawer.drawerId
        }
        expandedDrawerId = expandedDrawerIds.last
    }

    func prune(validDrawerIds: Set<UUID>) {
        guard let expandedDrawerId, !validDrawerIds.contains(expandedDrawerId) else { return }
        self.expandedDrawerId = nil
    }
}
