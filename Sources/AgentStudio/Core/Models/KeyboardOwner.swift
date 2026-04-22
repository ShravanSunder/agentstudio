import Foundation

/// Derived value naming who currently owns keyboard interpretation.
/// Never stored, never manually set.
enum KeyboardOwner: Equatable, Sendable {
    case otherWindow
    case managementLayer
    case sidebar(SidebarSurface)
    case mainWindowChain
}

extension KeyboardOwner {
    /// Computes the effective keyboard owner from the three canonical input atoms.
    ///
    /// `uiState.sidebarHasFocus` is a runtime cache published by focused sidebar
    /// surfaces. Callers that are about to present another key window must query
    /// this owner before that presentation steals key status from the workspace.
    @MainActor
    static func current(
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

        return .mainWindowChain
    }
}
