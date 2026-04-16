import Testing

@testable import AgentStudio

@Suite("WorkspaceEmptyStateView")
struct WorkspaceEmptyStateViewTests {
    @Test("launcher uses welcome one echo split layout tokens")
    func launcherUsesWelcomeOneEchoSplitLayoutTokens() {
        #expect(WorkspaceEmptyStateLayout.launcherStartFastTitle == "Start Fast")
        #expect(AppStyles.Welcome.contentColumnsGap >= 56)
        #expect(AppStyles.Welcome.teachingColumnWidth > AppStyles.Welcome.recentCardWidth)
        #expect(AppStyles.Welcome.previewWidth > 300)
        #expect(AppStyles.Welcome.shortcutBodyLeadingInset > AppStyles.Welcome.shortcutKeyColumnWidth)
    }

    @Test("launcher recent grid stays fixed at two columns")
    func launcherRecentGridStaysFixedAtTwoColumns() {
        #expect(WorkspaceEmptyStateLayout.recentColumnCount(for: 800) == 2)
        #expect(WorkspaceEmptyStateLayout.recentColumnCount(for: 1600) == 2)
        #expect(WorkspaceEmptyStateLayout.recentColumnCount(for: 2200) == 2)
        #expect(WorkspaceEmptyStateLayout.recentColumnCount(for: 2700) == 2)
    }

    @Test("launcher recent grid still shows at most three rows")
    func launcherRecentGridShowsAtMostThreeRows() {
        #expect(WorkspaceEmptyStateLayout.visibleRecentCardLimit(for: 800) == 6)
        #expect(WorkspaceEmptyStateLayout.visibleRecentCardLimit(for: 1600) == 6)
        #expect(WorkspaceEmptyStateLayout.visibleRecentCardLimit(for: 2200) == 6)
        #expect(WorkspaceEmptyStateLayout.visibleRecentCardLimit(for: 2700) == 6)
    }
}
