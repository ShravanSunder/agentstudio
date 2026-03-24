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
        #expect(store.terminalContainerBounds == .zero)
        #expect(store.isLaunchLayoutSettled == false)
        #expect(store.isReadyForLaunchRestore == false)
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

    @Test("recordTerminalContainerBounds updates bounds")
    func test_recordTerminalContainerBounds_updatesBounds() {
        let store = WindowLifecycleStore()
        let bounds = CGRect(x: 0, y: 0, width: 1140, height: 824)

        store.recordTerminalContainerBounds(bounds)

        #expect(store.terminalContainerBounds == bounds)
        #expect(store.isReadyForLaunchRestore == false)
    }

    @Test("recordLaunchLayoutSettled transitions to true")
    func test_recordLaunchLayoutSettled_transitionsToTrue() {
        let store = WindowLifecycleStore()

        store.recordLaunchLayoutSettled()

        #expect(store.isLaunchLayoutSettled == true)
        #expect(store.isReadyForLaunchRestore == false)
    }

    @Test("isReadyForLaunchRestore requires settled layout and non-empty bounds")
    func test_isReadyForLaunchRestore_requiresSettledLayoutAndBounds() {
        let store = WindowLifecycleStore()

        store.recordTerminalContainerBounds(CGRect(x: 0, y: 0, width: 1140, height: 824))
        #expect(store.isReadyForLaunchRestore == false)

        store.recordLaunchLayoutSettled()
        #expect(store.isReadyForLaunchRestore == true)
    }

    @Test("isReadyForLaunchRestore stays false for empty bounds")
    func test_isReadyForLaunchRestore_staysFalseForEmptyBounds() {
        let store = WindowLifecycleStore()

        store.recordLaunchLayoutSettled()

        #expect(store.isReadyForLaunchRestore == false)
    }
}
