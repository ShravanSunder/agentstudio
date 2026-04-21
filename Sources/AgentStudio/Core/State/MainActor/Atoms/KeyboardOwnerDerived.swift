import Foundation

/// Stateless factory that computes the current `KeyboardOwner`
/// from the three canonical input atoms.
@MainActor
struct KeyboardOwnerDerived {
    func current(
        windowLifecycle: WindowLifecycleAtom,
        managementLayer: ManagementLayerAtom,
        uiState: UIStateAtom
    ) -> KeyboardOwner {
        guard windowLifecycle.isWorkspaceWindowKey else {
            return .otherWindow
        }

        if managementLayer.isActive {
            return .managementLayer
        }

        if !uiState.sidebarCollapsed && uiState.sidebarHasFocus {
            return .sidebar(uiState.sidebarSurface)
        }

        return .none
    }
}
