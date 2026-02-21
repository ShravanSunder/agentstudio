import AppKit
import GhosttyKit
import XCTest

@testable import AgentStudio

final class KeyboardModifiersTests: XCTestCase {

    // MARK: - ghosttyMods Tests

    func test_ghosttyMods_emptyFlags_returnsNone() {
        // Arrange
        let flags: NSEvent.ModifierFlags = []

        // Act
        let result = ghosttyMods(from: flags)

        // Assert
        XCTAssertEqual(result.rawValue, GHOSTTY_MODS_NONE.rawValue)
    }

    func test_ghosttyMods_shiftOnly_returnsShift() {
        // Arrange
        let flags: NSEvent.ModifierFlags = .shift

        // Act
        let result = ghosttyMods(from: flags)

        // Assert
        XCTAssertNotEqual(result.rawValue & GHOSTTY_MODS_SHIFT.rawValue, 0)
        XCTAssertEqual(result.rawValue & GHOSTTY_MODS_CTRL.rawValue, 0)
    }

    func test_ghosttyMods_controlOnly_returnsCtrl() {
        // Arrange
        let flags: NSEvent.ModifierFlags = .control

        // Act
        let result = ghosttyMods(from: flags)

        // Assert
        XCTAssertNotEqual(result.rawValue & GHOSTTY_MODS_CTRL.rawValue, 0)
    }

    func test_ghosttyMods_optionOnly_returnsAlt() {
        // Arrange
        let flags: NSEvent.ModifierFlags = .option

        // Act
        let result = ghosttyMods(from: flags)

        // Assert
        XCTAssertNotEqual(result.rawValue & GHOSTTY_MODS_ALT.rawValue, 0)
    }

    func test_ghosttyMods_commandOnly_returnsSuper() {
        // Arrange
        let flags: NSEvent.ModifierFlags = .command

        // Act
        let result = ghosttyMods(from: flags)

        // Assert
        XCTAssertNotEqual(result.rawValue & GHOSTTY_MODS_SUPER.rawValue, 0)
    }

    func test_ghosttyMods_capsLock_returnsCaps() {
        // Arrange
        let flags: NSEvent.ModifierFlags = .capsLock

        // Act
        let result = ghosttyMods(from: flags)

        // Assert
        XCTAssertNotEqual(result.rawValue & GHOSTTY_MODS_CAPS.rawValue, 0)
    }

    func test_ghosttyMods_multipleModifiers_returnsCombined() {
        // Arrange
        let flags: NSEvent.ModifierFlags = [.shift, .control, .option]

        // Act
        let result = ghosttyMods(from: flags)

        // Assert
        XCTAssertNotEqual(result.rawValue & GHOSTTY_MODS_SHIFT.rawValue, 0)
        XCTAssertNotEqual(result.rawValue & GHOSTTY_MODS_CTRL.rawValue, 0)
        XCTAssertNotEqual(result.rawValue & GHOSTTY_MODS_ALT.rawValue, 0)
        XCTAssertEqual(result.rawValue & GHOSTTY_MODS_SUPER.rawValue, 0)
    }
}
