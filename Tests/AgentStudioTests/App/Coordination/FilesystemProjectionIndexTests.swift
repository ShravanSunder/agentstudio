import Foundation
import Testing

@testable import AgentStudio

@Suite
struct FilesystemProjectionIndexTests {
    @Test("source sync diff normalizes roots and returns deterministic source writes")
    func sourceSyncDiffNormalizesRootsAndReturnsDeterministicWrites() async {
        let repoId = UUID()
        let activeWorktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let idleWorktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let activePaneId = UUIDv7.generate()
        let index = FilesystemProjectionIndex()

        let diff = await index.reconcileSourceSync(
            FilesystemSourceSyncRequest(
                requestGeneration: 1,
                paneContextGeneration: 1,
                topologyEntries: [
                    .init(
                        repoId: repoId,
                        worktreeId: idleWorktreeId,
                        rootPath: URL(fileURLWithPath: "/tmp/repo/idle/../idle"),
                        isUnavailable: false
                    ),
                    .init(
                        repoId: repoId,
                        worktreeId: activeWorktreeId,
                        rootPath: URL(fileURLWithPath: "/tmp/repo/active"),
                        isUnavailable: false
                    ),
                ],
                paneEntries: [
                    .init(
                        paneId: activePaneId,
                        paneKind: .terminal,
                        repoId: repoId,
                        worktreeId: activeWorktreeId,
                        cwd: URL(fileURLWithPath: "/tmp/repo/active")
                    )
                ],
                appliedContextsByWorktreeId: [:],
                appliedActivityByWorktreeId: [:],
                activePaneWorktreeId: activeWorktreeId,
                appliedActivePaneWorktreeId: nil
            )
        )

        #expect(diff.requestGeneration == 1)
        #expect(diff.unregisterWorktreeIds.isEmpty)
        #expect(diff.registerWorktrees.map(\.worktreeId) == [activeWorktreeId, idleWorktreeId])
        #expect(
            diff.activityUpdates == [
                .init(worktreeId: activeWorktreeId, isActiveInApp: true),
                .init(worktreeId: idleWorktreeId, isActiveInApp: false),
            ])
        #expect(diff.shouldUpdateActivePaneWorktree)
        #expect(diff.activePaneWorktreeId == activeWorktreeId)
        #expect(diff.validPaneIds == [activePaneId])
        #expect(diff.validWorktreeIds == [activeWorktreeId, idleWorktreeId])
        #expect(diff.contextsByWorktreeId[activeWorktreeId]?.rootPath.path == "/tmp/repo/active")
        #expect(diff.contextsByWorktreeId[idleWorktreeId]?.rootPath.path == "/tmp/repo/idle")
    }

    @Test("identical source sync produces no source writes")
    func identicalSourceSyncProducesNoSourceWrites() async {
        let repoId = UUID()
        let worktreeId = UUID()
        let paneId = UUIDv7.generate()
        let rootPath = URL(fileURLWithPath: "/tmp/repo")
        let index = FilesystemProjectionIndex()
        let request = FilesystemSourceSyncRequest(
            requestGeneration: 1,
            paneContextGeneration: 1,
            topologyEntries: [
                .init(repoId: repoId, worktreeId: worktreeId, rootPath: rootPath, isUnavailable: false)
            ],
            paneEntries: [
                .init(paneId: paneId, paneKind: .terminal, repoId: repoId, worktreeId: worktreeId, cwd: rootPath)
            ],
            appliedContextsByWorktreeId: [:],
            appliedActivityByWorktreeId: [:],
            activePaneWorktreeId: worktreeId,
            appliedActivePaneWorktreeId: nil
        )

        _ = await reconcileAndCommit(index, request, topologyGeneration: 1)
        let secondAppliedActivity = [worktreeId: true]
        let secondDiff = await index.reconcileSourceSync(
            FilesystemSourceSyncRequest(
                requestGeneration: 2,
                paneContextGeneration: 1,
                topologyEntries: request.topologyEntries,
                paneEntries: request.paneEntries,
                appliedContextsByWorktreeId: [
                    worktreeId: WorktreeFilesystemContext(repoId: repoId, rootPath: rootPath)
                ],
                appliedActivityByWorktreeId: secondAppliedActivity,
                activePaneWorktreeId: worktreeId,
                appliedActivePaneWorktreeId: worktreeId
            )
        )

        #expect(secondDiff.unregisterWorktreeIds.isEmpty)
        #expect(secondDiff.registerWorktrees.isEmpty)
        #expect(secondDiff.activityUpdates.isEmpty)
        #expect(!secondDiff.shouldUpdateActivePaneWorktree)
    }

    @Test("source sync activity diff uses applied source baseline")
    func sourceSyncActivityDiffUsesAppliedSourceBaseline() async {
        let repoId = UUID()
        let worktreeId = UUID()
        let paneId = UUIDv7.generate()
        let rootPath = URL(fileURLWithPath: "/tmp/repo")
        let index = FilesystemProjectionIndex()
        _ = await reconcileAndCommit(
            index,
            FilesystemSourceSyncRequest(
                requestGeneration: 1,
                paneContextGeneration: 1,
                topologyEntries: [
                    .init(repoId: repoId, worktreeId: worktreeId, rootPath: rootPath, isUnavailable: false)
                ],
                paneEntries: [],
                appliedContextsByWorktreeId: [:],
                appliedActivityByWorktreeId: [:],
                activePaneWorktreeId: nil,
                appliedActivePaneWorktreeId: nil
            ),
            topologyGeneration: 1
        )

        await index.applyPaneUpdate(
            FilesystemProjectionPaneUpdate(
                requestGeneration: 2,
                kind: .upsert(
                    .init(
                        paneId: paneId,
                        paneKind: .terminal,
                        repoId: repoId,
                        worktreeId: worktreeId,
                        cwd: rootPath
                    )
                )
            )
        )

        let diff = await index.reconcileSourceSync(
            FilesystemSourceSyncRequest(
                requestGeneration: 2,
                paneContextGeneration: 2,
                topologyEntries: [
                    .init(repoId: repoId, worktreeId: worktreeId, rootPath: rootPath, isUnavailable: false)
                ],
                paneEntries: [
                    .init(paneId: paneId, paneKind: .terminal, repoId: repoId, worktreeId: worktreeId, cwd: rootPath)
                ],
                appliedContextsByWorktreeId: [
                    worktreeId: WorktreeFilesystemContext(repoId: repoId, rootPath: rootPath)
                ],
                appliedActivityByWorktreeId: [worktreeId: false],
                activePaneWorktreeId: nil,
                appliedActivePaneWorktreeId: nil
            )
        )

        #expect(diff.activityUpdates == [.init(worktreeId: worktreeId, isActiveInApp: true)])
    }

    @Test("source sync registration diff uses applied source baseline")
    func sourceSyncRegistrationDiffUsesAppliedSourceBaseline() async {
        let repoId = UUID()
        let worktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/repo")
        let index = FilesystemProjectionIndex()
        let request = FilesystemSourceSyncRequest(
            requestGeneration: 1,
            paneContextGeneration: 1,
            topologyEntries: [
                .init(repoId: repoId, worktreeId: worktreeId, rootPath: rootPath, isUnavailable: false)
            ],
            paneEntries: [],
            appliedContextsByWorktreeId: [:],
            appliedActivityByWorktreeId: [:],
            activePaneWorktreeId: nil,
            appliedActivePaneWorktreeId: nil
        )
        _ = await reconcileAndCommit(index, request, topologyGeneration: 1)

        let diff = await index.reconcileSourceSync(
            FilesystemSourceSyncRequest(
                requestGeneration: 2,
                paneContextGeneration: 1,
                topologyEntries: request.topologyEntries,
                paneEntries: request.paneEntries,
                appliedContextsByWorktreeId: [:],
                appliedActivityByWorktreeId: [worktreeId: false],
                activePaneWorktreeId: nil,
                appliedActivePaneWorktreeId: nil
            )
        )

        #expect(diff.registerWorktrees.map(\.worktreeId) == [worktreeId])
    }

    @Test("filesystem projection filters paths by indexed pane cwd")
    func filesystemProjectionFiltersPathsByIndexedPaneCwd() async {
        let repoId = UUID()
        let worktreeId = UUID()
        let paneId = UUIDv7.generate()
        let rootPath = URL(fileURLWithPath: "/tmp/repo")
        let index = FilesystemProjectionIndex()
        _ = await reconcileAndCommit(
            index,
            FilesystemSourceSyncRequest(
                requestGeneration: 1,
                paneContextGeneration: 1,
                topologyEntries: [
                    .init(repoId: repoId, worktreeId: worktreeId, rootPath: rootPath, isUnavailable: false)
                ],
                paneEntries: [
                    .init(
                        paneId: paneId,
                        paneKind: .terminal,
                        repoId: repoId,
                        worktreeId: worktreeId,
                        cwd: rootPath.appending(path: "src")
                    )
                ],
                appliedContextsByWorktreeId: [:],
                appliedActivityByWorktreeId: [:],
                activePaneWorktreeId: worktreeId,
                appliedActivePaneWorktreeId: nil
            ),
            topologyGeneration: 4
        )

        let result = await index.projectPaneFilesystem(
            PaneFilesystemProjectionRequest(
                requestGeneration: 2,
                paneContextGeneration: 1,
                topologyGeneration: 4,
                envelope: .worktree(
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
                                    paths: ["src/main.swift", "README.md", "src/main.swift"],
                                    timestamp: .now,
                                    batchSeq: 8
                                )
                            )
                        )
                    )
                )
            )
        )

        #expect(result.requestGeneration == 2)
        #expect(result.paneContextGeneration == 1)
        #expect(result.topologyGeneration == 4)
        #expect(result.worktreeCount == 1)
        #expect(result.paneCount == 1)
        #expect(result.intents.count == 1)
        guard case .cwdSubtreeChanged(let projection) = result.intents[0] else {
            Issue.record("Expected cwdSubtreeChanged intent")
            return
        }
        #expect(projection.context.paneId.uuid == paneId)
        #expect(projection.context.repoId == repoId)
        #expect(projection.context.worktreeId == worktreeId)
        #expect(projection.paths == ["src/main.swift"])
        #expect(projection.batchSequence == 8)
    }

    @Test("incremental pane update changes filtering cache")
    func incrementalPaneUpdateChangesFilteringCache() async {
        let repoId = UUID()
        let worktreeId = UUID()
        let paneId = UUIDv7.generate()
        let rootPath = URL(fileURLWithPath: "/tmp/repo")
        let index = FilesystemProjectionIndex()
        _ = await reconcileAndCommit(
            index,
            FilesystemSourceSyncRequest(
                requestGeneration: 1,
                paneContextGeneration: 1,
                topologyEntries: [
                    .init(repoId: repoId, worktreeId: worktreeId, rootPath: rootPath, isUnavailable: false)
                ],
                paneEntries: [
                    .init(
                        paneId: paneId,
                        paneKind: .terminal,
                        repoId: repoId,
                        worktreeId: worktreeId,
                        cwd: rootPath.appending(path: "src")
                    )
                ],
                appliedContextsByWorktreeId: [:],
                appliedActivityByWorktreeId: [:],
                activePaneWorktreeId: worktreeId,
                appliedActivePaneWorktreeId: nil
            ),
            topologyGeneration: 5
        )
        await index.applyPaneUpdate(
            FilesystemProjectionPaneUpdate(
                requestGeneration: 2,
                kind: .upsert(
                    .init(
                        paneId: paneId,
                        paneKind: .terminal,
                        repoId: repoId,
                        worktreeId: worktreeId,
                        cwd: rootPath.appending(path: "docs")
                    )
                )
            )
        )

        let result = await index.projectPaneFilesystem(
            PaneFilesystemProjectionRequest(
                requestGeneration: 3,
                paneContextGeneration: 2,
                topologyGeneration: 5,
                envelope: .worktree(
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
                                    paths: ["src/main.swift", "docs/readme.md"],
                                    timestamp: .now,
                                    batchSeq: 9
                                )
                            )
                        )
                    )
                )
            )
        )

        guard case .cwdSubtreeChanged(let projection) = result.intents.first else {
            Issue.record("Expected cwdSubtreeChanged intent")
            return
        }
        #expect(projection.paths == ["docs/readme.md"])
    }

    @Test("projection waits for requested pane generation")
    func projectionWaitsForRequestedPaneGeneration() async {
        let repoId = UUID()
        let worktreeId = UUID()
        let paneId = UUIDv7.generate()
        let rootPath = URL(fileURLWithPath: "/tmp/repo")
        let index = FilesystemProjectionIndex()
        _ = await reconcileAndCommit(
            index,
            FilesystemSourceSyncRequest(
                requestGeneration: 1,
                paneContextGeneration: 1,
                topologyEntries: [
                    .init(repoId: repoId, worktreeId: worktreeId, rootPath: rootPath, isUnavailable: false)
                ],
                paneEntries: [
                    .init(
                        paneId: paneId,
                        paneKind: .terminal,
                        repoId: repoId,
                        worktreeId: worktreeId,
                        cwd: rootPath.appending(path: "src")
                    )
                ],
                appliedContextsByWorktreeId: [:],
                appliedActivityByWorktreeId: [:],
                activePaneWorktreeId: nil,
                appliedActivePaneWorktreeId: nil
            ),
            topologyGeneration: 1
        )

        let projectionTask = Task {
            await index.projectPaneFilesystem(
                PaneFilesystemProjectionRequest(
                    requestGeneration: 2,
                    paneContextGeneration: 2,
                    topologyGeneration: 1,
                    envelope: .worktree(
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
                                        paths: ["src/main.swift", "docs/readme.md"],
                                        timestamp: .now,
                                        batchSeq: 9
                                    )
                                )
                            )
                        )
                    )
                )
            )
        }
        await Task.yield()
        await index.applyPaneUpdate(
            FilesystemProjectionPaneUpdate(
                requestGeneration: 2,
                kind: .upsert(
                    .init(
                        paneId: paneId,
                        paneKind: .terminal,
                        repoId: repoId,
                        worktreeId: worktreeId,
                        cwd: rootPath.appending(path: "docs")
                    )
                )
            )
        )

        let result = await projectionTask.value
        guard case .cwdSubtreeChanged(let projection) = result.intents.first else {
            Issue.record("Expected cwdSubtreeChanged intent")
            return
        }
        #expect(projection.paths == ["docs/readme.md"])
    }

    @Test("shutdown retires a projection waiting for a discarded pane generation")
    func shutdownRetiresProjectionWaitingForDiscardedPaneGeneration() async {
        let repoId = UUID()
        let worktreeId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/repo")
        let index = FilesystemProjectionIndex()

        let projectionTask = Task {
            await index.projectPaneFilesystem(
                PaneFilesystemProjectionRequest(
                    requestGeneration: 1,
                    paneContextGeneration: 1,
                    topologyGeneration: 0,
                    envelope: filesystemEnvelope(
                        repoId: repoId,
                        worktreeId: worktreeId,
                        rootPath: rootPath
                    )
                )
            )
        }

        await Task.yield()
        await index.shutdown()
        let result = await projectionTask.value

        #expect(result.intents.isEmpty)
        #expect(result.paneCount == 0)
        #expect(result.worktreeCount == 0)
    }

    @Test("pane removal prunes projection facts")
    func paneRemovalPrunesProjectionFacts() async {
        let repoId = UUID()
        let worktreeId = UUID()
        let paneId = UUIDv7.generate()
        let rootPath = URL(fileURLWithPath: "/tmp/repo")
        let index = FilesystemProjectionIndex()
        _ = await reconcileAndCommit(
            index,
            FilesystemSourceSyncRequest(
                requestGeneration: 1,
                paneContextGeneration: 1,
                topologyEntries: [
                    .init(repoId: repoId, worktreeId: worktreeId, rootPath: rootPath, isUnavailable: false)
                ],
                paneEntries: [
                    .init(paneId: paneId, paneKind: .terminal, repoId: repoId, worktreeId: worktreeId, cwd: rootPath)
                ],
                appliedContextsByWorktreeId: [:],
                appliedActivityByWorktreeId: [:],
                activePaneWorktreeId: worktreeId,
                appliedActivePaneWorktreeId: nil
            ),
            topologyGeneration: 5
        )
        await index.applyPaneUpdate(
            FilesystemProjectionPaneUpdate(
                requestGeneration: 2,
                kind: .remove(paneId: paneId)
            )
        )

        let result = await index.projectPaneFilesystem(
            PaneFilesystemProjectionRequest(
                requestGeneration: 3,
                paneContextGeneration: 2,
                topologyGeneration: 5,
                envelope: .worktree(
                    WorktreeEnvelope(
                        source: .system(.builtin(.gitWorkingDirectoryProjector)),
                        seq: 1,
                        timestamp: .now,
                        repoId: repoId,
                        worktreeId: worktreeId,
                        event: .gitWorkingDirectory(
                            .snapshotChanged(
                                snapshot: GitWorkingTreeSnapshot(
                                    worktreeId: worktreeId,
                                    repoId: repoId,
                                    rootPath: rootPath,
                                    summary: GitWorkingTreeSummary(changed: 1, staged: 2, untracked: 3),
                                    branch: "main"
                                )
                            )
                        )
                    )
                )
            )
        )

        #expect(result.intents.isEmpty)
        #expect(result.paneCount == 0)
    }

    @Test("projection reports committed topology snapshot generation")
    func projectionReportsCommittedTopologySnapshotGeneration() async {
        let repoId = UUID()
        let oldWorktreeId = UUID()
        let newWorktreeId = UUID()
        let paneId = UUIDv7.generate()
        let rootPath = URL(fileURLWithPath: "/tmp/repo")
        let index = FilesystemProjectionIndex()
        let oldRequest = FilesystemSourceSyncRequest(
            requestGeneration: 1,
            paneContextGeneration: 1,
            topologyEntries: [
                .init(repoId: repoId, worktreeId: oldWorktreeId, rootPath: rootPath, isUnavailable: false)
            ],
            paneEntries: [
                .init(paneId: paneId, paneKind: .terminal, repoId: repoId, worktreeId: oldWorktreeId, cwd: rootPath)
            ],
            appliedContextsByWorktreeId: [:],
            appliedActivityByWorktreeId: [:],
            activePaneWorktreeId: nil,
            appliedActivePaneWorktreeId: nil
        )
        _ = await reconcileAndCommit(index, oldRequest, topologyGeneration: 10)

        _ = await index.reconcileSourceSync(
            FilesystemSourceSyncRequest(
                requestGeneration: 2,
                paneContextGeneration: 1,
                topologyEntries: [
                    .init(repoId: repoId, worktreeId: newWorktreeId, rootPath: rootPath, isUnavailable: false)
                ],
                paneEntries: [
                    .init(paneId: paneId, paneKind: .terminal, repoId: repoId, worktreeId: newWorktreeId, cwd: rootPath)
                ],
                appliedContextsByWorktreeId: [
                    oldWorktreeId: WorktreeFilesystemContext(repoId: repoId, rootPath: rootPath)
                ],
                appliedActivityByWorktreeId: [:],
                activePaneWorktreeId: nil,
                appliedActivePaneWorktreeId: nil
            )
        )

        let uncommittedResult = await index.projectPaneFilesystem(
            PaneFilesystemProjectionRequest(
                requestGeneration: 3,
                paneContextGeneration: 1,
                topologyGeneration: 10,
                envelope: filesystemEnvelope(repoId: repoId, worktreeId: newWorktreeId, rootPath: rootPath)
            )
        )
        #expect(uncommittedResult.topologyGeneration == 10)
        #expect(uncommittedResult.intents.isEmpty)

        _ = await index.commitSourceSync(requestGeneration: 2, topologyGeneration: 11)
        let committedResult = await index.projectPaneFilesystem(
            PaneFilesystemProjectionRequest(
                requestGeneration: 4,
                paneContextGeneration: 1,
                topologyGeneration: 11,
                envelope: filesystemEnvelope(repoId: repoId, worktreeId: newWorktreeId, rootPath: rootPath)
            )
        )
        #expect(committedResult.topologyGeneration == 11)
        #expect(committedResult.intents.count == 1)
    }

    @Test("stale source sync commit does not roll back newer pane update")
    func staleSourceSyncCommitDoesNotRollBackNewerPaneUpdate() async {
        let (repoId, worktreeId) = (UUID(), UUID())
        let paneId = UUIDv7.generate()
        let rootPath = URL(fileURLWithPath: "/tmp/repo")
        let index = FilesystemProjectionIndex()
        _ = await reconcileAndCommit(
            index,
            FilesystemSourceSyncRequest(
                requestGeneration: 1,
                paneContextGeneration: 1,
                topologyEntries: [
                    .init(repoId: repoId, worktreeId: worktreeId, rootPath: rootPath, isUnavailable: false)
                ],
                paneEntries: [
                    .init(
                        paneId: paneId,
                        paneKind: .terminal,
                        repoId: repoId,
                        worktreeId: worktreeId,
                        cwd: rootPath.appending(path: "src")
                    )
                ],
                appliedContextsByWorktreeId: [:],
                appliedActivityByWorktreeId: [:],
                activePaneWorktreeId: nil,
                appliedActivePaneWorktreeId: nil
            ),
            topologyGeneration: 10
        )

        _ = await index.reconcileSourceSync(
            FilesystemSourceSyncRequest(
                requestGeneration: 2,
                paneContextGeneration: 1,
                topologyEntries: [
                    .init(repoId: repoId, worktreeId: worktreeId, rootPath: rootPath, isUnavailable: false)
                ],
                paneEntries: [
                    .init(
                        paneId: paneId,
                        paneKind: .terminal,
                        repoId: repoId,
                        worktreeId: worktreeId,
                        cwd: rootPath.appending(path: "src")
                    )
                ],
                appliedContextsByWorktreeId: [worktreeId: .init(repoId: repoId, rootPath: rootPath)],
                appliedActivityByWorktreeId: [worktreeId: true],
                activePaneWorktreeId: nil,
                appliedActivePaneWorktreeId: nil
            )
        )
        await index.applyPaneUpdate(
            FilesystemProjectionPaneUpdate(
                requestGeneration: 2,
                kind: .upsert(
                    .init(
                        paneId: paneId,
                        paneKind: .terminal,
                        repoId: repoId,
                        worktreeId: worktreeId,
                        cwd: rootPath.appending(path: "docs")
                    )
                )
            )
        )

        let didCommit = await index.commitSourceSync(requestGeneration: 2, topologyGeneration: 11)
        #expect(!didCommit)

        let result = await index.projectPaneFilesystem(
            PaneFilesystemProjectionRequest(
                requestGeneration: 3,
                paneContextGeneration: 2,
                topologyGeneration: 10,
                envelope: .worktree(
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
                                    paths: ["src/main.swift", "docs/readme.md"],
                                    timestamp: .now,
                                    batchSeq: 10
                                )
                            )
                        )
                    )
                )
            )
        )

        #expect(result.topologyGeneration == 10)
        guard case .cwdSubtreeChanged(let projection) = result.intents.first else {
            Issue.record("Expected cwdSubtreeChanged intent")
            return
        }
        #expect(projection.paths == ["docs/readme.md"])
    }

    private func reconcileAndCommit(
        _ index: FilesystemProjectionIndex,
        _ request: FilesystemSourceSyncRequest,
        topologyGeneration: UInt64
    ) async -> FilesystemSourceSyncDiff {
        let diff = await index.reconcileSourceSync(request)
        _ = await index.commitSourceSync(
            requestGeneration: request.requestGeneration,
            topologyGeneration: topologyGeneration
        )
        return diff
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
                            paths: ["Sources/App.swift"],
                            timestamp: .now,
                            batchSeq: 1
                        )
                    )
                )
            )
        )
    }
}
