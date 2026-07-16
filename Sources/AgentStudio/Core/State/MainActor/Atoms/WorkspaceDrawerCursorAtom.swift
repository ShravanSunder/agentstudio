import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceDrawerCursorAtom {
    var expandedDrawerId: UUID? { storedExpandedDrawerId }

    private var storedExpandedDrawerId: UUID?

    init(expandedDrawerId: UUID? = nil) {
        storedExpandedDrawerId = expandedDrawerId
    }

    func isExpanded(drawerId: UUID) -> Bool {
        storedExpandedDrawerId == drawerId
    }

    func toggleDrawer(drawerId: UUID) {
        storedExpandedDrawerId = storedExpandedDrawerId == drawerId ? nil : drawerId
    }

    func expandDrawer(drawerId: UUID) {
        storedExpandedDrawerId = drawerId
    }

    func collapseAllDrawers() {
        storedExpandedDrawerId = nil
    }

    func replaceExpandedDrawer(_ expandedDrawerId: UUID?) {
        storedExpandedDrawerId = expandedDrawerId
    }

    func prune(validDrawerIds: Set<UUID>) {
        guard let storedExpandedDrawerId, !validDrawerIds.contains(storedExpandedDrawerId) else { return }
        self.storedExpandedDrawerId = nil
    }
}
