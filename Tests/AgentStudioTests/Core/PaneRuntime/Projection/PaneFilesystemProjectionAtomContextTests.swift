import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("PaneFilesystemProjectionAtom context tracking")
struct PaneFilesystemProjectionAtomContextTests {
    @Test("registerPaneContext stores context by pane id")
    func registerPaneContextStoresContext() {
        let store = PaneFilesystemProjectionAtom()
        let context = PaneFilesystemContext(
            paneId: PaneId(),
            repoId: UUID(),
            cwd: URL(fileURLWithPath: "/tmp/worktree/Sources"),
            worktreeId: UUID()
        )

        store.registerPaneContext(context)

        #expect(store.contextsByPaneId[context.paneId.uuid] == context)
        #expect(store.context(for: context.paneId.uuid) == context)
    }

    @Test("unregisterPaneContext removes context and snapshot")
    func unregisterPaneContextRemovesContextAndSnapshot() {
        let store = PaneFilesystemProjectionAtom()
        let repoId = UUID()
        let worktreeId = UUID()
        let root = URL(fileURLWithPath: "/tmp/worktree-\(UUID().uuidString)")
        let pane = makePane(repoId: repoId, worktreeId: worktreeId, cwd: root)

        store.registerPaneContext(
            PaneFilesystemContext(
                paneId: PaneId(uuid: pane.id),
                repoId: repoId,
                cwd: root,
                worktreeId: worktreeId
            )
        )
        _ = store.consume(
            makeFilesChangedEnvelope(seq: 1, repoId: repoId, worktreeId: worktreeId, root: root, paths: ["A.swift"]),
            panesById: [pane.id: pane],
            worktreeRootsByWorktreeId: [worktreeId: root]
        )

        store.unregisterPaneContext(pane.id)

        #expect(store.contextsByPaneId[pane.id] == nil)
        #expect(store.snapshotsByPaneId[pane.id] == nil)
    }

    @Test("updatePaneCwd clears stale snapshot when cwd changes")
    func updatePaneCwdClearsSnapshotWhenCwdChanges() {
        let store = PaneFilesystemProjectionAtom()
        let repoId = UUID()
        let worktreeId = UUID()
        let root = URL(fileURLWithPath: "/tmp/worktree-\(UUID().uuidString)")
        let pane = makePane(repoId: repoId, worktreeId: worktreeId, cwd: root)
        let paneId = PaneId(uuid: pane.id)

        store.registerPaneContext(
            PaneFilesystemContext(paneId: paneId, repoId: repoId, cwd: root, worktreeId: worktreeId)
        )
        _ = store.consume(
            makeFilesChangedEnvelope(seq: 1, repoId: repoId, worktreeId: worktreeId, root: root, paths: ["A.swift"]),
            panesById: [pane.id: pane],
            worktreeRootsByWorktreeId: [worktreeId: root]
        )

        store.updatePaneCwd(paneId: pane.id, newCwd: root.appending(path: "Sources"))

        #expect(store.contextsByPaneId[pane.id]?.cwd == root.appending(path: "Sources"))
        #expect(store.snapshotsByPaneId[pane.id] == nil)
    }

    @Test("updatePaneCwd is idempotent when cwd is unchanged")
    func updatePaneCwdIsIdempotentWhenUnchanged() {
        let store = PaneFilesystemProjectionAtom()
        let context = PaneFilesystemContext(
            paneId: PaneId(),
            repoId: UUID(),
            cwd: URL(fileURLWithPath: "/tmp/worktree/Sources"),
            worktreeId: UUID()
        )
        store.registerPaneContext(context)

        store.updatePaneCwd(paneId: context.paneId.uuid, newCwd: context.cwd)

        #expect(store.contextsByPaneId[context.paneId.uuid] == context)
    }

    @Test("unchanged pane context upsert preserves snapshot")
    func unchangedPaneContextUpsertPreservesSnapshot() {
        let store = PaneFilesystemProjectionAtom()
        let repoId = UUID()
        let worktreeId = UUID()
        let root = URL(fileURLWithPath: "/tmp/worktree-\(UUID().uuidString)")
        let paneId = UUIDv7.generate()
        let update = FilesystemProjectionPaneUpdate(
            requestGeneration: 1,
            kind: .upsert(
                .init(
                    paneId: paneId,
                    paneKind: .terminal,
                    repoId: repoId,
                    worktreeId: worktreeId,
                    cwd: root
                )
            )
        )

        store.applyPaneContextUpdate(update)
        _ = store.applyProjectionIntent(
            .cwdSubtreeChanged(
                PaneFilesystemCWDSubtreeProjection(
                    paneId: paneId,
                    paneKind: .terminal,
                    context: PaneFilesystemContext(
                        paneId: PaneId(uuid: paneId),
                        repoId: repoId,
                        cwd: root,
                        worktreeId: worktreeId
                    ),
                    paths: ["Sources/App.swift"],
                    batchSequence: 1,
                    timestamp: .now,
                    correlationId: nil,
                    commandId: nil
                )
            )
        )

        store.applyPaneContextUpdate(update)

        #expect(store.snapshotsByPaneId[paneId]?.changedPaths == ["Sources/App.swift"])
    }

    @Test("prune and reset clean context tracking state")
    func pruneAndResetCleanContextTrackingState() {
        let store = PaneFilesystemProjectionAtom()
        let keepContext = PaneFilesystemContext(
            paneId: PaneId(),
            repoId: UUID(),
            cwd: URL(fileURLWithPath: "/tmp/worktree/Keep"),
            worktreeId: UUID()
        )
        let dropContext = PaneFilesystemContext(
            paneId: PaneId(),
            repoId: UUID(),
            cwd: URL(fileURLWithPath: "/tmp/worktree/Drop"),
            worktreeId: UUID()
        )
        store.registerPaneContext(keepContext)
        store.registerPaneContext(dropContext)

        store.prune(
            validPaneIds: Set([keepContext.paneId.uuid]),
            validWorktreeIds: Set([keepContext.worktreeId])
        )

        #expect(Set(store.contextsByPaneId.keys) == Set([keepContext.paneId.uuid]))

        store.reset()

        #expect(store.contextsByPaneId.isEmpty)
        #expect(store.snapshotsByPaneId.isEmpty)
    }

    private func makePane(repoId: UUID, worktreeId: UUID, cwd: URL?) -> Pane {
        Pane(
            content: .terminal(
                TerminalState(provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7())
            ),
            metadata: PaneMetadata(
                launchDirectory: URL(fileURLWithPath: "/tmp/worktree"),
                title: "Pane",
                facets: PaneContextFacets(repoId: repoId, worktreeId: worktreeId, cwd: cwd)
            )
        )
    }

    private func makeFilesChangedEnvelope(
        seq: UInt64,
        repoId: UUID,
        worktreeId: UUID,
        root: URL,
        paths: [String]
    ) -> RuntimeEnvelope {
        .worktree(
            WorktreeEnvelope.test(
                event: .filesystem(
                    .filesChanged(
                        changeset: FileChangeset(
                            worktreeId: worktreeId,
                            repoId: repoId,
                            rootPath: root,
                            paths: paths,
                            timestamp: ContinuousClock().now,
                            batchSeq: seq
                        )
                    )
                ),
                repoId: repoId,
                worktreeId: worktreeId,
                seq: seq
            )
        )
    }
}
