import SwiftUI
import Testing

@testable import AgentStudio

@MainActor
@Suite("InboxNotificationSidebarView")
struct InboxNotificationSidebarViewTests {
    @Test("instantiates with inbox atoms and pane store")
    func instantiates() {
        let view = InboxNotificationSidebarView(
            inboxAtom: InboxNotificationAtom(),
            prefsAtom: InboxNotificationPrefsAtom(),
            uiState: UIStateAtom(),
            workspacePaneAtom: WorkspacePaneAtom(),
            dispatcher: CommandDispatcher.shared,
            onRefocusActivePane: {}
        )

        _ = view.body
        #expect(Bool(true))
    }
}
