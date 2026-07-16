import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("PaneFilesystemProjectionAtom")
struct PaneFilesystemProjectionAtomTests {
    @Test("projects file changes by worktree and pane cwd subtree")
    func projectsByWorktreeAndSubtree() {
        let store = PaneFilesystemProjectionAtom()
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
        _ = store.consume(
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
        let store = PaneFilesystemProjectionAtom()
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
        _ = store.consume(
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
        let store = PaneFilesystemProjectionAtom()
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
        _ = store.consume(
            envelope,
            panesById: [matchingPane.id: matchingPane, unrelatedPane.id: unrelatedPane],
            worktreeRootsByWorktreeId: [worktreeId: worktreeRoot, otherWorktreeId: worktreeRoot]
        )

        #expect(store.snapshotsByPaneId[matchingPane.id] != nil)
        #expect(store.snapshotsByPaneId[unrelatedPane.id] == nil)
    }

    @Test("consume returns pane-scoped filesystem context envelopes for subtree matches")
    func consumeReturnsPaneFilesystemContextEnvelopes() {
        let store = PaneFilesystemProjectionAtom()
        let repoId = UUID()
        let worktreeId = UUID()
        let worktreeRoot = URL(fileURLWithPath: "/tmp/worktree-\(UUID().uuidString)")
        let pane = makePane(
            repoId: repoId,
            worktreeId: worktreeId,
            cwd: worktreeRoot.appending(path: "Sources")
        )

        let derivedEnvelopes = store.consume(
            makeFilesChangedEnvelope(
                seq: 1,
                worktreeId: worktreeId,
                paths: ["README.md", "Sources/App.swift", "Sources/Views/List.swift"]
            ),
            panesById: [pane.id: pane],
            worktreeRootsByWorktreeId: [worktreeId: worktreeRoot]
        )

        let paneEvents = RuntimeEnvelopeHarness.paneEvents(from: derivedEnvelopes)
        #expect(paneEvents.count == 1)
        guard
            case .paneFilesystemContext(.cwdSubtreeChanged(let context, let paths, let batchSeq)) = paneEvents[0].event
        else {
            Issue.record("Expected cwdSubtreeChanged pane filesystem context event")
            return
        }
        #expect(context.paneId == PaneId(existingUUID: pane.id))
        #expect(context.repoId == repoId)
        #expect(context.cwd == worktreeRoot.appending(path: "Sources"))
        #expect(context.worktreeId == worktreeId)
        #expect(paths == Set(["Sources/App.swift", "Sources/Views/List.swift"]))
        #expect(batchSeq == 1)
    }

    @Test("consume returns pane-scoped git summary envelopes for worktree snapshots")
    func consumeReturnsPaneGitSummaryContextEnvelopes() {
        let store = PaneFilesystemProjectionAtom()
        let repoId = UUID()
        let worktreeId = UUID()
        let worktreeRoot = URL(fileURLWithPath: "/tmp/worktree-\(UUID().uuidString)")
        let pane = makePane(repoId: repoId, worktreeId: worktreeId, cwd: worktreeRoot)
        let snapshot = GitWorkingTreeSnapshot(
            worktreeId: worktreeId,
            repoId: repoId,
            rootPath: worktreeRoot,
            summary: GitWorkingTreeSummary(changed: 3, staged: 2, untracked: 1),
            branch: "main"
        )

        let derivedEnvelopes = store.consume(
            RuntimeEnvelopeHarness.gitEnvelope(
                event: .snapshotChanged(snapshot: snapshot),
                repoId: repoId,
                worktreeId: worktreeId
            ),
            panesById: [pane.id: pane],
            worktreeRootsByWorktreeId: [worktreeId: worktreeRoot]
        )

        let paneEvents = RuntimeEnvelopeHarness.paneEvents(from: derivedEnvelopes)
        #expect(paneEvents.count == 1)
        guard
            case .paneFilesystemContext(.gitWorkingTreeInCwd(let context, let staged, let unstaged, let untracked)) =
                paneEvents[0].event
        else {
            Issue.record("Expected gitWorkingTreeInCwd pane filesystem context event")
            return
        }
        #expect(context.paneId == PaneId(existingUUID: pane.id))
        #expect(context.repoId == repoId)
        #expect(context.cwd == worktreeRoot)
        #expect(staged == 2)
        #expect(unstaged == 3)
        #expect(untracked == 1)
    }

    @Test("derived filesystem context envelopes round-trip through the runtime bus harness")
    func derivedFilesystemContextEnvelopes_roundTripThroughBusHarness() async {
        let store = PaneFilesystemProjectionAtom()
        let repoId = UUID()
        let worktreeId = UUID()
        let worktreeRoot = URL(fileURLWithPath: "/tmp/worktree-\(UUID().uuidString)")
        let pane = makePane(
            repoId: repoId,
            worktreeId: worktreeId,
            cwd: worktreeRoot.appending(path: "Sources")
        )
        let harness = EventBusHarness<RuntimeEnvelope>()
        let subscriber = await harness.makeSubscriber()

        let derivedEnvelopes = store.consume(
            makeFilesChangedEnvelope(
                seq: 1,
                worktreeId: worktreeId,
                paths: ["README.md", "Sources/App.swift"]
            ),
            panesById: [pane.id: pane],
            worktreeRootsByWorktreeId: [worktreeId: worktreeRoot]
        )

        _ = await harness.postAll(derivedEnvelopes)

        await assertEventuallyAsync("bus subscriber should receive derived pane filesystem envelope") {
            await subscriber.snapshot().count == 1
        }

        let busPaneEvents = RuntimeEnvelopeHarness.paneEvents(from: await subscriber.snapshot())
        #expect(busPaneEvents.count == 1)
        guard case .paneFilesystemContext(.cwdSubtreeChanged(_, let paths, _)) = busPaneEvents[0].event else {
            Issue.record("Expected pane filesystem context event on bus")
            return
        }
        #expect(paths == Set(["Sources/App.swift"]))

        await subscriber.shutdown()
        await assertBusDrained(harness.bus)
    }

    @Test("prune removes snapshots for missing panes and worktrees")
    func pruneRemovesStaleSnapshots() {
        let store = PaneFilesystemProjectionAtom()
        let repoId = UUID()
        let keepWorktreeId = UUID()
        let dropWorktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/worktree-\(UUID().uuidString)")

        let keepPane = makePane(repoId: repoId, worktreeId: keepWorktreeId, cwd: rootPath)
        let dropPane = makePane(repoId: repoId, worktreeId: dropWorktreeId, cwd: rootPath)

        _ = store.consume(
            makeFilesChangedEnvelope(seq: 1, worktreeId: keepWorktreeId, paths: ["A.swift"]),
            panesById: [keepPane.id: keepPane, dropPane.id: dropPane],
            worktreeRootsByWorktreeId: [keepWorktreeId: rootPath, dropWorktreeId: rootPath]
        )
        _ = store.consume(
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
        let launchDirectory = URL(fileURLWithPath: "/tmp/worktree")
        return Pane(
            content: .terminal(
                TerminalState(provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7())
            ),
            metadata: PaneMetadata(
                launchDirectory: launchDirectory,
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
    ) -> RuntimeEnvelope {
        .worktree(
            WorktreeEnvelope(
                source: .system(.builtin(.filesystemWatcher)),
                seq: seq,
                timestamp: ContinuousClock().now,
                repoId: worktreeId,
                worktreeId: worktreeId,
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
        )
    }
}
