import Testing

@testable import AgentStudio

@Suite(.serialized)
struct DropTargetLatchStateTests {

    @Test
    func test_shouldClearTarget_appInactive_returnsTrue() {
        #expect(DropTargetLatchState.shouldClearTarget(appIsActive: false, pressedMouseButtons: 1))
    }

    @Test
    func test_shouldClearTarget_noButtonsPressed_returnsTrue() {
        #expect(DropTargetLatchState.shouldClearTarget(appIsActive: true, pressedMouseButtons: 0))
    }

    @Test
    func test_shouldClearTarget_appActiveWithButtonsPressed_returnsFalse() {
        #expect(!DropTargetLatchState.shouldClearTarget(appIsActive: true, pressedMouseButtons: 1))
    }
}
