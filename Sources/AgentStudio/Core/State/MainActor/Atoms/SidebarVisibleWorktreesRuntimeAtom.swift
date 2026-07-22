import Foundation
import Observation

@MainActor
@Observable
final class SidebarVisibleWorktreesRuntimeAtom {
    /// Runtime-only sidebar row visibility fact used to prioritize git refresh cadence.
    private(set) var visibleWorktreeIds: Set<UUID> = []

    func setVisibleWorktreeIds(_ worktreeIds: Set<UUID>) {
        visibleWorktreeIds = worktreeIds
    }

    func clear() {
        visibleWorktreeIds.removeAll(keepingCapacity: false)
    }
}
