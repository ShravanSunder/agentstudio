import AppKit
import XCTest

@testable import AgentStudio

final class GhosttySurfaceShortcutTests: XCTestCase {

    // MARK: - App-Owned Shortcut List

    func test_appOwnedShortcuts_containsAtLeast3() {
        // Assert — at minimum the 3 command bar shortcuts are registered
        XCTAssertGreaterThanOrEqual(
            Ghostty.SurfaceView.appOwnedShortcuts.count, 3,
            "Expected at least 3 app-owned shortcuts (⌘P, ⌘⇧P, ⌘⌥P)"
        )
    }

    func test_appOwnedShortcuts_containsCmdP() {
        // Act
        let match = Ghostty.SurfaceView.appOwnedShortcuts.contains { shortcut in
            shortcut.key == "p" && shortcut.mods == [.command]
        }

        // Assert
        XCTAssertTrue(match, "Expected ⌘P in appOwnedShortcuts")
    }

    func test_appOwnedShortcuts_containsCmdShiftP() {
        // Act
        let match = Ghostty.SurfaceView.appOwnedShortcuts.contains { shortcut in
            shortcut.key == "p" && shortcut.mods == [.command, .shift]
        }

        // Assert
        XCTAssertTrue(match, "Expected ⌘⇧P in appOwnedShortcuts")
    }

    func test_appOwnedShortcuts_containsCmdOptionP() {
        // Act
        let match = Ghostty.SurfaceView.appOwnedShortcuts.contains { shortcut in
            shortcut.key == "p" && shortcut.mods == [.command, .option]
        }

        // Assert
        XCTAssertTrue(match, "Expected ⌘⌥P in appOwnedShortcuts")
    }
}
