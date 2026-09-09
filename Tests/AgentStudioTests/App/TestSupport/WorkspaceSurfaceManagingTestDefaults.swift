import AgentStudioTerminal
import Foundation

@testable import AgentStudio

/// Fixtures outside renderer-visibility tests do not simulate renderer state.
/// Production conformers must implement the required visibility operations themselves.
extension WorkspaceSurfaceManaging {
    func setAttachedBindingsChangeHandler(_ handler: (() -> Void)?) {}

    func reconcileAttachedVisibility(
        _ visibilityForPaneID: (UUID) -> Bool
    ) -> SurfaceVisibilityReconciliationResult {
        .init(applied: 0, equal: 0, missing: 0)
    }
}
