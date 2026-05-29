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

    @Test("registry owns active workspace selection separately from workspace metadata")
    func registryOwnsActiveWorkspaceSelectionSeparatelyFromWorkspaceMetadata() {
        let selectedWorkspaceId = UUID()
        let hydratedWorkspaceId = UUID()
        let metadataAtom = WorkspaceMetadataAtom()
        metadataAtom.hydrate(
            workspaceId: hydratedWorkspaceId,
            workspaceName: "Hydrated Workspace",
            createdAt: Date(),
            sidebarWidth: 250,
            windowFrame: nil
        )
        let registry = AtomRegistry(
            workspaceMetadata: metadataAtom
        )

        registry.activeWorkspaceSelection.selectWorkspace(selectedWorkspaceId)

        #expect(registry.activeWorkspaceSelection.activeWorkspaceId == selectedWorkspaceId)
        #expect(registry.workspaceMetadata.workspaceId == hydratedWorkspaceId)
        #expect(registry.workspaceMetadata.workspaceId != selectedWorkspaceId)
    }
}
