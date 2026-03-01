import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("PaneFilesystemProjectionStore")
struct PaneFilesystemProjectionStoreTests {
    @Test("projects file changes by worktree and pane cwd subtree")
    func projectsByWorktreeAndSubtree() {
        let store = PaneFilesystemProjectionStore()
        let repoId = UUID()
        let worktreeId = UUID()
        let worktreeRoot = URL(fileURLWithPath: "/tmp/worktree-\(UUID().uuidString)")

        let rootPane = makePane(
            repoId: repoId,
            worktreeId: worktreeId,
            cwd: worktreeRoot
        )
        let subtreePane = makePane(
            repoId: repoId,
            worktreeId: worktreeId,
            cwd: worktreeRoot.appending(path: "Sources")
        )

        let envelope = makeFilesChangedEnvelope(
            seq: 1,
            worktreeId: worktreeId,
            paths: ["README.md", "Sources/App.swift", "Sources/Views/List.swift", "."]
        )
        store.consume(
            envelope,
            panesById: [rootPane.id: rootPane, subtreePane.id: subtreePane],
            worktreeRootsByWorktreeId: [worktreeId: worktreeRoot]
        )

        guard let rootSnapshot = store.snapshotsByPaneId[rootPane.id] else {
            Issue.record("Expected root pane snapshot")
            return
        }
        guard let subtreeSnapshot = store.snapshotsByPaneId[subtreePane.id] else {
            Issue.record("Expected subtree pane snapshot")
            return
        }

        #expect(rootSnapshot.changedPaths == ["README.md", "Sources/App.swift", "Sources/Views/List.swift", "."])
        #expect(subtreeSnapshot.changedPaths == ["Sources/App.swift", "Sources/Views/List.swift", "."])
    }

    @Test("pane projection uses worktree scope for nil cwd and subtree scope when cwd is set")
    func projectionHandlesNilCwdFallbackAndSubtreeScope() {
        let store = PaneFilesystemProjectionStore()
        let repoId = UUID()
        let worktreeId = UUID()
        let worktreeRoot = URL(fileURLWithPath: "/tmp/worktree-\(UUID().uuidString)")

        let nilCwdPane = makePane(
            repoId: repoId,
            worktreeId: worktreeId,
            cwd: nil
        )
        let subtreePane = makePane(
            repoId: repoId,
            worktreeId: worktreeId,
            cwd: worktreeRoot.appending(path: "Sources")
        )

        let envelope = makeFilesChangedEnvelope(
            seq: 2,
            worktreeId: worktreeId,
            paths: ["/README.md", "./Sources/App.swift", "Sources/App.swift", "Tests/Test.swift"]
        )
        store.consume(
            envelope,
            panesById: [nilCwdPane.id: nilCwdPane, subtreePane.id: subtreePane],
            worktreeRootsByWorktreeId: [worktreeId: worktreeRoot]
        )

        guard let nilCwdSnapshot = store.snapshotsByPaneId[nilCwdPane.id] else {
            Issue.record("Expected nil-cwd pane snapshot")
            return
        }
        guard let subtreeSnapshot = store.snapshotsByPaneId[subtreePane.id] else {
            Issue.record("Expected subtree pane snapshot")
            return
        }

        #expect(nilCwdSnapshot.changedPaths == ["README.md", "Sources/App.swift", "Tests/Test.swift"])
        #expect(subtreeSnapshot.changedPaths == ["Sources/App.swift"])
    }

    @Test("ignores panes that are outside the worktree id")
    func ignoresUnrelatedWorktreePanes() {
        let store = PaneFilesystemProjectionStore()
        let repoId = UUID()
        let worktreeId = UUID()
        let otherWorktreeId = UUID()
        let worktreeRoot = URL(fileURLWithPath: "/tmp/worktree-\(UUID().uuidString)")

        let matchingPane = makePane(
            repoId: repoId,
            worktreeId: worktreeId,
            cwd: worktreeRoot
        )
        let unrelatedPane = makePane(
            repoId: repoId,
            worktreeId: otherWorktreeId,
            cwd: worktreeRoot
        )

        let envelope = makeFilesChangedEnvelope(
            seq: 1,
            worktreeId: worktreeId,
            paths: ["Package.swift"]
        )
        store.consume(
            envelope,
            panesById: [matchingPane.id: matchingPane, unrelatedPane.id: unrelatedPane],
            worktreeRootsByWorktreeId: [worktreeId: worktreeRoot, otherWorktreeId: worktreeRoot]
        )

        #expect(store.snapshotsByPaneId[matchingPane.id] != nil)
        #expect(store.snapshotsByPaneId[unrelatedPane.id] == nil)
    }

    @Test("prune removes snapshots for missing panes and worktrees")
    func pruneRemovesStaleSnapshots() {
        let store = PaneFilesystemProjectionStore()
        let repoId = UUID()
        let keepWorktreeId = UUID()
        let dropWorktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/worktree-\(UUID().uuidString)")

        let keepPane = makePane(repoId: repoId, worktreeId: keepWorktreeId, cwd: rootPath)
        let dropPane = makePane(repoId: repoId, worktreeId: dropWorktreeId, cwd: rootPath)

        store.consume(
            makeFilesChangedEnvelope(seq: 1, worktreeId: keepWorktreeId, paths: ["A.swift"]),
            panesById: [keepPane.id: keepPane, dropPane.id: dropPane],
            worktreeRootsByWorktreeId: [keepWorktreeId: rootPath, dropWorktreeId: rootPath]
        )
        store.consume(
            makeFilesChangedEnvelope(seq: 2, worktreeId: dropWorktreeId, paths: ["B.swift"]),
            panesById: [keepPane.id: keepPane, dropPane.id: dropPane],
            worktreeRootsByWorktreeId: [keepWorktreeId: rootPath, dropWorktreeId: rootPath]
        )

        store.prune(
            validPaneIds: Set([keepPane.id]),
            validWorktreeIds: Set([keepWorktreeId])
        )

        #expect(store.snapshotsByPaneId[keepPane.id] != nil)
        #expect(store.snapshotsByPaneId[dropPane.id] == nil)
    }

    private func makePane(
        repoId: UUID,
        worktreeId: UUID,
        cwd: URL?
    ) -> Pane {
        Pane(
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(
                source: .worktree(worktreeId: worktreeId, repoId: repoId),
                title: "Pane",
                facets: PaneContextFacets(
                    repoId: repoId,
                    worktreeId: worktreeId,
                    cwd: cwd
                )
            )
        )
    }

    private func makeFilesChangedEnvelope(
        seq: UInt64,
        worktreeId: UUID,
        paths: [String]
    ) -> PaneEventEnvelope {
        PaneEventEnvelope(
            source: .system(.builtin(.filesystemWatcher)),
            sourceFacets: PaneContextFacets(worktreeId: worktreeId),
            paneKind: nil,
            seq: seq,
            commandId: nil,
            correlationId: nil,
            timestamp: ContinuousClock().now,
            epoch: 0,
            event: .filesystem(
                .filesChanged(
                    changeset: FileChangeset(
                        worktreeId: worktreeId,
                        rootPath: URL(fileURLWithPath: "/tmp/worktree-\(UUID().uuidString)"),
                        paths: paths,
                        timestamp: ContinuousClock().now,
                        batchSeq: seq
                    )
                )
            )
        )
    }
}
