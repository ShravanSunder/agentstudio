import SwiftUI
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
@Suite("RepoExplorerWorktreeRow")
struct RepoExplorerWorktreeRowTests {
    @Test("row content accepts primitive unread count")
    func rowContentAcceptsUnreadCount() {
        let view = RepoExplorerWorktreeRowContent(
            octiconLoader: makeRepoExplorerTestOcticonLoader(),
            checkoutTitle: "agent-studio",
            branchName: "main",
            placementText: "Pane 2 active",
            checkoutIconKind: .mainCheckout,
            iconColor: .accentColor,
            branchStatus: .unknown,
            unreadCount: 4,
            showsFavoriteControl: false
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
        #expect(RepoExplorerWorktreeRowContent.favoriteActionSpec(isFavorite: false).icon == .system(.bookmark))
        #expect(RepoExplorerWorktreeRowContent.favoriteActionSpec(isFavorite: true).icon == .system(.bookmarkFill))
    }

    @Test("favorite control visibility uses main worktree identity for every action")
    func favoriteControlVisibilityUsesMainWorktreeIdentity() {
        let mainVisibility = RepoExplorerFavoriteControlVisibility(isMainWorktree: true)
        let linkedVisibility = RepoExplorerFavoriteControlVisibility(isMainWorktree: false)

        #expect(mainVisibility.showsInlineButton)
        #expect(mainVisibility.showsContextMenuAction)
        #expect(!linkedVisibility.showsInlineButton)
        #expect(!linkedVisibility.showsContextMenuAction)
    }

    @Test("favorite visibility policy guards inline and context-menu actions")
    func favoriteVisibilityPolicyGuardsEveryAction() throws {
        let source = try String(
            contentsOfFile: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerWorktreeRow.swift",
            encoding: .utf8
        )

        #expect(source.contains("showsFavoriteControl: favoriteControlVisibility.showsInlineButton"))
        #expect(source.contains("if favoriteControlVisibility.showsContextMenuAction"))
        #expect(source.contains(".controlHelp(favoriteActionSpec.controlTooltipRenderValue())"))
        #expect(!source.contains(".help(favoriteActionSpec.helpText)"))
    }

    @Test("context menu groups creation actions by destination")
    func contextMenuGroupsCreationActionsByDestination() throws {
        let source = try String(
            contentsOfFile: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerWorktreeRow.swift",
            encoding: .utf8
        )

        #expect(source.contains("LocalActionSpec.openInCurrentTabMenu.actionSpec"))
        #expect(source.contains("LocalActionSpec.openInNewTabMenu.actionSpec"))
        #expect(source.contains("LocalActionSpec.createNew.actionSpec"))
        #expect(source.contains("LocalActionSpec.goToPane.actionSpec"))
        #expect(source.contains("LocalActionSpec.openInEditorMenu.actionSpec"))
        #expect(source.contains("commandPresentation.contextMenuCommand(.openWorktreeInPane)"))
        #expect(source.contains("menuLabel(actionSpec: openWorktreeInPane.commandSpec.actionSpec)"))
        #expect(source.contains("commandPresentation.contextMenuCommand(.openNewTerminalInTab)"))
        #expect(source.contains("menuLabel(actionSpec: openNewTerminal.commandSpec.actionSpec)"))
        #expect(!source.contains("AppCommand.openWorktreeInPane.definition.actionSpec"))
        #expect(!source.contains("AppCommand.openNewTerminalInTab.definition.actionSpec"))
        #expect(!source.contains("contextMenuCommand(.openWorktree)"))
        let createNewOffset = try #require(source.range(of: "LocalActionSpec.createNew.actionSpec")?.lowerBound)
        let goToPaneOffset = try #require(source.range(of: "LocalActionSpec.goToPane.actionSpec")?.lowerBound)
        #expect(createNewOffset < goToPaneOffset)
    }

    @Test("repository header menu contains only pane navigation and path actions")
    func repositoryHeaderMenuUsesExactAllowedActions() throws {
        let source = try String(
            contentsOfFile: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerPaneNavigation.swift",
            encoding: .utf8
        )

        let goToPaneOffset = try #require(source.range(of: "LocalActionSpec.goToPane.actionSpec")?.lowerBound)
        let revealOffset = try #require(source.range(of: "LocalActionSpec.revealInFinder.actionSpec")?.lowerBound)
        let copyOffset = try #require(source.range(of: "LocalActionSpec.copyPath.actionSpec")?.lowerBound)
        #expect(goToPaneOffset < revealOffset)
        #expect(revealOffset < copyOffset)
        #expect(source.contains("PathActions.revealInFinder(repo.repoPath)"))
        #expect(source.contains("PathActions.copyPath(repo.repoPath)"))
        #expect(!source.contains("Refresh Worktrees"))
        #expect(!source.contains("Remove Repo"))
        #expect(!source.contains("createNew"))
    }

    @Test("pane row icon matches sidebar pane metadata scale")
    func paneRowIconMatchesSidebarPaneMetadataScale() throws {
        let source = try String(
            contentsOfFile: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerPaneNavigation.swift",
            encoding: .utf8
        )

        #expect(
            source.contains(
                ".font(.system(size: AppStyles.Shell.Sidebar.branchFontSize, weight: .medium))"
            )
        )
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
