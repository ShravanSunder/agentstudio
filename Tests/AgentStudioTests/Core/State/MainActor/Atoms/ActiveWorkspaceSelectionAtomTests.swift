import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("ActiveWorkspaceSelectionAtom")
struct ActiveWorkspaceSelectionAtomTests {
    @Test("selection starts empty for welcome and empty-workspace states")
    func selectionStartsEmpty() {
        let atom = ActiveWorkspaceSelectionAtom()

        #expect(atom.activeWorkspaceId == nil)
    }

    @Test("selection can point at a workspace id without hydrating workspace identity")
    func selectionCanPointAtWorkspaceIdWithoutHydratingIdentity() {
        let atom = ActiveWorkspaceSelectionAtom()
        let workspaceId = UUID()

        atom.selectWorkspace(workspaceId)

        #expect(atom.activeWorkspaceId == workspaceId)
    }

    @Test("selection can be cleared")
    func selectionCanBeCleared() {
        let atom = ActiveWorkspaceSelectionAtom()
        atom.selectWorkspace(UUID())

        atom.clearSelection()

        #expect(atom.activeWorkspaceId == nil)
    }

    @Test("Core atoms own active workspace selection separately from workspace metadata")
    func coreAtomsOwnActiveWorkspaceSelectionSeparatelyFromWorkspaceMetadata() {
        let selectedWorkspaceId = UUID()
        let hydratedWorkspaceId = UUID()
        let identityAtom = WorkspaceIdentityAtom(
            workspaceId: hydratedWorkspaceId,
            workspaceName: "Hydrated Workspace",
            createdAt: Date()
        )
        let coreAtoms = CoreAtoms(
            workspaceIdentity: identityAtom
        )

        coreAtoms.activeWorkspaceSelection.selectWorkspace(selectedWorkspaceId)

        #expect(coreAtoms.activeWorkspaceSelection.activeWorkspaceId == selectedWorkspaceId)
        #expect(coreAtoms.workspaceIdentity.workspaceId == hydratedWorkspaceId)
        #expect(coreAtoms.workspaceIdentity.workspaceId != selectedWorkspaceId)
    }
}
