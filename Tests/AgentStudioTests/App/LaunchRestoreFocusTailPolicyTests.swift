import Testing

@testable import AgentStudio

@MainActor
struct LaunchRestoreFocusTailPolicyTests {
    @Test("publishing launch restore caller owns the focus tail")
    func publishedPlaceholderCaller_runsFocusTail() {
        #expect(LaunchRestoreFocusTailPolicy.shouldRun(for: .published))
    }

    @Test("reentrant launch restore caller never reruns the focus tail")
    func joinedPlaceholderCaller_skipsFocusTail() {
        #expect(!LaunchRestoreFocusTailPolicy.shouldRun(for: .joinedExistingPublication))
    }
}
