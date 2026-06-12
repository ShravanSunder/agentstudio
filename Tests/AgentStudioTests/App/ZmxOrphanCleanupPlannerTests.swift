import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct ZmxOrphanCleanupPlannerTests {

    @Test("returns known session IDs when candidates are resolvable")
    func test_plan_whenAllCandidatesResolvable_returnsKnownSessionIds() {
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
        #expect(
            plan.knownSessionIds
                == Set([
                    ZmxBackend.drawerSessionId(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId),
                    ZmxBackend.sessionId(
                        repoStableKey: "a1b2c3d4e5f6a7b8",
                        worktreeStableKey: "00112233aabbccdd",
                        paneId: mainPaneId
                    ),
                ])
        )
        #expect(plan.protectedPaneSegments.isEmpty)
    }

    @Test("protects unresolvable main pane sessions by pane segment")
    func test_plan_whenMainCandidateUnresolvable_protectsPaneSegment() {
        // Arrange
        let resolvablePaneId = UUID(uuidString: "11111111-1111-1111-AAAA-AAAAAAAAAAAA")!
        let unresolvedPaneId = UUID(uuidString: "22222222-2222-2222-BBBB-BBBBBBBBBBBB")!
        let knownSessionId = ZmxBackend.sessionId(
            repoStableKey: "abcdef0123456789",
            worktreeStableKey: "fedcba9876543210",
            paneId: resolvablePaneId
        )
        let protectedUnresolvableSessionId = ZmxBackend.sessionId(
            repoStableKey: "1111222233334444",
            worktreeStableKey: "5555666677778888",
            paneId: unresolvedPaneId
        )
        let destroyableOrphanId = ZmxBackend.sessionId(
            repoStableKey: "99990000aaaabbbb",
            worktreeStableKey: "ccccddddeeeeffff",
            paneId: UUID(uuidString: "33333333-3333-3333-CCCC-CCCCCCCCCCCC")!
        )
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
        #expect(plan.protectedPaneSegments.count == 1)
        #expect(
            plan.knownSessionIds == [knownSessionId]
        )
        #expect(
            plan.destroyableSessionIds(
                from: [
                    knownSessionId,
                    protectedUnresolvableSessionId,
                    destroyableOrphanId,
                    "user-session",
                    "as-user-owned-session",
                    "as-d--not-a-complete-drawer-id",
                ]
            ) == [destroyableOrphanId]
        )
    }
}
