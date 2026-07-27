import Foundation
import Observation

@MainActor
@Observable
package final class SidebarVisibleWorktreesRuntimeAtom {
    /// Runtime-only sidebar row visibility fact used to prioritize git refresh cadence.
    package private(set) var visibleWorktreeIds: Set<UUID> = []

    package func setVisibleWorktreeIds(_ worktreeIds: Set<UUID>) {
        visibleWorktreeIds = worktreeIds
    }

    func clear() {
        visibleWorktreeIds.removeAll(keepingCapacity: false)
    }
}
