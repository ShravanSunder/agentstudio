import Testing

@testable import AgentStudio

@Suite("WorkspaceEmptyStateView")
struct WorkspaceEmptyStateViewTests {
    @Test("launcher quick actions section uses the agreed shortcuts boundary contract")
    func launcherQuickActionsSectionUsesShortcutsBoundaryContract() {
        #expect(WorkspaceEmptyStateLayout.launcherQuickActionsSectionTitle == "Shortcuts")
        #expect(WorkspaceEmptyStateLayout.launcherQuickActionsDividerWidth == 220)
        #expect(WorkspaceEmptyStateLayout.launcherQuickActionsSectionTopPadding > AppStyle.spacingLoose)
        #expect(WorkspaceEmptyStateLayout.launcherQuickActionsDividerBottomPadding > AppStyle.spacingLoose)
        #expect(WorkspaceEmptyStateLayout.launcherQuickActionsLabelBottomPadding > AppStyle.spacingLoose)
    }

    @Test("launcher recent grid uses 2 to 5 columns across width bands")
    func launcherRecentGridUsesTwoToFiveColumnsAcrossWidthBands() {
        #expect(WorkspaceEmptyStateLayout.recentColumnCount(for: 800) == 2)
        #expect(WorkspaceEmptyStateLayout.recentColumnCount(for: 1600) == 3)
        #expect(WorkspaceEmptyStateLayout.recentColumnCount(for: 2200) == 4)
        #expect(WorkspaceEmptyStateLayout.recentColumnCount(for: 2700) == 5)
    }

    @Test("launcher recent grid shows at most three rows")
    func launcherRecentGridShowsAtMostThreeRows() {
        #expect(WorkspaceEmptyStateLayout.visibleRecentCardLimit(for: 800) == 6)
        #expect(WorkspaceEmptyStateLayout.visibleRecentCardLimit(for: 1600) == 9)
        #expect(WorkspaceEmptyStateLayout.visibleRecentCardLimit(for: 2200) == 12)
        #expect(WorkspaceEmptyStateLayout.visibleRecentCardLimit(for: 2700) == 15)
    }
}
