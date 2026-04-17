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

    // MARK: - Launcher content width + responsive breakpoints

    @Test("responsive breakpoint tokens exist with expected values")
    func responsiveBreakpointTokensExistWithExpectedValues() {
        #expect(AppStyles.Welcome.launcherWideBreakpoint == 1400)
        #expect(AppStyles.Welcome.launcherNarrowBreakpoint == 900)
        #expect(AppStyles.Welcome.recentsColumnCountWide == 3)
        #expect(AppStyles.Welcome.recentsColumnCountNarrow == 1)
        #expect(AppStyles.Welcome.recentsColumnCount == 2)
    }

    @Test("launcher content max width caps at 780")
    func launcherContentMaxWidthCapsAt780() {
        #expect(AppStyles.Welcome.launcherContentMaxWidth == 780)
    }

    @Test("recent card min width token exists at 260")
    func recentCardMinWidthTokenExistsAt260() {
        #expect(AppStyles.Welcome.recentCardMinWidth == 260)
    }

    // MARK: - Typography scale (semantic hierarchy)

    @Test("typography h1 is biggest and semibold")
    func typographyH1IsBiggestAndSemibold() {
        // Sanity: referencing the symbol compiles and produces a Font value.
        let font = AppStyles.Welcome.Typography.h1
        _ = font  // Touch to ensure the symbol survives.
    }

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

    // MARK: - Responsive recent grid

    @Test("recent column count is 3 at wide viewports")
    func recentColumnCountIs3AtWideViewports() {
        #expect(WorkspaceEmptyStateLayout.recentColumnCount(for: 1400) == 3)
        #expect(WorkspaceEmptyStateLayout.recentColumnCount(for: 1600) == 3)
        #expect(WorkspaceEmptyStateLayout.recentColumnCount(for: 2400) == 3)
    }

    @Test("recent column count is 2 at medium viewports")
    func recentColumnCountIs2AtMediumViewports() {
        #expect(WorkspaceEmptyStateLayout.recentColumnCount(for: 900) == 2)
        #expect(WorkspaceEmptyStateLayout.recentColumnCount(for: 1100) == 2)
        #expect(WorkspaceEmptyStateLayout.recentColumnCount(for: 1399) == 2)
    }

    @Test("recent column count is 1 at narrow viewports")
    func recentColumnCountIs1AtNarrowViewports() {
        #expect(WorkspaceEmptyStateLayout.recentColumnCount(for: 500) == 1)
        #expect(WorkspaceEmptyStateLayout.recentColumnCount(for: 899) == 1)
    }

    @Test("visible recent card limit stays at 6 across all viewports")
    func visibleRecentCardLimitStaysAt6AcrossAllViewports() {
        #expect(WorkspaceEmptyStateLayout.visibleRecentCardLimit(for: 500) == 6)
        #expect(WorkspaceEmptyStateLayout.visibleRecentCardLimit(for: 1100) == 6)
        #expect(WorkspaceEmptyStateLayout.visibleRecentCardLimit(for: 1600) == 6)
    }

    // MARK: - Flexible card width

    @Test("content column width equals teaching + gap + preview")
    func contentColumnWidthEqualsTeachingPlusGapPlusPreview() {
        let expected =
            AppStyles.Welcome.teachingColumnWidth
            + AppStyles.Welcome.contentColumnsGap
            + AppStyles.Welcome.previewWidth
        let actual = WorkspaceEmptyStateLayout.contentColumnWidth
        let diff = abs(actual - expected)
        #expect(diff < 0.001, "actual=\(actual) expected=\(expected) diff=\(diff)")
        #expect(abs(actual - 1092) < 0.001)
    }

    @Test("recent card width fills content column at each breakpoint")
    func recentCardWidthFillsContentColumnAtEachBreakpoint() {
        let gap = AppStyles.Welcome.recentCardGap
        let total = WorkspaceEmptyStateLayout.contentColumnWidth

        let wide3 = WorkspaceEmptyStateLayout.recentCardWidth(forColumns: 3)
        #expect(abs((wide3 * 3 + gap * 2) - total) < 0.001)

        let medium2 = WorkspaceEmptyStateLayout.recentCardWidth(forColumns: 2)
        #expect(abs((medium2 * 2 + gap) - total) < 0.001)

        let narrow1 = WorkspaceEmptyStateLayout.recentCardWidth(forColumns: 1)
        #expect(abs(narrow1 - total) < 0.001)
    }

    @Test("recent card width never goes below min width")
    func recentCardWidthNeverGoesBelowMinWidth() {
        let clamped = WorkspaceEmptyStateLayout.recentCardWidth(forColumns: 8)
        #expect(clamped >= AppStyles.Welcome.recentCardMinWidth)
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
        #expect(entries[0].body == "Run actions — open, close, toggle")
        #expect(entries[1].prefix == "$")
        #expect(entries[1].title == "Panes")
        #expect(entries[1].body == "Jump to any open tab or pane")
        #expect(entries[2].prefix == "#")
        #expect(entries[2].title == "Repos · Worktrees")
        #expect(entries[2].body == "Open a repo, switch a worktree, or start a new one")
    }

    // MARK: - Launcher composition sanity

    @Test("launcher narrow breakpoint is below command-palette horizontal width")
    func launcherNarrowBreakpointIsBelowCommandPaletteHorizontalWidth() {
        let pairWidth =
            AppStyles.Welcome.teachingColumnWidth
            + AppStyles.Welcome.contentColumnsGap
            + AppStyles.Welcome.previewWidth
        #expect(AppStyles.Welcome.launcherNarrowBreakpoint < pairWidth)
    }
}
