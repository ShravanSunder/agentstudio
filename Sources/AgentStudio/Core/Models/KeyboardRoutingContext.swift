import Foundation

package struct KeyboardRoutingContext: Equatable, Sendable {
    package let stableOwner: KeyboardOwner
    let activeSurface: ActiveKeyboardSurface
    let workspaceWindowId: UUID?

    init(
        stableOwner: KeyboardOwner,
        activeSurface: ActiveKeyboardSurface,
        workspaceWindowId: UUID? = nil
    ) {
        self.stableOwner = stableOwner
        self.activeSurface = activeSurface
        self.workspaceWindowId = workspaceWindowId
    }

    /// True only when the main pane chain itself genuinely owns keyboard input right now: the
    /// workspace window is key, the management layer is inactive, the sidebar is not focused, and
    /// no transient surface (command bar, arrangement panel, rename field, etc.) is presented.
    /// Package-level accessor so callers outside Core (e.g. the RepoExplorer sidebar's active-pane
    /// composition) can gate on this exact fact without `ActiveKeyboardSurface`/`KeyboardOwner`
    /// case matching being exposed more broadly than this one check needs.
    package var isStableMainWindowChain: Bool {
        if case .stable(.mainWindowChain) = activeSurface {
            return true
        }
        return false
    }
}

extension KeyboardRoutingContext {
    @MainActor
    package static func current(
        windowLifecycle: WindowLifecycleAtom,
        managementLayer: ManagementLayerAtom,
        uiState: WorkspaceSidebarState,
        commandBarSurface: CommandBarSurfaceAtom,
        transientKeyboardSurface: TransientKeyboardSurfaceAtom,
        workspaceWindowId: UUID? = nil
    ) -> KeyboardRoutingContext {
        let stableOwner = KeyboardOwner.current(
            windowLifecycle: windowLifecycle,
            managementLayer: managementLayer,
            uiState: uiState
        )
        let resolvedWorkspaceWindowId =
            workspaceWindowId
            ?? windowLifecycle.focusedWindowId
            ?? windowLifecycle.keyWindowId
            ?? commandBarSurface.activeSurface?.workspaceWindowId
            ?? transientKeyboardSurface.topAnySurface?.workspaceWindowId

        let activeSurface: ActiveKeyboardSurface
        if let commandBarScope = commandBarSurface.activeScope(for: resolvedWorkspaceWindowId) {
            activeSurface = .commandBar(scope: commandBarScope)
        } else if let transientSurface = transientKeyboardSurface.topSurface(for: resolvedWorkspaceWindowId) {
            activeSurface = .transient(transientSurface.kind)
        } else {
            activeSurface = .stable(stableOwner)
        }

        return KeyboardRoutingContext(
            stableOwner: stableOwner,
            activeSurface: activeSurface,
            workspaceWindowId: resolvedWorkspaceWindowId
        )
    }
}
