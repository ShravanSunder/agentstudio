import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct AppLifecycleAtomTests {
    @Test("starts inactive and not terminating")
    func test_appLifecycleAtom_startsInactiveAndNotTerminating() {
        let atom = AppLifecycleAtom()

        #expect(atom.isActive == false)
        #expect(atom.isTerminating == false)
    }

    @Test("mutates active and terminating state through explicit methods")
    func test_appLifecycleAtom_mutationMethodsUpdateState() {
        let atom = AppLifecycleAtom()

        atom.setActive(true)
        atom.markTerminating()

        #expect(atom.isActive == true)
        #expect(atom.isTerminating == true)
    }
}
