import Foundation

/// Pure attended-pane read model for consumers that care about current user attention.
///
/// A pane is attended only while the workspace window is key and the management
/// layer is inactive. Observation and transition delivery belong to the consuming
/// coordinator, not this derived state.
@MainActor
struct AttendedPaneDerived {
    private let tabLayout: WorkspaceTabLayoutAtom
    private let windowLifecycle: WindowLifecycleAtom
    private let managementLayer: ManagementLayerAtom

    init(
        tabLayout: WorkspaceTabLayoutAtom,
        windowLifecycle: WindowLifecycleAtom,
        managementLayer: ManagementLayerAtom
    ) {
        self.tabLayout = tabLayout
        self.windowLifecycle = windowLifecycle
        self.managementLayer = managementLayer
    }

    var attendedPaneId: UUID? {
        guard windowLifecycle.isWorkspaceWindowKey else { return nil }
        guard !managementLayer.isActive else { return nil }
        return tabLayout.activeTab?.activePaneId
    }
}
