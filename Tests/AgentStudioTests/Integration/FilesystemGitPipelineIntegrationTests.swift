import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct FilesystemGitPipelineIntegrationTests {
    @Test("pipeline emits filesystem and git snapshot facts that converge projection stores")
    func pipelineEmitsFilesystemAndGitSnapshotFacts() async throws {
        let bus = EventBus<RuntimeEnvelope>()
        let pipeline = FilesystemGitPipeline(
            bus: bus,
            gitWorkingTreeProvider: .stub { _ in
                GitWorkingTreeStatus(
                    summary: GitWorkingTreeSummary(changed: 2, staged: 1, untracked: 1),
                    branch: "feature/pipeline",
                    origin: nil
                )
            }
        )
        await pipeline.start()

        let rootPath = FileManager.default.temporaryDirectory
            .appending(path: "pipeline-int-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootPath) }

        let worktreeId = UUID()
        let repoId = UUID()
        let workspaceDir = FileManager.default.temporaryDirectory
            .appending(path: "pipeline-store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspaceDir) }
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: workspaceDir))
        store.restore()
        let pane = store.createPane(
            source: .worktree(worktreeId: worktreeId, repoId: repoId),
            title: "Pipeline Pane",
            facets: PaneContextFacets(repoId: repoId, worktreeId: worktreeId, cwd: rootPath)
        )
        let panesById: [UUID: Pane] = [pane.id: pane]
        let worktreeRootsByWorktreeId: [UUID: URL] = [worktreeId: rootPath]

        let paneProjectionStore = PaneFilesystemProjectionStore()
        let cacheStore = WorkspaceCacheStore()
        let cacheCoordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: store,
            cacheStore: cacheStore
        )
        let observed = ObservedFilesystemGitEvents()

        let stream = await bus.subscribe()
        let consumerTask = Task { @MainActor in
            for await envelope in stream {
                cacheCoordinator.consume(envelope)
                paneProjectionStore.consume(
                    envelope,
                    panesById: panesById,
                    worktreeRootsByWorktreeId: worktreeRootsByWorktreeId
                )
                await observed.record(envelope)
            }
        }
        defer { consumerTask.cancel() }

        await pipeline.register(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)
        await pipeline.enqueueRawPathsForTesting(
            worktreeId: worktreeId,
            paths: ["Sources/Feature.swift"]
        )

        let receivedFilesChanged = await eventually("filesChanged fact should be posted") {
            await observed.filesChangedCount(for: worktreeId) >= 1
        }
        #expect(receivedFilesChanged)

        let receivedGitSnapshot = await eventually("gitSnapshotChanged fact should be posted") {
            await observed.gitSnapshotCount(for: worktreeId) >= 1
        }
        #expect(receivedGitSnapshot)

        let projectionConverged = await eventually("pane filesystem projection should update") {
            paneProjectionStore.snapshotsByPaneId[pane.id]?.changedPaths.contains("Sources/Feature.swift") == true
        }
        #expect(projectionConverged)

        let gitStoreConverged = await eventually("workspace cache enrichment should update") {
            guard let snapshot = cacheStore.worktreeEnrichmentByWorktreeId[worktreeId]?.snapshot else { return false }
            return snapshot.summary.changed == 2
                && snapshot.summary.staged == 1
                && snapshot.summary.untracked == 1
                && snapshot.branch == "feature/pipeline"
        }
        #expect(gitStoreConverged)

        await pipeline.shutdown()
    }

    private func eventually(
        _ description: String,
        maxAttempts: Int = 200,
        pollIntervalNanoseconds: UInt64 = 10_000_000,
        condition: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        for _ in 0..<maxAttempts {
            if await condition() {
                return true
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        Issue.record("\(description) timed out")
        return false
    }
}

private actor ObservedFilesystemGitEvents {
    private var filesChangedCountsByWorktreeId: [UUID: Int] = [:]
    private var gitSnapshotCountsByWorktreeId: [UUID: Int] = [:]

    func record(_ envelope: RuntimeEnvelope) {
        guard case .worktree(let worktreeEnvelope) = envelope else { return }

        switch worktreeEnvelope.event {
        case .filesystem(.filesChanged(let changeset)):
            filesChangedCountsByWorktreeId[changeset.worktreeId, default: 0] += 1
        case .gitWorkingDirectory(.snapshotChanged(let snapshot)):
            gitSnapshotCountsByWorktreeId[snapshot.worktreeId, default: 0] += 1
        case .filesystem, .gitWorkingDirectory, .forge, .security:
            return
        }
    }

    func filesChangedCount(for worktreeId: UUID) -> Int {
        filesChangedCountsByWorktreeId[worktreeId, default: 0]
    }

    func gitSnapshotCount(for worktreeId: UUID) -> Int {
        gitSnapshotCountsByWorktreeId[worktreeId, default: 0]
    }
}
