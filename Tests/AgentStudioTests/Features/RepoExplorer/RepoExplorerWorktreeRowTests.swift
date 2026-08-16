import AgentStudioCore
import SwiftUI
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
@Suite("RepoExplorerWorktreeRow")
struct RepoExplorerWorktreeRowTests {
    @Test("By Repo hides clean synced zero metadata while retaining unknown facts")
    func byRepoMetadataUsesZeroSuppression() {
        let cleanSynced = GitBranchStatus(
            isDirty: false,
            syncState: .synced,
            prCount: 0,
            linesAdded: 0,
            linesDeleted: 0
        )
        let noUpstream = GitBranchStatus(
            isDirty: false,
            syncState: .noUpstream,
            prCount: 0,
            linesAdded: 0,
            linesDeleted: 0
        )
        let dirtyAheadWithPullRequests = GitBranchStatus(
            isDirty: true,
            syncState: .ahead(2),
            prCount: 3,
            linesAdded: 4,
            linesDeleted: 1
        )

        #expect(!RepoExplorerWorktreeRowContent.shouldShowDiffChip(branchStatus: cleanSynced))
        #expect(!RepoExplorerWorktreeRowContent.shouldShowSyncChip(branchStatus: cleanSynced))
        #expect(!RepoExplorerWorktreeRowContent.shouldShowPullRequestChip(branchStatus: cleanSynced))
        #expect(!RepoExplorerWorktreeRowContent.shouldShowSyncChip(branchStatus: noUpstream))
        #expect(RepoExplorerWorktreeRowContent.shouldShowSyncChip(branchStatus: .unknown))
        #expect(RepoExplorerWorktreeRowContent.shouldShowDiffChip(branchStatus: dirtyAheadWithPullRequests))
        #expect(RepoExplorerWorktreeRowContent.shouldShowSyncChip(branchStatus: dirtyAheadWithPullRequests))
        #expect(RepoExplorerWorktreeRowContent.shouldShowPullRequestChip(branchStatus: dirtyAheadWithPullRequests))
    }

    @Test("pane trailing metadata suppresses zero pull requests")
    func paneTrailingMetadataSuppressesZeroPullRequests() {
        #expect(RepoExplorerPaneRow.normalizedPullRequestCount(nil) == nil)
        #expect(RepoExplorerPaneRow.normalizedPullRequestCount(0) == nil)
        #expect(RepoExplorerPaneRow.normalizedPullRequestCount(2) == 2)
    }

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

    @Test("context menu exposes creation destinations at the top level")
    func contextMenuGroupsCreationActionsByDestination() throws {
        let source = try String(
            contentsOfFile: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerWorktreeRow.swift",
            encoding: .utf8
        )

        #expect(source.contains("LocalActionSpec.createNewInPane.actionSpec"))
        #expect(source.contains("LocalActionSpec.createNewInTab.actionSpec"))
        #expect(!source.contains("LocalActionSpec.createNew.actionSpec"))
        #expect(!source.contains("LocalActionSpec.openInCurrentTabMenu.actionSpec"))
        #expect(!source.contains("LocalActionSpec.openInNewTabMenu.actionSpec"))
        #expect(source.contains("LocalActionSpec.goToPane.actionSpec"))
        #expect(source.contains("LocalActionSpec.openInEditorMenu.actionSpec"))
        #expect(source.contains("commandPresentation.contextMenuCommand(.openWorktreeInPane)"))
        #expect(source.contains("worktreeContextMenuLabel(for: openWorktreeInPane)"))
        #expect(source.contains("commandPresentation.contextMenuCommand(.openNewTerminalInTab)"))
        #expect(source.contains("worktreeContextMenuLabel(for: openNewTerminal)"))
        #expect(!source.contains("AppCommand.openWorktreeInPane.definition.actionSpec"))
        #expect(!source.contains("AppCommand.openNewTerminalInTab.definition.actionSpec"))
        #expect(!source.contains("contextMenuCommand(.openWorktree)"))
        let createNewInPaneOffset = try #require(
            source.range(of: "LocalActionSpec.createNewInPane.actionSpec")?.lowerBound
        )
        let createNewInTabOffset = try #require(
            source.range(of: "LocalActionSpec.createNewInTab.actionSpec")?.lowerBound
        )
        let goToPaneOffset = try #require(source.range(of: "LocalActionSpec.goToPane.actionSpec")?.lowerBound)
        #expect(createNewInTabOffset < createNewInPaneOffset)
        #expect(createNewInPaneOffset < goToPaneOffset)
    }

    @Test("context menu uses shared content labels for both creation destinations")
    func contextMenuUsesSharedContentLabels() throws {
        let source = try String(
            contentsOfFile: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerWorktreeRow.swift",
            encoding: .utf8
        )

        #expect(source.contains("worktreeContextMenuLabel(for: openNewTerminal)"))
        #expect(source.contains("worktreeContextMenuLabel(for: openReviewInNewTab)"))
        #expect(source.contains("worktreeContextMenuLabel(for: openFilesInNewTab)"))
        #expect(source.contains("worktreeContextMenuLabel(for: openWorktreeInPane)"))
        #expect(source.contains("worktreeContextMenuLabel(for: showBridgeReview)"))
        #expect(source.contains("worktreeContextMenuLabel(for: showBridgeFiles)"))
    }

    @Test("context menu labels use the same content vocabulary in tabs and panes")
    func contextMenuLabelsUseSharedContentVocabulary() {
        #expect(
            RepoExplorerWorktreeCommandPresentation.contextMenuLabel(for: .openNewTerminalInTab) == "Terminal"
        )
        #expect(
            RepoExplorerWorktreeCommandPresentation.contextMenuLabel(for: .openWorktreeInPane) == "Terminal"
        )
        #expect(
            RepoExplorerWorktreeCommandPresentation.contextMenuLabel(for: .openBridgeReviewInNewTab) == "Review"
        )
        #expect(
            RepoExplorerWorktreeCommandPresentation.contextMenuLabel(for: .showBridgeReview) == "Review"
        )
        #expect(
            RepoExplorerWorktreeCommandPresentation.contextMenuLabel(for: .openBridgeFilesInNewTab) == "Files"
        )
        #expect(
            RepoExplorerWorktreeCommandPresentation.contextMenuLabel(for: .showBridgeFiles) == "Files"
        )
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

    @Test("pane rows use the shared secondary metadata styling")
    func paneRowsUseSharedSecondaryMetadataStyling() throws {
        let paneNavigationSource = try String(
            contentsOfFile: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerPaneNavigation.swift",
            encoding: .utf8
        )
        let worktreeRowSource = try String(
            contentsOfFile: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerWorktreeRow.swift",
            encoding: .utf8
        )

        #expect(paneNavigationSource.contains("SidebarMetadataLine("))
        #expect(paneNavigationSource.contains("iconSystemName: \"terminal\""))
        #expect(paneNavigationSource.contains("text: row.secondaryText"))
        #expect(paneNavigationSource.contains("AppStyles.Shell.Sidebar.rowContentSpacing"))
        #expect(!paneNavigationSource.contains("SidebarChip("))
        #expect(!paneNavigationSource.contains("text: \"Active\""))
        #expect(paneNavigationSource.contains("normalizedPullRequestCount(pullRequestCount)"))
        #expect(paneNavigationSource.contains("Text(\"·\")"))
        #expect(
            worktreeRowSource.contains(
                """
                Image(systemName: "square.split.2x1")
                                        .font(.system(size: AppStyles.Shell.Sidebar.branchIconSize, weight: .medium))
                """
            )
        )
    }

    @Test("pane rows use By Repo rhythm, indent, and group-container color")
    func paneRowsMatchByRepoChromeAndTabGroupColor() throws {
        let explorerViewSource = try String(
            contentsOfFile: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift",
            encoding: .utf8
        )
        let appEntityIconSource = try String(
            contentsOfFile: "Sources/AgentStudio/SharedComponents/AppEntityIcon.swift",
            encoding: .utf8
        )

        #expect(explorerViewSource.contains("leading: AppStyles.Shell.Sidebar.groupChildRowLeadingInset"))
        #expect(explorerViewSource.contains("pullRequestCount: cachedProjectionResult.branchStatusByWorktreeId"))
        #expect(appEntityIconSource.contains("case .tabGroup:"))
        #expect(appEntityIconSource.contains("AppStyles.Shell.Sidebar.mutedPrimaryAccentColor"))
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
