import Foundation

struct KeyboardRoutingContext: Equatable, Sendable {
    let keyboardOwner: KeyboardOwner
    let workspaceWindowId: UUID?
    let transientSurface: TransientKeyboardSurfaceKind?

    init(
        keyboardOwner: KeyboardOwner,
        workspaceWindowId: UUID? = nil,
        transientSurface: TransientKeyboardSurfaceKind? = nil
    ) {
        self.keyboardOwner = keyboardOwner
        self.workspaceWindowId = workspaceWindowId
        self.transientSurface = transientSurface
    }
}

extension KeyboardRoutingContext {
    @MainActor
    static func current(
        windowLifecycle: WindowLifecycleAtom,
        managementLayer: ManagementLayerAtom,
        uiState: UIStateAtom,
        transientKeyboardSurface: TransientKeyboardSurfaceAtom,
        workspaceWindowId: UUID? = nil
    ) -> KeyboardRoutingContext {
        let keyboardOwner = KeyboardOwner.current(
            windowLifecycle: windowLifecycle,
            managementLayer: managementLayer,
            uiState: uiState
        )
        let resolvedWorkspaceWindowId =
            workspaceWindowId ?? windowLifecycle.focusedWindowId ?? windowLifecycle.keyWindowId
        return KeyboardRoutingContext(
            keyboardOwner: keyboardOwner,
            workspaceWindowId: resolvedWorkspaceWindowId,
            transientSurface: transientKeyboardSurface.topSurface(for: resolvedWorkspaceWindowId)?.kind
        )
    }
}
