import SwiftUI
import Testing

@testable import AgentStudio

@MainActor
@Suite("RepoExplorerWorktreeRow")
struct RepoExplorerWorktreeRowTests {
    @Test("row content accepts primitive unread count")
    func rowContentAcceptsUnreadCount() {
        let view = RepoExplorerWorktreeRowContent(
            checkoutTitle: "agent-studio",
            branchName: "main",
            checkoutIconKind: .mainCheckout,
            iconColor: .accentColor,
            branchStatus: .unknown,
            unreadCount: 4
        )

        _ = view.body
    }
}
