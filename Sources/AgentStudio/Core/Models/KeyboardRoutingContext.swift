import Foundation

struct KeyboardRoutingContext: Equatable, Sendable {
    let stableOwner: KeyboardOwner
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
}

extension KeyboardRoutingContext {
    @MainActor
    static func current(
        windowLifecycle: WindowLifecycleAtom,
        managementLayer: ManagementLayerAtom,
        uiState: UIStateAtom,
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
