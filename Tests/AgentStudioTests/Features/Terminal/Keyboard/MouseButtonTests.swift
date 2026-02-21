import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@Suite(.serialized)

final class MouseButtonTests {

    @Test
    func test_ghosttyMouseButton_leftClick_returnsLeft() {
        #expect(ghosttyMouseButton(from: 0) == GHOSTTY_MOUSE_LEFT)
    }

    @Test
    func test_ghosttyMouseButton_rightClick_returnsRight() {
        #expect(ghosttyMouseButton(from: 1) == GHOSTTY_MOUSE_RIGHT)
    }

    @Test
    func test_ghosttyMouseButton_middleClick_returnsMiddle() {
        #expect(ghosttyMouseButton(from: 2) == GHOSTTY_MOUSE_MIDDLE)
    }

    @Test
    func test_ghosttyMouseButton_buttons3to7_returnCorrectButtons() {
        #expect(ghosttyMouseButton(from: 3) == GHOSTTY_MOUSE_FOUR)
        #expect(ghosttyMouseButton(from: 4) == GHOSTTY_MOUSE_FIVE)
        #expect(ghosttyMouseButton(from: 5) == GHOSTTY_MOUSE_SIX)
        #expect(ghosttyMouseButton(from: 6) == GHOSTTY_MOUSE_SEVEN)
        #expect(ghosttyMouseButton(from: 7) == GHOSTTY_MOUSE_EIGHT)
    }

    @Test
    func test_ghosttyMouseButton_outOfRange_defaultsToLeft() {
        #expect(ghosttyMouseButton(from: 99) == GHOSTTY_MOUSE_LEFT)
        #expect(ghosttyMouseButton(from: -1) == GHOSTTY_MOUSE_LEFT)
    }
}
