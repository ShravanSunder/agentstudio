import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import AppKit
import SwiftUI

enum RepoExplorerFocus: Hashable {
    case filter
}

@MainActor
enum RepoExplorerViewportPublisher {
    static func publish(
        _ snapshot: RepoExplorerVisibleWorktreeSnapshot,
        into atom: SidebarVisibleWorktreesRuntimeAtom,
        onChange: @MainActor @Sendable () -> Void
    ) {
        atom.setVisibleWorktreeIds(snapshot.worktreeIDs)
        onChange()
    }
}

extension RepoExplorerView {
    @discardableResult
    package static func requestListFocus(on target: NSView) -> Bool {
        guard let target = target as? RepoExplorerMaterializationHost else { return false }
        return target.requestListFocus()
    }

    @discardableResult
    package static func requestFilterFocus(on target: NSView) -> Bool {
        guard let target = target as? RepoExplorerMaterializationHost else { return false }
        return target.requestFilterFocus()
    }

    package static let focusTargetIdentifier = NSUserInterfaceItemIdentifier("repoExplorerFocusTarget")
    static let surfaceListPolicy = SidebarSurfaceListPolicy.nativeSidebarList
    static let surfaceBackground = SidebarSurfaceBackground.shellChrome

    func updateSidebarVisibleWorktrees(_ snapshot: RepoExplorerVisibleWorktreeSnapshot) {
        RepoExplorerViewportPublisher.publish(
            snapshot,
            into: atom(\.sidebarVisibleWorktreesRuntime),
            onChange: onSidebarVisibleWorktreesChanged
        )
        onVisibleWorktreeSnapshotChanged(snapshot)
    }

    func clearSidebarVisibleWorktrees() {
        atom(\.sidebarVisibleWorktreesRuntime).setVisibleWorktreeIds([])
        onSidebarVisibleWorktreesChanged()
    }
}
