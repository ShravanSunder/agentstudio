import Foundation
import Testing

@testable import AgentStudio

@Suite
struct FilesystemProjectionIndexAffectedKeyTests {
    @Test("closed worktree event admission projects only filesystem changes and Git snapshots")
    func closedWorktreeEventAdmissionProjectsOnlyOwnedInputs() {
        let repoId = UUIDv7.generate()
        let worktreeId = UUIDv7.generate()
        let rootPath = URL(fileURLWithPath: "/tmp/repo")
        let changeset = FileChangeset(
            worktreeId: worktreeId,
            repoId: repoId,
            rootPath: rootPath,
            paths: ["file.swift"],
            timestamp: .now,
            batchSeq: 1
        )
        let snapshot = GitWorkingTreeSnapshot(
            worktreeId: worktreeId,
            repoId: repoId,
            rootPath: rootPath,
            summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
            branch: "main"
        )

        let filesystemAdmission = PaneFilesystemProjectionAdmission.classify(
            .filesystem(.filesChanged(changeset: changeset))
        )
        let gitAdmission = PaneFilesystemProjectionAdmission.classify(
            .gitWorkingDirectory(.snapshotChanged(snapshot: snapshot))
        )
        let ignoredFilesystemAdmission = PaneFilesystemProjectionAdmission.classify(
            .filesystem(.worktreeRegistered(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath))
        )
        let ignoredGitAdmission = PaneFilesystemProjectionAdmission.classify(
            .gitWorkingDirectory(.originUnavailable(repoId: repoId))
        )

        #expect(filesystemAdmission.shouldProject)
        #expect(filesystemAdmission.performancePhase == "filesystem_projection")
        #expect(gitAdmission.shouldProject)
        #expect(gitAdmission.performancePhase == "git_snapshot_projection")
        #expect(!ignoredFilesystemAdmission.shouldProject)
        #expect(ignoredFilesystemAdmission.performancePhase == "ignored")
        #expect(!ignoredGitAdmission.shouldProject)
        #expect(ignoredGitAdmission.performancePhase == "ignored")
    }

    @Test("pane removal reports only the old worktree becoming inactive")
    func paneRemovalReportsOnlyOldWorktreeBecomingInactive() async {
        let repoId = UUID()
        let worktreeId = UUID()
        let paneId = UUIDv7.generate()
        let rootPath = URL(fileURLWithPath: "/tmp/repo")
        let index = FilesystemProjectionIndex()
        await seed(
            index,
            repoId: repoId,
            worktrees: [(worktreeId, rootPath)],
            pane: (paneId, worktreeId, rootPath)
        )

        let outcome = await index.applyPaneUpdate(
            FilesystemProjectionPaneUpdate(
                requestGeneration: 2,
                kind: .remove(paneId: paneId)
            )
        )

        #expect(
            outcome
                == .applied(
                    FilesystemProjectionAffectedActivity(
                        updates: [.init(worktreeId: worktreeId, isActiveInApp: false)]
                    )
                )
        )
    }

    @Test("unknown worktree update is explicitly inapplicable and preserves prior membership")
    func unknownWorktreeUpdateIsInapplicableAndPreservesPriorMembership() async {
        let repoId = UUID()
        let worktreeId = UUID()
        let unknownWorktreeId = UUID()
        let paneId = UUIDv7.generate()
        let rootPath = URL(fileURLWithPath: "/tmp/repo")
        let index = FilesystemProjectionIndex()
        await seed(
            index,
            repoId: repoId,
            worktrees: [(worktreeId, rootPath)],
            pane: (paneId, worktreeId, rootPath)
        )

        let outcome = await index.applyPaneUpdate(
            FilesystemProjectionPaneUpdate(
                requestGeneration: 2,
                kind: .upsert(
                    .init(
                        paneId: paneId,
                        paneKind: .terminal,
                        repoId: repoId,
                        worktreeId: unknownWorktreeId,
                        cwd: rootPath
                    )
                )
            )
        )

        #expect(outcome == .inapplicable)
        let result = await index.projectPaneFilesystem(
            PaneFilesystemProjectionRequest(
                requestGeneration: 3,
                paneContextGeneration: 1,
                topologyGeneration: 1,
                envelope: filesystemEnvelope(repoId: repoId, worktreeId: worktreeId, rootPath: rootPath)
            )
        )
        #expect(result.paneCount == 1)
        #expect(result.intents.count == 1)
    }

    @Test("inapplicable update completes its generation and releases projection")
    func inapplicableUpdateCompletesGenerationAndReleasesProjection() async {
        let repoId = UUID()
        let worktreeId = UUID()
        let unknownWorktreeId = UUID()
        let paneId = UUIDv7.generate()
        let rootPath = URL(fileURLWithPath: "/tmp/repo")
        let index = FilesystemProjectionIndex()
        await seed(
            index,
            repoId: repoId,
            worktrees: [(worktreeId, rootPath)],
            pane: (paneId, worktreeId, rootPath)
        )
        let projection = Task {
            await index.projectPaneFilesystem(
                PaneFilesystemProjectionRequest(
                    requestGeneration: 3,
                    paneContextGeneration: 2,
                    topologyGeneration: 1,
                    envelope: filesystemEnvelope(repoId: repoId, worktreeId: worktreeId, rootPath: rootPath)
                )
            )
        }
        await Task.yield()

        let outcome = await index.applyPaneUpdate(
            FilesystemProjectionPaneUpdate(
                requestGeneration: 2,
                kind: .upsert(
                    .init(
                        paneId: paneId,
                        paneKind: .terminal,
                        repoId: repoId,
                        worktreeId: unknownWorktreeId,
                        cwd: rootPath
                    )
                )
            )
        )
        let result = await projection.value

        #expect(outcome == .inapplicable)
        #expect(result.paneContextGeneration == 2)
        #expect(result.paneCount == 1)
        #expect(result.intents.count == 1)
    }

    @Test("affected pane updates report only changed worktree activity and reject stale work")
    func affectedPaneUpdatesReportOnlyChangedActivityAndRejectStaleWork() async {
        let repoId = UUID()
        let firstWorktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondWorktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let paneId = UUIDv7.generate()
        let firstRoot = URL(fileURLWithPath: "/tmp/repo/first")
        let secondRoot = URL(fileURLWithPath: "/tmp/repo/second")
        let index = FilesystemProjectionIndex()
        await seed(
            index,
            repoId: repoId,
            worktrees: [(firstWorktreeId, firstRoot), (secondWorktreeId, secondRoot)],
            pane: (paneId, firstWorktreeId, firstRoot)
        )

        let sameWorktreeOutcome = await index.applyPaneUpdate(
            FilesystemProjectionPaneUpdate(
                requestGeneration: 2,
                kind: .upsert(
                    .init(
                        paneId: paneId,
                        paneKind: .terminal,
                        repoId: repoId,
                        worktreeId: firstWorktreeId,
                        cwd: firstRoot.appending(path: "Sources")
                    )
                )
            )
        )
        #expect(sameWorktreeOutcome == .applied(FilesystemProjectionAffectedActivity(updates: [])))

        let movedOutcome = await index.applyPaneUpdate(
            FilesystemProjectionPaneUpdate(
                requestGeneration: 3,
                kind: .upsert(
                    .init(
                        paneId: paneId,
                        paneKind: .terminal,
                        repoId: repoId,
                        worktreeId: secondWorktreeId,
                        cwd: secondRoot
                    )
                )
            )
        )
        #expect(
            movedOutcome
                == .applied(
                    FilesystemProjectionAffectedActivity(
                        updates: [
                            .init(worktreeId: firstWorktreeId, isActiveInApp: false),
                            .init(worktreeId: secondWorktreeId, isActiveInApp: true),
                        ]
                    )
                )
        )

        let staleOutcome = await index.applyPaneUpdate(
            FilesystemProjectionPaneUpdate(
                requestGeneration: 2,
                kind: .remove(paneId: paneId)
            )
        )
        #expect(staleOutcome == .stale)
    }

    private func seed(
        _ index: FilesystemProjectionIndex,
        repoId: UUID,
        worktrees: [(UUID, URL)],
        pane: (UUID, UUID, URL)
    ) async {
        let request = FilesystemSourceSyncRequest(
            requestGeneration: 1,
            paneContextGeneration: 1,
            topologyEntries: worktrees.map { worktreeId, rootPath in
                .init(repoId: repoId, worktreeId: worktreeId, rootPath: rootPath, isUnavailable: false)
            },
            paneEntries: [
                .init(
                    paneId: pane.0,
                    paneKind: .terminal,
                    repoId: repoId,
                    worktreeId: pane.1,
                    cwd: pane.2
                )
            ],
            appliedActivityByWorktreeId: [:],
            activePaneWorktreeId: nil,
            appliedActivePaneWorktreeId: nil
        )
        _ = await index.reconcileSourceSync(request)
        _ = await index.commitSourceSync(requestGeneration: 1, topologyGeneration: 1)
    }

    private func filesystemEnvelope(repoId: UUID, worktreeId: UUID, rootPath: URL) -> RuntimeEnvelope {
        .worktree(
            WorktreeEnvelope(
                source: .system(.builtin(.filesystemWatcher)),
                seq: 1,
                timestamp: .now,
                repoId: repoId,
                worktreeId: worktreeId,
                event: .filesystem(
                    .filesChanged(
                        changeset: FileChangeset(
                            worktreeId: worktreeId,
                            repoId: repoId,
                            rootPath: rootPath,
                            paths: ["file.swift"],
                            timestamp: .now,
                            batchSeq: 1
                        )
                    )
                )
            )
        )
    }
}
