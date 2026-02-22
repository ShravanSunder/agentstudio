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
        // Act
        let match = Ghostty.SurfaceView.appOwnedShortcuts.contains { shortcut in
            shortcut.key == "p" && shortcut.mods == [.command]
        }

        // Assert
        #expect(match, "Expected ⌘P in appOwnedShortcuts")
    }

    @Test
    func test_appOwnedShortcuts_containsCmdShiftP() {
        // Act
        let match = Ghostty.SurfaceView.appOwnedShortcuts.contains { shortcut in
            shortcut.key == "p" && shortcut.mods == [.command, .shift]
        }

        // Assert
        #expect(match, "Expected ⌘⇧P in appOwnedShortcuts")
    }

    @Test
    func test_appOwnedShortcuts_containsCmdOptionP() {
        // Act
        let match = Ghostty.SurfaceView.appOwnedShortcuts.contains { shortcut in
            shortcut.key == "p" && shortcut.mods == [.command, .option]
        }

        // Assert
        #expect(match, "Expected ⌘⌥P in appOwnedShortcuts")
    }
}
