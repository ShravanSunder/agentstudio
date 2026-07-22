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
        #expect(atom.preferredWorkspaceWindowId == nil)
        #expect(atom.terminalContainerBounds == .zero)
        #expect(atom.isLaunchLayoutSettled == false)
        #expect(atom.isReadyForLaunchRestore == false)
    }

    @Test("registered windows start with conservative hidden presentation facts")
    func registeredWindowsStartHidden() throws {
        // Arrange
        let atom = WindowLifecycleAtom()
        let windowId = UUID()

        // Act
        atom.recordWindowRegistered(windowId)

        // Assert
        let facts = try #require(atom.presentationFacts(for: windowId))
        #expect(facts == .hidden)
    }

    @Test("window presentation facts transition independently")
    func windowPresentationFactsTransitionIndependently() throws {
        // Arrange
        let atom = WindowLifecycleAtom()
        let windowId = UUID()
        atom.recordWindowRegistered(windowId)

        // Act and assert: visible
        atom.recordWindowVisibility(true, for: windowId)
        #expect(
            try #require(atom.presentationFacts(for: windowId))
                == WindowPresentationFacts(isVisible: true, isMiniaturized: false, isOccluded: true)
        )

        // Act and assert: unoccluded
        atom.recordWindowOcclusion(false, for: windowId)
        #expect(
            try #require(atom.presentationFacts(for: windowId))
                == WindowPresentationFacts(isVisible: true, isMiniaturized: false, isOccluded: false)
        )

        // Act and assert: miniaturized
        atom.recordWindowMiniaturization(true, for: windowId)
        #expect(
            try #require(atom.presentationFacts(for: windowId))
                == WindowPresentationFacts(isVisible: true, isMiniaturized: true, isOccluded: false)
        )
    }

    @Test("unregistered windows cannot mint presentation facts")
    func unregisteredWindowsCannotMintPresentationFacts() {
        // Arrange
        let atom = WindowLifecycleAtom()
        let windowId = UUID()

        // Act
        atom.recordWindowPresentation(
            WindowPresentationFacts(isVisible: true, isMiniaturized: false, isOccluded: false),
            for: windowId
        )

        // Assert
        #expect(atom.presentationFacts(for: windowId) == nil)
    }

    @Test("key and focus transitions do not change window presentation facts")
    func keyAndFocusDoNotChangeWindowPresentationFacts() throws {
        // Arrange
        let atom = WindowLifecycleAtom()
        let windowId = UUID()
        atom.recordWindowRegistered(windowId)
        let originalFacts = try #require(atom.presentationFacts(for: windowId))

        // Act
        atom.recordWindowBecameKey(windowId)
        atom.recordWindowResignedKey(windowId)
        atom.recordWindowBecameFocused(windowId)
        atom.recordWindowResignedFocused(windowId)

        // Assert
        #expect(atom.presentationFacts(for: windowId) == originalFacts)
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
        #expect(atom.preferredWorkspaceWindowId == windowId)
    }

    @Test("preferred workspace window falls back to single registered window")
    func test_preferredWorkspaceWindowId_fallsBackToSingleRegisteredWindow() {
        let atom = WindowLifecycleAtom()
        let windowId = UUID()

        atom.recordWindowRegistered(windowId)

        #expect(atom.keyWindowId == nil)
        #expect(atom.focusedWindowId == nil)
        #expect(atom.preferredWorkspaceWindowId == windowId)
    }

    @Test("preferred workspace window refuses ambiguous registered windows")
    func test_preferredWorkspaceWindowId_refusesAmbiguousRegisteredWindows() {
        let atom = WindowLifecycleAtom()

        atom.recordWindowRegistered(UUID())
        atom.recordWindowRegistered(UUID())

        #expect(atom.keyWindowId == nil)
        #expect(atom.focusedWindowId == nil)
        #expect(atom.preferredWorkspaceWindowId == nil)
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
