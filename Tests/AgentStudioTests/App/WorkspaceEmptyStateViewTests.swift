import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

@Suite("WorkspaceEmptyStateView")
struct WorkspaceEmptyStateViewTests {
    // MARK: - Welcome 1 regression locks (must never fail)

    @Test("welcome 1 illustration width is pinned")
    func welcome1IllustrationWidthIsPinned() {
        #expect(WelcomeSidebarIllustrationConstants.frameWidth == 300)
    }

    @Test("welcome 1 palette indices are pinned")
    func welcome1PaletteIndicesArePinned() {
        #expect(WelcomeSidebarIllustrationConstants.ghosttyPaletteIndex == 0)
        #expect(WelcomeSidebarIllustrationConstants.uvPaletteIndex == 3)
    }

    @Test("welcome tokens read by welcome 1 do not shift")
    func welcomeTokensReadByWelcome1DoNotShift() {
        #expect(AppStyles.Welcome.titleFontSize == 30)
        #expect(AppStyles.Welcome.bodyFontSize == AppStyles.General.Typography.textXl)
        #expect(AppStyles.Welcome.titleBodyGap == 8)
        #expect(AppStyles.Welcome.headerMaxWidth == 720)
    }

    // MARK: - Launcher composition tokens

    @Test("launcher content max width fits preview + gap + shortcuts column")
    func launcherContentMaxWidthFitsPreviewPlusGapPlusShortcutsColumn() {
        // Preview (500) + shortcut columns gap + shortcut column. The max width
        // must leave room for the shortcuts column to render comfortably.
        let minViable =
            AppStyles.Welcome.previewWidth
            + AppStyles.Welcome.launcherShortcutsColumnsGap
            + 320  // reasonable shortcuts column width
        #expect(AppStyles.Welcome.launcherContentMaxWidth >= minViable)
    }

    @Test("launcher page top padding is comfortable")
    func launcherPageTopPaddingIsComfortable() {
        // Welcome 2 is a page; top padding should be big enough that the title
        // doesn't feel jammed against the toolbar.
        #expect(AppStyles.Welcome.launcherPageTopPadding >= 48)
    }

    @Test("recent card limit stays at 6")
    func recentCardLimitStaysAt6() {
        #expect(WorkspaceEmptyStateLayout.visibleRecentCardLimit == 6)
    }

    // MARK: - Typography scale (semantic hierarchy)

    @Test("typography scale symbols exist for every role")
    func typographyScaleSymbolsExistForEveryRole() {
        _ = AppStyles.Welcome.Typography.h1
        _ = AppStyles.Welcome.Typography.h2
        _ = AppStyles.Welcome.Typography.h3
        _ = AppStyles.Welcome.Typography.body
        _ = AppStyles.Welcome.Typography.bodySm
        _ = AppStyles.Welcome.Typography.caption
        _ = AppStyles.Welcome.Typography.key
    }

    @Test("text color opacities are set for h2 and h3")
    func textColorOpacitiesAreSetForH2AndH3() {
        #expect(AppStyles.Welcome.TextColor.h2Opacity == 0.62)
        #expect(AppStyles.Welcome.TextColor.h3Opacity == 0.88)
    }

    // MARK: - Embedded cmd-P preview

    @Test("preview mocks five ghost-themed worktrees so every row matches the query")
    @MainActor
    func previewMocksFiveGhostThemedWorktrees() {
        let items = CommandBarEmbeddedPreview.mockItems
        let titles = items.map(\.title)
        #expect(
            titles == [
                "ghostty",
                "ghostrider",
                "ghostty.gpu-renderer",
                "ghostty.fix-keybinds",
                "ghostrider.fix-engine",
            ])
        // Every row must contain the preview query so the highlight demo
        // reads cleanly — no unmatched rows cluttering the mock.
        for title in titles {
            #expect(title.contains(CommandBarEmbeddedPreview.previewQuery))
        }
    }

    @Test("preview groups worktrees by repo")
    @MainActor
    func previewGroupsWorktreesByRepo() {
        let groups = CommandBarEmbeddedPreview.mockGroups
        #expect(groups.map(\.name) == ["Repos", "ghostty (worktrees)", "ghostrider (worktrees)"])
        #expect(groups[0].items.count == 2)
        #expect(groups[1].items.count == 2)
        #expect(groups[2].items.count == 1)
    }

    @Test("preview query is short so it still feels like the user is typing")
    @MainActor
    func previewQueryIsShort() {
        #expect(CommandBarEmbeddedPreview.previewQuery == "gho")
    }

    // MARK: - Folder-intake layout tokens (noFolders/scanning/scanEmpty share)

    @Test("intake layout tokens are defined")
    func intakeLayoutTokensAreDefined() {
        // These tokens back the shared layout used by noFolders, scanning,
        // and scanEmpty — the illustration + logo + title + body stay put
        // across all three states, so these must be stable.
        #expect(AppStyles.Welcome.intakeColumnSpacing == 56)
        #expect(AppStyles.Welcome.intakeRightColumnSpacing == 20)
        #expect(AppStyles.Welcome.intakeLogoSize == 96)
        #expect(AppStyles.Welcome.intakeActionTopPadding == 8)
        #expect(AppStyles.Welcome.intakeActionRowSpacing == 10)
        #expect(AppStyles.Welcome.intakeScanningSpinnerGap == 10)
    }

    @Test("intake scanning title opacity reuses h3 readability")
    func intakeScanningTitleOpacityIsReadable() {
        // Scanning/scanEmpty titles are h3-weight text — must stay readable,
        // not fade into the background.
        #expect(AppStyles.Welcome.intakeScanningTitleOpacity >= 0.8)
    }

    // MARK: - Copy locks

    @Test("intake copy is stable")
    func intakeCopyIsStable() {
        #expect(WorkspaceEmptyStateCopy.intakeTitle == "Welcome to AgentStudio")
        #expect(WorkspaceEmptyStateCopy.intakeBody == "The terminal IDE built for coding agents.")
        #expect(WorkspaceEmptyStateCopy.intakeHelper.contains("watches"))
        #expect(WorkspaceEmptyStateCopy.intakeHelper.contains("automatically"))
    }

    @Test("intake busy copy mentions the folder picker")
    func intakeBusyCopyMentionsFolderPicker() {
        // The busy state is the instant-feedback placeholder — it must read as
        // "we're opening the picker", not as if scanning has already started.
        #expect(WorkspaceEmptyStateCopy.intakeBusyTitle.lowercased().contains("folder"))
        #expect(WorkspaceEmptyStateCopy.intakeBusyHelper.lowercased().contains("folder"))
    }

    @Test("scanning copy mentions the folder and what we're looking for")
    func scanningCopyMentionsFolder() {
        let title = WorkspaceEmptyStateCopy.scanningTitle(folder: "~/code/project")
        #expect(title == "Scanning ~/code/project")
        #expect(WorkspaceEmptyStateCopy.scanningHelper.contains("git folders"))
    }

    @Test("scan empty copy mentions the folder and offers a retry")
    func scanEmptyCopyMentionsFolder() {
        let title = WorkspaceEmptyStateCopy.scanEmptyTitle(folder: "~/code/project")
        #expect(title == "No git folders found in ~/code/project")
        #expect(WorkspaceEmptyStateCopy.scanEmptyRetryButton.contains("Choose"))
        #expect(WorkspaceEmptyStateCopy.scanEmptyHelper.contains("watching"))
    }

    @Test("displayName collapses the user's home directory to a tilde")
    func displayNameCollapsesHomeToTilde() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let nested = home.appendingPathComponent("code/project")
        #expect(
            WorkspaceEmptyStateCopy.displayName(for: nested, fallback: "") == "~/code/project"
        )
    }

    @Test("displayName preserves paths outside the home directory")
    func displayNamePreservesNonHomePaths() {
        let external = URL(fileURLWithPath: "/tmp/work/repo")
        #expect(
            WorkspaceEmptyStateCopy.displayName(for: external, fallback: "") == "/tmp/work/repo"
        )
    }

    @Test("displayName falls back when no path is present")
    func displayNameFallsBackWhenPathMissing() {
        #expect(
            WorkspaceEmptyStateCopy.displayName(for: nil, fallback: "this folder") == "this folder"
        )
    }

    // MARK: - Watch Folder rename

    @Test("addFolder command label is Watch Folder")
    @MainActor
    func addFolderCommandLabelIsWatchFolder() {
        let definition = CommandDispatcher.shared.definition(for: .addFolder)
        #expect(definition.actionSpec.label == "Watch Folder")
    }
}
