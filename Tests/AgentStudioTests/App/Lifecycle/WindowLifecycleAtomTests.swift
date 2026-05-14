import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct WindowLifecycleAtomTests {
    @Test("starts with no registered or focused windows")
    func test_windowLifecycleAtom_startsEmpty() {
        let atom = WindowLifecycleAtom()

        #expect(atom.registeredWindowIds.isEmpty)
        #expect(atom.keyWindowId == nil)
        #expect(atom.focusedWindowId == nil)
        #expect(atom.terminalContainerBounds == .zero)
        #expect(atom.isLaunchLayoutSettled == false)
        #expect(atom.isReadyForLaunchRestore == false)
    }

    @Test("tracks registered and key window identity")
    func test_windowLifecycleAtom_tracksFocusedWindow() {
        let atom = WindowLifecycleAtom()
        let windowId = UUID()

        atom.recordWindowRegistered(windowId)
        atom.recordWindowBecameKey(windowId)

        #expect(atom.registeredWindowIds == [windowId])
        #expect(atom.keyWindowId == windowId)
        #expect(atom.focusedWindowId == windowId)
    }

    @Test("recordTerminalContainerBounds updates bounds")
    func test_recordTerminalContainerBounds_updatesBounds() {
        let atom = WindowLifecycleAtom()
        let bounds = CGRect(x: 0, y: 0, width: 1140, height: 824)

        atom.recordTerminalContainerBounds(bounds)

        #expect(atom.terminalContainerBounds == bounds)
        #expect(atom.isReadyForLaunchRestore == false)
    }

    @Test("recordTerminalContainerBounds ignores empty bounds")
    func test_recordTerminalContainerBounds_ignoresEmptyBounds() {
        let atom = WindowLifecycleAtom()
        let bounds = CGRect(x: 0, y: 0, width: 1140, height: 824)

        atom.recordTerminalContainerBounds(bounds)
        atom.recordTerminalContainerBounds(.zero)

        #expect(atom.terminalContainerBounds == bounds)
    }

    @Test("recordLaunchLayoutSettled transitions to true")
    func test_recordLaunchLayoutSettled_transitionsToTrue() {
        let atom = WindowLifecycleAtom()

        atom.recordLaunchLayoutSettled()

        #expect(atom.isLaunchLayoutSettled == true)
        #expect(atom.isReadyForLaunchRestore == false)
    }

    @Test("isReadyForLaunchRestore requires settled layout and non-empty bounds")
    func test_isReadyForLaunchRestore_requiresSettledLayoutAndBounds() {
        let atom = WindowLifecycleAtom()

        atom.recordTerminalContainerBounds(CGRect(x: 0, y: 0, width: 1140, height: 824))
        #expect(atom.isReadyForLaunchRestore == false)

        atom.recordLaunchLayoutSettled()
        #expect(atom.isReadyForLaunchRestore == true)
    }

    @Test("isReadyForLaunchRestore stays false for empty bounds")
    func test_isReadyForLaunchRestore_staysFalseForEmptyBounds() {
        let atom = WindowLifecycleAtom()

        atom.recordLaunchLayoutSettled()

        #expect(atom.isReadyForLaunchRestore == false)
    }
}
