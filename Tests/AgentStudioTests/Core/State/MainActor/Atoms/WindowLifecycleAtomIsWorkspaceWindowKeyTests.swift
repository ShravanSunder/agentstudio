import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("WindowLifecycleAtom.isWorkspaceWindowKey")
struct WindowLifecycleAtomIsWorkspaceWindowKeyTests {
    @Test("nil keyWindowId is false")
    func nilKeyWindowIdIsFalse() {
        let atom = WindowLifecycleAtom()

        #expect(atom.isWorkspaceWindowKey == false)
    }

    @Test("keyWindowId present but not registered is false")
    func keyWindowNotRegisteredIsFalse() {
        let atom = WindowLifecycleAtom()
        let foreignId = UUID()

        atom.recordWindowBecameKey(foreignId)

        #expect(atom.isWorkspaceWindowKey == false)
    }

    @Test("keyWindowId present and registered is true")
    func keyWindowRegisteredIsTrue() {
        let atom = WindowLifecycleAtom()
        let id = UUID()

        atom.recordWindowRegistered(id)
        atom.recordWindowBecameKey(id)

        #expect(atom.isWorkspaceWindowKey == true)
    }

    @Test("resigning key makes isWorkspaceWindowKey false")
    func resignKeyReturnsFalse() {
        let atom = WindowLifecycleAtom()
        let id = UUID()

        atom.recordWindowRegistered(id)
        atom.recordWindowBecameKey(id)
        #expect(atom.isWorkspaceWindowKey == true)

        atom.recordWindowResignedKey(id)

        #expect(atom.isWorkspaceWindowKey == false)
    }
}
