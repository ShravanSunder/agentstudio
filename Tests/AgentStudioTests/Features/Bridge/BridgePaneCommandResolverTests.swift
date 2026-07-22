import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge pane command resolver")
struct BridgePaneCommandResolverTests {
    @Test("the matching pane with the greatest attendance ordinal wins")
    func greatestAttendanceOrdinalWins() {
        // Arrange
        let worktreeId = UUID()
        let olderPaneId = UUID()
        let newerPaneId = UUID()
        let candidates = [
            candidate(paneId: olderPaneId, worktreeId: worktreeId, attendanceOrdinal: 4),
            candidate(paneId: newerPaneId, worktreeId: worktreeId, attendanceOrdinal: 9),
        ]

        // Act
        let resolution = BridgePaneCommandResolver.resolve(
            worktreeId: worktreeId,
            candidates: candidates
        )

        // Assert
        #expect(resolution == .reuse(paneId: newerPaneId))
    }

    @Test("the currently active matching pane wins an attendance tie")
    func currentActivePaneWinsAttendanceTie() {
        // Arrange
        let worktreeId = UUID()
        let inactivePaneId = UUID()
        let activePaneId = UUID()
        let candidates = [
            candidate(
                paneId: inactivePaneId,
                worktreeId: worktreeId,
                isCurrentActivePane: false,
                attendanceOrdinal: 12,
                tabIndex: 0
            ),
            candidate(
                paneId: activePaneId,
                worktreeId: worktreeId,
                isCurrentActivePane: true,
                attendanceOrdinal: 12,
                tabIndex: 1
            ),
        ]

        // Act
        let resolution = BridgePaneCommandResolver.resolve(
            worktreeId: worktreeId,
            candidates: candidates
        )

        // Assert
        #expect(resolution == .reuse(paneId: activePaneId))
    }

    @Test("restored attendance ties use stable tab then pane layout order")
    func restoredTieUsesStableWorkspaceOrder() {
        // Arrange
        let worktreeId = UUID()
        let laterTabPaneId = UUID()
        let laterPaneInFirstTabId = UUID()
        let firstPaneId = UUID()
        let candidates = [
            candidate(
                paneId: laterTabPaneId,
                worktreeId: worktreeId,
                attendanceOrdinal: nil,
                tabIndex: 1,
                paneIndexInTab: 0
            ),
            candidate(
                paneId: laterPaneInFirstTabId,
                worktreeId: worktreeId,
                attendanceOrdinal: nil,
                tabIndex: 0,
                paneIndexInTab: 2
            ),
            candidate(
                paneId: firstPaneId,
                worktreeId: worktreeId,
                attendanceOrdinal: nil,
                tabIndex: 0,
                paneIndexInTab: 1
            ),
        ]

        // Act
        let resolution = BridgePaneCommandResolver.resolve(
            worktreeId: worktreeId,
            candidates: candidates
        )

        // Assert
        #expect(resolution == .reuse(paneId: firstPaneId))
    }

    @Test("wrong-worktree non-Bridge and inactive panes are excluded")
    func ineligiblePanesAreExcluded() {
        // Arrange
        let worktreeId = UUID()
        let eligiblePaneId = UUID()
        let candidates = [
            candidate(paneId: UUID(), worktreeId: UUID(), attendanceOrdinal: 100),
            candidate(
                paneId: UUID(),
                worktreeId: worktreeId,
                isBridgePane: false,
                attendanceOrdinal: 100
            ),
            candidate(
                paneId: UUID(),
                worktreeId: worktreeId,
                isPaneActive: false,
                attendanceOrdinal: 100
            ),
            candidate(paneId: eligiblePaneId, worktreeId: worktreeId, attendanceOrdinal: 1),
        ]

        // Act
        let resolution = BridgePaneCommandResolver.resolve(
            worktreeId: worktreeId,
            candidates: candidates
        )

        // Assert
        #expect(resolution == .reuse(paneId: eligiblePaneId))
    }

    @Test("no eligible matching pane resolves to creation")
    func noMatchCreates() {
        // Arrange
        let worktreeId = UUID()
        let candidates = [
            candidate(paneId: UUID(), worktreeId: UUID(), attendanceOrdinal: 4),
            candidate(
                paneId: UUID(),
                worktreeId: worktreeId,
                isBridgePane: false,
                attendanceOrdinal: 8
            ),
        ]

        // Act
        let resolution = BridgePaneCommandResolver.resolve(
            worktreeId: worktreeId,
            candidates: candidates
        )

        // Assert
        #expect(resolution == .create)
    }

    private func candidate(
        paneId: UUID,
        worktreeId: UUID,
        isBridgePane: Bool = true,
        isPaneActive: Bool = true,
        isCurrentActivePane: Bool = false,
        attendanceOrdinal: UInt64?,
        tabIndex: Int = 0,
        paneIndexInTab: Int = 0
    ) -> BridgePaneCommandCandidate {
        BridgePaneCommandCandidate(
            paneId: paneId,
            worktreeId: worktreeId,
            isBridgePane: isBridgePane,
            isPaneActive: isPaneActive,
            isCurrentActivePane: isCurrentActivePane,
            attendanceOrdinal: attendanceOrdinal,
            tabIndex: tabIndex,
            paneIndexInTab: paneIndexInTab
        )
    }
}
