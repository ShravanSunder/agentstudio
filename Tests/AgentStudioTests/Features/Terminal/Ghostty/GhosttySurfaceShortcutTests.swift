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
        // Assert — command bar shortcuts, drawer-pane creation, and terminal navigation are registered
        #expect(
            Ghostty.SurfaceView.appOwnedShortcuts.count >= 5,
            "Expected app-owned shortcuts to include ⌘P, ⌘⇧P, ⌘⌥P, ⌘⇧D, and ⌘⌥K"
        )
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

    @Test
    func test_appOwnedShortcuts_containsCmdShiftD() {
        // Assert
        #expect(
            Ghostty.SurfaceView.appOwnedShortcuts.contains(.addDrawerPane),
            "Expected add drawer pane in appOwnedShortcuts"
        )
    }

    @Test
    func test_appOwnedShortcuts_containsCmdOptionKScrollToBottom() {
        #expect(
            Ghostty.SurfaceView.appOwnedShortcuts.contains(.scrollToBottom),
            "Expected scroll-to-bottom in appOwnedShortcuts"
        )
    }
}
