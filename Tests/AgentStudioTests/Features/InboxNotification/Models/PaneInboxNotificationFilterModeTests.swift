import Testing

@testable import AgentStudio

@Suite("PaneInboxNotificationFilterMode")
struct PaneInboxNotificationFilterModeTests {
    @Test("filter mode toggle is explicit binary behavior")
    func filterModeToggleIsExplicitBinaryBehavior() {
        #expect(PaneInboxNotificationFilterMode.unread.toggled == .all)
        #expect(PaneInboxNotificationFilterMode.all.toggled == .unread)
    }
}
