import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceWindowMemoryAtom")
struct WorkspaceWindowMemoryAtomTests {
    @Test("window memory starts with default local geometry")
    func windowMemoryStartsWithDefaultLocalGeometry() {
        let atom = WorkspaceWindowMemoryAtom()

        #expect(atom.sidebarWidth == 250)
        #expect(atom.windowFrame == nil)
    }

    @Test("window memory replacement updates only local geometry fields")
    func windowMemoryReplacementUpdatesOnlyLocalGeometryFields() {
        let atom = WorkspaceWindowMemoryAtom()
        let frame = CGRect(x: 12, y: 34, width: 900, height: 700)

        atom.replaceWindowMemory(sidebarWidth: 320, windowFrame: frame)

        #expect(atom.sidebarWidth == 320)
        #expect(atom.windowFrame == frame)
    }

    @Test("sidebar and window frame mutate independently from identity")
    func sidebarAndWindowFrameMutateIndependentlyFromIdentity() {
        let identity = WorkspaceIdentityAtom(workspaceId: UUIDv7.generate())
        let initialWorkspaceId = identity.workspaceId
        let memory = WorkspaceWindowMemoryAtom()
        let frame = CGRect(x: 4, y: 5, width: 600, height: 500)

        memory.setSidebarWidth(300)
        memory.setWindowFrame(frame)

        #expect(identity.workspaceId == initialWorkspaceId)
        #expect(identity.workspaceName == "Default Workspace")
        #expect(memory.sidebarWidth == 300)
        #expect(memory.windowFrame == frame)
    }

}
