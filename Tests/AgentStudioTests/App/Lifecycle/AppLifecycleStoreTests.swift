import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct AppLifecycleStoreTests {
    @Test("starts inactive and not terminating")
    func test_appLifecycleStore_startsInactiveAndNotTerminating() {
        let store = AppLifecycleStore()

        #expect(store.isActive == false)
        #expect(store.isTerminating == false)
    }

    @Test("mutates active and terminating state through explicit methods")
    func test_appLifecycleStore_mutationMethodsUpdateState() {
        let store = AppLifecycleStore()

        store.setActive(true)
        store.markTerminating()

        #expect(store.isActive == true)
        #expect(store.isTerminating == true)
    }
}
