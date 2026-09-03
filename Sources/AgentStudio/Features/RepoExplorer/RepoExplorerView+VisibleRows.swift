import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import AppKit
import SwiftUI

enum RepoExplorerFocus: Hashable {
    case filter
}

final class RepoExplorerFocusableView: NSView {
    var onFocusChange: @MainActor (Bool) -> Void = { _ in }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            onFocusChange(true)
        }
        return didBecomeFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let didResignFirstResponder = super.resignFirstResponder()
        if didResignFirstResponder {
            onFocusChange(false)
        }
        return didResignFirstResponder
    }

    override func cancelOperation(_ sender: Any?) {
        _ = sender
    }
}

struct RepoExplorerFocusBridge: NSViewRepresentable {
    let uiState: WorkspaceSidebarState

    func makeNSView(context: Context) -> RepoExplorerFocusableView {
        let view = RepoExplorerFocusableView()
        view.identifier = RepoExplorerView.focusTargetIdentifier
        view.onFocusChange = { hasFocus in
            uiState.setSidebarHasFocus(hasFocus)
        }
        return view
    }

    func updateNSView(_ nsView: RepoExplorerFocusableView, context: Context) {
        nsView.onFocusChange = { hasFocus in
            uiState.setSidebarHasFocus(hasFocus)
        }
    }

    static func dismantleNSView(_ nsView: RepoExplorerFocusableView, coordinator: ()) {
        MainActor.assumeIsolated {
            nsView.onFocusChange(false)
        }
    }
}

enum RepoExplorerFocusPublisher {
    @MainActor
    static func publish(
        focusedField: RepoExplorerFocus?,
        into uiState: WorkspaceSidebarState
    ) {
        uiState.setSidebarHasFocus(focusedField != nil)
    }
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
