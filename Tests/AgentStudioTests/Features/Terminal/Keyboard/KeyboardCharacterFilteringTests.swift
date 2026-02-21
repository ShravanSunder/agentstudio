import AppKit
import XCTest

@testable import AgentStudio

final class KeyboardCharacterFilteringTests: XCTestCase {

    // MARK: - shouldSendKeyEventText Tests

    func test_shouldSendKeyEventText_nilText_returnsFalse() {
        // Arrange
        let text: String? = nil

        // Act
        let result = shouldSendKeyEventText(text)

        // Assert
        XCTAssertFalse(result)
    }

    func test_shouldSendKeyEventText_emptyText_returnsFalse() {
        // Arrange
        let text = ""

        // Act
        let result = shouldSendKeyEventText(text)

        // Assert
        XCTAssertFalse(result)
    }

    func test_shouldSendKeyEventText_controlCharacter_returnsFalse() {
        // Arrange - Ctrl+C produces 0x03
        let text = "\u{03}"

        // Act
        let result = shouldSendKeyEventText(text)

        // Assert
        XCTAssertFalse(result, "Control characters < 0x20 should not be sent")
    }

    func test_shouldSendKeyEventText_normalCharacter_returnsTrue() {
        // Arrange
        let text = "c"

        // Act
        let result = shouldSendKeyEventText(text)

        // Assert
        XCTAssertTrue(result)
    }

    func test_shouldSendKeyEventText_space_returnsTrue() {
        // Arrange - Space is 0x20, the boundary
        let text = " "

        // Act
        let result = shouldSendKeyEventText(text)

        // Assert
        XCTAssertTrue(result, "Space (0x20) should be sent")
    }

    func test_shouldSendKeyEventText_tab_returnsFalse() {
        // Arrange - Tab is 0x09
        let text = "\t"

        // Act
        let result = shouldSendKeyEventText(text)

        // Assert
        XCTAssertFalse(result, "Tab (0x09) is < 0x20, should not be sent")
    }

    // MARK: - filterGhosttyCharacters Tests

    func test_filterGhosttyCharacters_nilInput_returnsNil() {
        // Arrange
        let characters: String? = nil

        // Act
        let result = filterGhosttyCharacters(
            characters: characters,
            byApplyingModifiers: { _ in "x" },
            modifierFlags: []
        )

        // Assert
        XCTAssertNil(result)
    }

    func test_filterGhosttyCharacters_normalChar_returnsUnchanged() {
        // Arrange
        let characters = "a"

        // Act
        let result = filterGhosttyCharacters(
            characters: characters,
            byApplyingModifiers: { _ in "x" },
            modifierFlags: []
        )

        // Assert
        XCTAssertEqual(result, "a")
    }

    func test_filterGhosttyCharacters_controlChar_stripsControlModifier() {
        // Arrange - 0x03 is Ctrl+C
        let characters = "\u{03}"
        var appliedFlags: NSEvent.ModifierFlags?

        // Act
        let result = filterGhosttyCharacters(
            characters: characters,
            byApplyingModifiers: { flags in
                appliedFlags = flags
                return "c"
            },
            modifierFlags: .control
        )

        // Assert
        XCTAssertEqual(result, "c")
        XCTAssertNotNil(appliedFlags)
        XCTAssertFalse(appliedFlags!.contains(.control), "Control should be stripped")
    }

    func test_filterGhosttyCharacters_functionKey_returnsNil() {
        // Arrange - F1 key in PUA range
        let characters = "\u{F704}"  // NSF1FunctionKey

        // Act
        let result = filterGhosttyCharacters(
            characters: characters,
            byApplyingModifiers: { _ in "x" },
            modifierFlags: []
        )

        // Assert
        XCTAssertNil(result, "Function keys should not be sent as text")
    }
}
