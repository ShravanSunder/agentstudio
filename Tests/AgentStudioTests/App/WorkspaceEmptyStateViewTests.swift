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

    // MARK: - New tokens from composition redesign

    @Test("hero row tokens exist with expected values")
    func heroRowTokensExistWithExpectedValues() {
        #expect(AppStyles.Welcome.heroRowCornerRadius == 18)
        #expect(AppStyles.Welcome.heroRowStrokeOpacity == AppStyles.General.Stroke.hover)
        #expect(AppStyles.Welcome.heroRowFillOpacity == AppStyles.General.Fill.subtle)
        #expect(AppStyles.Welcome.heroRowHoverFillOpacity == AppStyles.General.Fill.hover)
        #expect(AppStyles.Welcome.heroRowInnerHorizontalPadding == 24)
        #expect(AppStyles.Welcome.heroRowInnerVerticalPadding == 22)
        #expect(AppStyles.Welcome.heroRowChevronOpacity == 0.35)
    }

    @Test("scope row tokens exist with expected values")
    func scopeRowTokensExistWithExpectedValues() {
        #expect(AppStyles.Welcome.scopeRowVerticalSpacing == 12)
        #expect(AppStyles.Welcome.scopeRowTitleBodyGap == 2)
        #expect(AppStyles.Welcome.scopeRowBodySize == AppStyles.General.Typography.textSm)
        #expect(AppStyles.Welcome.scopeRowBodyOpacity == 0.50)
        #expect(AppStyles.Welcome.scopeRowBodyLineLimit == 2)
        #expect(AppStyles.Welcome.scopeRowCaretColumnWidth == AppStyles.CommandBar.Rows.iconSize)
    }

    @Test("responsive breakpoint tokens exist with expected values")
    func responsiveBreakpointTokensExistWithExpectedValues() {
        #expect(AppStyles.Welcome.launcherWideBreakpoint == 1400)
        #expect(AppStyles.Welcome.launcherNarrowBreakpoint == 900)
        #expect(AppStyles.Welcome.recentsColumnCountWide == 3)
        #expect(AppStyles.Welcome.recentsColumnCountNarrow == 1)
        #expect(AppStyles.Welcome.recentsColumnCount == 2)
    }

    @Test("section ordering gap tokens exist with expected values")
    func sectionOrderingGapTokensExistWithExpectedValues() {
        #expect(AppStyles.Welcome.recentsToHeroGap == 32)
        #expect(AppStyles.Welcome.heroToCommandPaletteGap == 28)
    }

    @Test("recent card min width token exists at 260")
    func recentCardMinWidthTokenExistsAt260() {
        #expect(AppStyles.Welcome.recentCardMinWidth == 260)
    }
}
