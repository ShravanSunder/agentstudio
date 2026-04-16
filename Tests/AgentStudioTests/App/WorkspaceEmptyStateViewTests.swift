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

    // MARK: - Typography contract (locked values, pixel-level hierarchy)

    @Test("typography tokens match the spec contract values")
    func typographyTokensMatchSpecContractValues() {
        #expect(AppStyles.Welcome.titleFontSize == 30)
        #expect(AppStyles.Welcome.bodyFontSize == 16)
        #expect(AppStyles.Welcome.sectionLabelFontSize == 15)
        #expect(AppStyles.Welcome.sectionLabelOpacity == 0.62)
        #expect(AppStyles.Welcome.shortcutTitleFontSize == 24)
        #expect(AppStyles.Welcome.shortcutBodyFontSize == AppStyles.Welcome.bodyFontSize)
        #expect(AppStyles.Welcome.shortcutKeyFontSize == 18)
    }

    @Test("typography hierarchy: shortcut title outranks general body text")
    func typographyHierarchyShortcutTitleOutranksGeneralBodyText() {
        #expect(AppStyles.Welcome.shortcutTitleFontSize > AppStyles.Welcome.bodyFontSize)
        #expect(AppStyles.Welcome.shortcutTitleFontSize > AppStyles.General.Typography.textBase)
    }

    @Test("typography hierarchy: page title outranks shortcut titles")
    func typographyHierarchyPageTitleOutranksShortcutTitles() {
        #expect(AppStyles.Welcome.titleFontSize > AppStyles.Welcome.shortcutTitleFontSize)
    }

    @Test("typography hierarchy: preview scope body stays below title")
    func typographyHierarchyPreviewScopeBodyStaysBelowTitle() {
        #expect(AppStyles.Welcome.scopeRowBodySize < AppStyles.General.Typography.textBase)
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
}
