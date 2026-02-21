import AppKit
import Testing
import Foundation

@testable import AgentStudio

@Suite(.serialized)

final class KeyboardCharacterFilteringTests {

    // MARK: - shouldSendKeyEventText Tests

    @Test
    func test_shouldSendKeyEventText_nilText_returnsFalse() {
        // Arrange
        let text: String? = nil

        // Act
        let result = shouldSendKeyEventText(text)

        // Assert
        #expect(!(result))
    }

    @Test
    func test_shouldSendKeyEventText_emptyText_returnsFalse() {
        // Arrange
        let text = ""

        // Act
        let result = shouldSendKeyEventText(text)

        // Assert
        #expect(!(result))
    }

    @Test
    func test_shouldSendKeyEventText_controlCharacter_returnsFalse() {
        // Arrange - Ctrl+C produces 0x03
        let text = "\u{03}"

        // Act
        let result = shouldSendKeyEventText(text)

        // Assert
        #expect(!(result), "Control characters < 0x20 should not be sent")
    }

    @Test
    func test_shouldSendKeyEventText_normalCharacter_returnsTrue() {
        // Arrange
        let text = "c"

        // Act
        let result = shouldSendKeyEventText(text)

        // Assert
        #expect(result)
    }

    @Test
    func test_shouldSendKeyEventText_space_returnsTrue() {
        // Arrange - Space is 0x20, the boundary
        let text = " "

        // Act
        let result = shouldSendKeyEventText(text)

        // Assert
        #expect(result, "Space (0x20) should be sent")
    }

    @Test
    func test_shouldSendKeyEventText_tab_returnsFalse() {
        // Arrange - Tab is 0x09
        let text = "\t"

        // Act
        let result = shouldSendKeyEventText(text)

        // Assert
        #expect(!(result), "Tab (0x09) is < 0x20, should not be sent")
    }

    // MARK: - filterGhosttyCharacters Tests

    @Test
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
        #expect(result == nil)
    }

    @Test
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
        #expect(result == "a")
    }

    @Test
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
        #expect(result == "c")
        #expect(appliedFlags != nil)
        #expect(!(appliedFlags!.contains(.control)), "Control should be stripped")
    }

    @Test
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
        #expect(result == nil, "Function keys should not be sent as text")
    }
}
