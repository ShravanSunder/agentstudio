import Testing

@testable import AgentStudio

@MainActor
@Suite("InboxNotificationPlaceholder focus publishing")
struct InboxNotificationPlaceholderViewTests {
    @Test("publishing focused true flips sidebarHasFocus true")
    func focusPublishTrue() {
        let uiState = UIStateAtom()

        InboxNotificationPlaceholderFocusPublisher.publish(
            hasFocus: true,
            into: uiState
        )

        #expect(uiState.sidebarHasFocus == true)
    }

    @Test("publishing focused false flips sidebarHasFocus false")
    func focusPublishFalse() {
        let uiState = UIStateAtom()
        uiState.setSidebarHasFocus(true)

        InboxNotificationPlaceholderFocusPublisher.publish(
            hasFocus: false,
            into: uiState
        )

        #expect(uiState.sidebarHasFocus == false)
    }
}
