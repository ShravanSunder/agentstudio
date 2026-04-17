import CoreGraphics
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

    // MARK: - Launcher preview scope row

    @Test("launcher preview scope row compiles with title and body text")
    @MainActor
    func launcherPreviewScopeRowCompilesWithTitleAndBodyText() {
        let row = LauncherPreviewScopeRow(
            prefix: ">",
            title: "Commands",
            bodyText: "Run actions — open, close, toggle",
            isSelected: true
        )
        #expect(row.prefix == ">")
        #expect(row.title == "Commands")
        #expect(row.bodyText == "Run actions — open, close, toggle")
        #expect(row.isSelected == true)
    }

    @Test("command bar embedded preview exposes three scope entries")
    @MainActor
    func commandBarEmbeddedPreviewExposesThreeScopeEntries() {
        let entries = CommandBarEmbeddedPreview.scopeEntries
        #expect(entries.count == 3)
        #expect(entries[0].prefix == ">")
        #expect(entries[0].title == "Commands")
        #expect(entries[1].prefix == "$")
        #expect(entries[1].title == "Panes")
        #expect(entries[2].prefix == "#")
        #expect(entries[2].title == "Repos · Worktrees")
    }
}
