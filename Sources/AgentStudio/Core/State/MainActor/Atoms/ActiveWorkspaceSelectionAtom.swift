import Foundation
import Observation

@MainActor
@Observable
final class ActiveWorkspaceSelectionAtom {
    private(set) var activeWorkspaceId: UUID?

    func selectWorkspace(_ workspaceId: UUID) {
        guard activeWorkspaceId != workspaceId else { return }
        activeWorkspaceId = workspaceId
    }

    func clearSelection() {
        guard activeWorkspaceId != nil else { return }
        activeWorkspaceId = nil
    }
}
