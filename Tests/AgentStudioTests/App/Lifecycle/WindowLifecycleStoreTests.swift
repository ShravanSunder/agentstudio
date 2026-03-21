import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct WindowLifecycleStoreTests {
    @Test("starts with no registered or focused windows")
    func test_windowLifecycleStore_startsEmpty() {
        let store = WindowLifecycleStore()

        #expect(store.registeredWindowIds.isEmpty)
        #expect(store.keyWindowId == nil)
        #expect(store.focusedWindowId == nil)
    }

    @Test("tracks registered and key window identity")
    func test_windowLifecycleStore_tracksFocusedWindow() {
        let store = WindowLifecycleStore()
        let windowId = UUID()

        store.recordWindowRegistered(windowId)
        store.recordWindowBecameKey(windowId)

        #expect(store.registeredWindowIds == [windowId])
        #expect(store.keyWindowId == windowId)
        #expect(store.focusedWindowId == windowId)
    }
}
