import XCTest
import GhosttyKit
@testable import AgentStudio

final class MouseButtonTests: XCTestCase {

    func test_ghosttyMouseButton_leftClick_returnsLeft() {
        XCTAssertEqual(ghosttyMouseButton(from: 0), GHOSTTY_MOUSE_LEFT)
    }

    func test_ghosttyMouseButton_rightClick_returnsRight() {
        XCTAssertEqual(ghosttyMouseButton(from: 1), GHOSTTY_MOUSE_RIGHT)
    }

    func test_ghosttyMouseButton_middleClick_returnsMiddle() {
        XCTAssertEqual(ghosttyMouseButton(from: 2), GHOSTTY_MOUSE_MIDDLE)
    }

    func test_ghosttyMouseButton_buttons3to7_returnCorrectButtons() {
        XCTAssertEqual(ghosttyMouseButton(from: 3), GHOSTTY_MOUSE_FOUR)
        XCTAssertEqual(ghosttyMouseButton(from: 4), GHOSTTY_MOUSE_FIVE)
        XCTAssertEqual(ghosttyMouseButton(from: 5), GHOSTTY_MOUSE_SIX)
        XCTAssertEqual(ghosttyMouseButton(from: 6), GHOSTTY_MOUSE_SEVEN)
        XCTAssertEqual(ghosttyMouseButton(from: 7), GHOSTTY_MOUSE_EIGHT)
    }

    func test_ghosttyMouseButton_outOfRange_defaultsToLeft() {
        XCTAssertEqual(ghosttyMouseButton(from: 99), GHOSTTY_MOUSE_LEFT)
        XCTAssertEqual(ghosttyMouseButton(from: -1), GHOSTTY_MOUSE_LEFT)
    }
}
