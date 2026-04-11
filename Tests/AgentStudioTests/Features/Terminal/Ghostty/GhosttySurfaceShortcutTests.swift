import AppKit
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
final class GhosttySurfaceShortcutTests {

    // MARK: - App-Owned Shortcut List

    @Test
    func test_appOwnedShortcuts_containsAtLeast3() {
        // Assert — at minimum the 3 command bar shortcuts are registered
        #expect(
            Ghostty.SurfaceView.appOwnedShortcuts.count >= 3, "Expected at least 3 app-owned shortcuts (⌘P, ⌘⇧P, ⌘⌥P)")
    }

    @Test
    func test_appOwnedShortcuts_containsCmdP() {
        // Assert
        #expect(
            Ghostty.SurfaceView.appOwnedShortcuts.contains(.showCommandBarEverything),
            "Expected quick open in appOwnedShortcuts"
        )
    }

    @Test
    func test_appOwnedShortcuts_containsCmdShiftP() {
        // Assert
        #expect(
            Ghostty.SurfaceView.appOwnedShortcuts.contains(.showCommandBarCommands),
            "Expected command palette in appOwnedShortcuts"
        )
    }

    @Test
    func test_appOwnedShortcuts_containsCmdOptionP() {
        // Assert
        #expect(
            Ghostty.SurfaceView.appOwnedShortcuts.contains(.showCommandBarPanes),
            "Expected pane picker in appOwnedShortcuts"
        )
    }
}
