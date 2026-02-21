import AppKit
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)

final class KeyboardRoutingTests {

    // MARK: - Event Type Tests

    @Test
    func test_determineKeyRouting_keyUpEvent_passesToSystem() {
        // Arrange
        let eventType = NSEvent.EventType.keyUp

        // Act
        let result = determineKeyRouting(
            eventType: eventType,
            focused: true,
            modifiers: .control,
            charactersIgnoringModifiers: "c"
        )

        // Assert
        #expect(result == .passToSystem)
    }

    // MARK: - Focus Tests

    @Test
    func test_determineKeyRouting_notFocused_passesToSystem() {
        // Arrange
        let focused = false

        // Act
        let result = determineKeyRouting(
            eventType: .keyDown,
            focused: focused,
            modifiers: .control,
            charactersIgnoringModifiers: "c"
        )

        // Assert
        #expect(result == .passToSystem)
    }

    // MARK: - Command Key Tests

    @Test
    func test_determineKeyRouting_commandC_passesToSystem() {
        // Arrange - Cmd+C should go to macOS for copy

        // Act
        let result = determineKeyRouting(
            eventType: .keyDown,
            focused: true,
            modifiers: .command,
            charactersIgnoringModifiers: "c"
        )

        // Assert
        #expect(result == .passToSystem)
    }

    @Test
    func test_determineKeyRouting_commandShiftV_passesToSystem() {
        // Arrange - Cmd+Shift+V should go to macOS

        // Act
        let result = determineKeyRouting(
            eventType: .keyDown,
            focused: true,
            modifiers: [.command, .shift],
            charactersIgnoringModifiers: "v"
        )

        // Assert
        #expect(result == .passToSystem)
    }

    @Test
    func test_determineKeyRouting_commandControlArrow_passesToSystem() {
        // Arrange - Cmd+Ctrl+Arrow for window managers (Rectangle)

        // Act
        let result = determineKeyRouting(
            eventType: .keyDown,
            focused: true,
            modifiers: [.command, .control],
            charactersIgnoringModifiers: nil  // Arrow keys
        )

        // Assert
        #expect(result == .passToSystem)
    }

    // MARK: - Control Key Tests

    @Test
    func test_determineKeyRouting_controlC_handlesInTerminal() {
        // Arrange - Ctrl+C should go to terminal

        // Act
        let result = determineKeyRouting(
            eventType: .keyDown,
            focused: true,
            modifiers: .control,
            charactersIgnoringModifiers: "c"
        )

        // Assert
        #expect(result == .handleInTerminal)
    }

    @Test
    func test_determineKeyRouting_controlSlash_modifiesAndHandles() {
        // Arrange - Ctrl+/ converts to Ctrl+_

        // Act
        let result = determineKeyRouting(
            eventType: .keyDown,
            focused: true,
            modifiers: .control,
            charactersIgnoringModifiers: "/"
        )

        // Assert
        #expect(result == .modifyAndHandle("_"))
    }

    @Test
    func test_determineKeyRouting_controlReturn_handlesInTerminal() {
        // Arrange - Ctrl+Return should go to terminal

        // Act
        let result = determineKeyRouting(
            eventType: .keyDown,
            focused: true,
            modifiers: .control,
            charactersIgnoringModifiers: "\r"
        )

        // Assert
        #expect(result == .handleInTerminal)
    }

    // MARK: - Other Modifier Tests

    @Test
    func test_determineKeyRouting_shiftReturn_passesToSystem() {
        // Arrange - Shift+Return flows through keyDown naturally

        // Act
        let result = determineKeyRouting(
            eventType: .keyDown,
            focused: true,
            modifiers: .shift,
            charactersIgnoringModifiers: "\r"
        )

        // Assert
        #expect(result == .passToSystem)
    }

    @Test
    func test_determineKeyRouting_optionArrow_passesToSystem() {
        // Arrange - Option+Arrow for word navigation

        // Act
        let result = determineKeyRouting(
            eventType: .keyDown,
            focused: true,
            modifiers: .option,
            charactersIgnoringModifiers: nil
        )

        // Assert
        #expect(result == .passToSystem)
    }

    @Test
    func test_determineKeyRouting_plainKey_passesToSystem() {
        // Arrange - Plain keys flow through keyDown naturally

        // Act
        let result = determineKeyRouting(
            eventType: .keyDown,
            focused: true,
            modifiers: [],
            charactersIgnoringModifiers: "a"
        )

        // Assert
        #expect(result == .passToSystem)
    }
}
