import XCTest

@testable import AgentStudio

final class ZmxOrphanCleanupPlannerTests: XCTestCase {

    func test_plan_whenAllCandidatesResolvable_returnsKnownSessionIdsWithoutSkip() {
        // Arrange
        let parentPaneId = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let drawerPaneId = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let mainPaneId = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let candidates: [ZmxOrphanCleanupCandidate] = [
            .drawer(parentPaneId: parentPaneId, paneId: drawerPaneId),
            .main(
                paneId: mainPaneId,
                repoStableKey: "a1b2c3d4e5f6a7b8",
                worktreeStableKey: "00112233aabbccdd"
            ),
        ]

        // Act
        let plan = ZmxOrphanCleanupPlanner.plan(candidates: candidates)

        // Assert
        XCTAssertFalse(plan.shouldSkipCleanup)
        XCTAssertEqual(
            plan.knownSessionIds,
            Set([
                ZmxBackend.drawerSessionId(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId),
                ZmxBackend.sessionId(
                    repoStableKey: "a1b2c3d4e5f6a7b8",
                    worktreeStableKey: "00112233aabbccdd",
                    paneId: mainPaneId
                ),
            ])
        )
    }

    func test_plan_whenAnyMainCandidateUnresolvable_setsSkipCleanupTrue() {
        // Arrange
        let resolvablePaneId = UUID()
        let unresolvedPaneId = UUID()
        let candidates: [ZmxOrphanCleanupCandidate] = [
            .main(
                paneId: resolvablePaneId,
                repoStableKey: "abcdef0123456789",
                worktreeStableKey: "fedcba9876543210"
            ),
            .main(
                paneId: unresolvedPaneId,
                repoStableKey: nil,
                worktreeStableKey: "fedcba9876543210"
            ),
        ]

        // Act
        let plan = ZmxOrphanCleanupPlanner.plan(candidates: candidates)

        // Assert
        XCTAssertTrue(plan.shouldSkipCleanup)
        XCTAssertTrue(
            plan.knownSessionIds.contains(
                ZmxBackend.sessionId(
                    repoStableKey: "abcdef0123456789",
                    worktreeStableKey: "fedcba9876543210",
                    paneId: resolvablePaneId
                )
            )
        )
    }
}
