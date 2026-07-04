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
            placementText: "Pane 2 active",
            checkoutIconKind: .mainCheckout,
            iconColor: .accentColor,
            branchStatus: .unknown,
            unreadCount: 4
        )

        _ = view.body
    }

    @Test("unread pill only renders for positive counts")
    func unreadPillVisibility() {
        #expect(RepoExplorerWorktreeRowContent.shouldShowUnreadPill(unreadCount: 0) == false)
        #expect(RepoExplorerWorktreeRowContent.shouldShowUnreadPill(unreadCount: 4) == true)
    }

    @Test("favorite state exposes explicit add and remove labels")
    func favoriteStateExposesExplicitLabels() {
        #expect(RepoExplorerWorktreeRowContent.favoriteAccessibilityLabel(isFavorite: false) == "Add Favorite")
        #expect(RepoExplorerWorktreeRowContent.favoriteAccessibilityLabel(isFavorite: true) == "Remove Favorite")
        #expect(RepoExplorerWorktreeRowContent.favoriteHelpText(isFavorite: false) == "Add favorite")
        #expect(RepoExplorerWorktreeRowContent.favoriteHelpText(isFavorite: true) == "Remove favorite")
        #expect(RepoExplorerWorktreeRowContent.favoriteSystemImageName(isFavorite: false) == "bookmark")
        #expect(RepoExplorerWorktreeRowContent.favoriteSystemImageName(isFavorite: true) == "bookmark.fill")
    }

    @Test("repo explorer remains inbox-feature agnostic")
    func repoExplorerDoesNotReferenceInboxFeatureTypes() throws {
        let source = try String(
            contentsOfFile: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerWorktreeRow.swift",
            encoding: .utf8
        )

        #expect(!source.contains("InboxNotification"))
    }
}
