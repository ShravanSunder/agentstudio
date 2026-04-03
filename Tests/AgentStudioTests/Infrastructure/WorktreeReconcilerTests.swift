import Foundation
import Testing

@testable import AgentStudio

@Suite("WorktreeReconciler")
struct WorktreeReconcilerTests {
    @Test("does not report a topology change when discovery matches existing worktrees")
    func identicalDiscoveryDoesNotChangeTopology() {
        let repoId = UUID(uuidString: "01010101-0101-0101-0101-010101010101")!
        let existingMainId = UUID(uuidString: "02020202-0202-0202-0202-020202020202")!
        let existingFeatureId = UUID(uuidString: "03030303-0303-0303-0303-030303030303")!

        let existing = [
            makeWorktree(
                id: existingMainId,
                repoId: repoId,
                name: "agent-studio",
                path: "/tmp/repos/agent-studio",
                isMainWorktree: true
            ),
            makeWorktree(
                id: existingFeatureId,
                repoId: repoId,
                name: "feature-a",
                path: "/tmp/worktrees/feature-a"
            ),
        ]
        let discovered = [
            makeWorktree(
                repoId: repoId,
                name: "agent-studio",
                path: "/tmp/repos/agent-studio",
                isMainWorktree: true
            ),
            makeWorktree(
                repoId: repoId,
                name: "feature-a",
                path: "/tmp/worktrees/feature-a"
            ),
        ]

        let result = WorktreeReconciler.reconcile(
            repoId: repoId,
            existing: existing,
            discovered: discovered
        )

        #expect(result.merged == existing)
        #expect(result.delta.addedWorktreeIds.isEmpty)
        #expect(result.delta.removedWorktrees.isEmpty)
        #expect(result.delta.preservedWorktreeIds == [existingMainId, existingFeatureId])
        #expect(result.delta.didChange == false)
        #expect(result.delta.traceId == nil)
    }

    @Test("preserves existing identifiers when discovered worktrees match by path")
    func preservesIdentifiersForPathMatches() {
        let repoId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let existingMainId = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let existingFeatureId = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let traceId = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!

        let existing = [
            makeWorktree(
                id: existingMainId,
                repoId: repoId,
                name: "main",
                path: "/tmp/repos/agent-studio",
                isMainWorktree: true
            ),
            makeWorktree(
                id: existingFeatureId,
                repoId: repoId,
                name: "feature-a",
                path: "/tmp/worktrees/feature-a"
            ),
        ]
        let discovered = [
            makeWorktree(
                repoId: repoId,
                name: "main-renamed",
                path: "/tmp/repos/agent-studio",
                isMainWorktree: true
            ),
            makeWorktree(
                repoId: repoId,
                name: "feature-a-renamed",
                path: "/tmp/worktrees/feature-a"
            ),
        ]

        let result = WorktreeReconciler.reconcile(
            repoId: repoId,
            existing: existing,
            discovered: discovered,
            traceId: traceId
        )

        #expect(result.merged.map(\.id) == [existingMainId, existingFeatureId])
        #expect(result.merged.map(\.name) == ["main-renamed", "feature-a-renamed"])
        #expect(result.delta.addedWorktreeIds.isEmpty)
        #expect(result.delta.removedWorktrees.isEmpty)
        #expect(result.delta.preservedWorktreeIds == [existingMainId, existingFeatureId])
        #expect(result.delta.didChange)
        #expect(result.delta.traceId == traceId)
    }

    @Test("reuses the existing main identifier when the main worktree path changes")
    func reusesMainIdentifierForRelocatedMainWorktree() {
        let repoId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let existingMainId = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
        let existingFeatureId = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!

        let existing = [
            makeWorktree(
                id: existingMainId,
                repoId: repoId,
                name: "agent-studio",
                path: "/tmp/old/agent-studio",
                isMainWorktree: true
            ),
            makeWorktree(
                id: existingFeatureId,
                repoId: repoId,
                name: "feature-a",
                path: "/tmp/worktrees/feature-a"
            ),
        ]
        let discovered = [
            makeWorktree(
                repoId: repoId,
                name: "agent-studio",
                path: "/tmp/new/agent-studio",
                isMainWorktree: true
            ),
            makeWorktree(
                repoId: repoId,
                name: "feature-a",
                path: "/tmp/worktrees/feature-a"
            ),
        ]

        let result = WorktreeReconciler.reconcile(
            repoId: repoId,
            existing: existing,
            discovered: discovered
        )

        #expect(result.merged[0].id == existingMainId)
        #expect(result.merged[0].path == URL(fileURLWithPath: "/tmp/new/agent-studio"))
        #expect(result.merged[1].id == existingFeatureId)
        #expect(result.delta.addedWorktreeIds.isEmpty)
        #expect(result.delta.removedWorktrees.isEmpty)
        #expect(result.delta.preservedWorktreeIds == [existingMainId, existingFeatureId])
        #expect(result.delta.didChange)
    }

    @Test("reports added removed and preserved worktrees in the topology delta")
    func reportsTopologyDelta() {
        let repoId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let existingMainId = UUID(uuidString: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")!
        let removedFeatureId = UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!

        let existing = [
            makeWorktree(
                id: existingMainId,
                repoId: repoId,
                name: "agent-studio",
                path: "/tmp/repos/agent-studio",
                isMainWorktree: true
            ),
            makeWorktree(
                id: removedFeatureId,
                repoId: repoId,
                name: "feature-a",
                path: "/tmp/worktrees/feature-a"
            ),
        ]
        let discovered = [
            makeWorktree(
                repoId: repoId,
                name: "agent-studio",
                path: "/tmp/repos/agent-studio",
                isMainWorktree: true
            ),
            makeWorktree(
                repoId: repoId,
                name: "feature-b",
                path: "/tmp/worktrees/feature-b"
            ),
        ]

        let result = WorktreeReconciler.reconcile(
            repoId: repoId,
            existing: existing,
            discovered: discovered
        )

        #expect(result.merged.count == 2)
        #expect(result.delta.addedWorktreeIds.count == 1)
        #expect(result.delta.removedWorktrees.count == 1)
        #expect(result.delta.removedWorktrees[0].id == removedFeatureId)
        #expect(
            result.delta.removedWorktrees[0].path
                == URL(fileURLWithPath: "/tmp/worktrees/feature-a"))
        #expect(result.delta.preservedWorktreeIds == [existingMainId])
        #expect(result.delta.didChange)
    }

    @Test("reuses an existing identifier when the fallback name match is the only match")
    func reusesIdentifierForNameFallback() {
        let repoId = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let existingFeatureId = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!

        let existing = [
            makeWorktree(
                id: existingFeatureId,
                repoId: repoId,
                name: "feature-a",
                path: "/tmp/old-feature-a"
            )
        ]
        let discovered = [
            makeWorktree(
                repoId: repoId,
                name: "feature-a",
                path: "/tmp/new-feature-a"
            )
        ]

        let result = WorktreeReconciler.reconcile(
            repoId: repoId,
            existing: existing,
            discovered: discovered
        )

        #expect(result.merged.count == 1)
        #expect(result.merged[0].id == existingFeatureId)
        #expect(result.merged[0].path == URL(fileURLWithPath: "/tmp/new-feature-a"))
        #expect(result.delta.addedWorktreeIds.isEmpty)
        #expect(result.delta.removedWorktrees.isEmpty)
        #expect(result.delta.preservedWorktreeIds == [existingFeatureId])
    }

    @Test("mixed reconcile reports preserved added and removed categories together")
    func mixedReconcileReportsAllDeltaCategories() {
        let repoId = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let existingMainId = UUID(uuidString: "aaaaaaaa-1111-1111-1111-aaaaaaaaaaaa")!
        let existingNameMatchedId = UUID(uuidString: "bbbbbbbb-1111-1111-1111-bbbbbbbbbbbb")!
        let removedId = UUID(uuidString: "cccccccc-1111-1111-1111-cccccccccccc")!

        let existing = [
            makeWorktree(
                id: existingMainId,
                repoId: repoId,
                name: "main",
                path: "/tmp/repo",
                isMainWorktree: true
            ),
            makeWorktree(
                id: existingNameMatchedId,
                repoId: repoId,
                name: "feature-a",
                path: "/tmp/old-feature-a"
            ),
            makeWorktree(
                id: removedId,
                repoId: repoId,
                name: "feature-b",
                path: "/tmp/feature-b"
            ),
        ]
        let discovered = [
            makeWorktree(
                repoId: repoId,
                name: "main",
                path: "/tmp/repo",
                isMainWorktree: true
            ),
            makeWorktree(
                repoId: repoId,
                name: "feature-a",
                path: "/tmp/new-feature-a"
            ),
            makeWorktree(
                repoId: repoId,
                name: "feature-c",
                path: "/tmp/feature-c"
            ),
        ]

        let result = WorktreeReconciler.reconcile(
            repoId: repoId,
            existing: existing,
            discovered: discovered
        )

        #expect(result.merged.count == 3)
        #expect(result.delta.preservedWorktreeIds == [existingMainId, existingNameMatchedId])
        #expect(result.delta.addedWorktreeIds.count == 1)
        #expect(result.delta.removedWorktrees.count == 1)
        #expect(result.delta.removedWorktrees[0].id == removedId)
        #expect(result.delta.didChange)
    }

    @Test("empty discovery removes every existing worktree")
    func emptyDiscoveryRemovesAllExistingWorktrees() {
        let repoId = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let existingMainId = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let existingFeatureId = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!

        let existing = [
            makeWorktree(
                id: existingMainId,
                repoId: repoId,
                name: "agent-studio",
                path: "/tmp/repos/agent-studio",
                isMainWorktree: true
            ),
            makeWorktree(
                id: existingFeatureId,
                repoId: repoId,
                name: "feature-a",
                path: "/tmp/worktrees/feature-a"
            ),
        ]

        let result = WorktreeReconciler.reconcile(
            repoId: repoId,
            existing: existing,
            discovered: []
        )

        #expect(result.merged.isEmpty)
        #expect(result.delta.addedWorktreeIds.isEmpty)
        #expect(result.delta.removedWorktrees.count == 2)
        #expect(result.delta.removedWorktrees.map(\.id) == [existingMainId, existingFeatureId])
        #expect(
            result.delta.removedWorktrees.map(\.path) == [
                URL(fileURLWithPath: "/tmp/repos/agent-studio"),
                URL(fileURLWithPath: "/tmp/worktrees/feature-a"),
            ])
        #expect(result.delta.preservedWorktreeIds.isEmpty)
        #expect(result.delta.didChange)
    }

    private func makeWorktree(
        id: UUID = UUID(),
        repoId: UUID,
        name: String,
        path: String,
        isMainWorktree: Bool = false
    ) -> Worktree {
        Worktree(
            id: id,
            repoId: repoId,
            name: name,
            path: URL(fileURLWithPath: path),
            isMainWorktree: isMainWorktree
        )
    }
}
