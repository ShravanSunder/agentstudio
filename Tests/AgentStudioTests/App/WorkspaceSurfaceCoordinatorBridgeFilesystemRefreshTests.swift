import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    struct WorkspaceSurfaceBridgeFilesystemRefreshTests {
        init() {
            installTestAtomRegistryIfNeeded()
        }

        @Test("coordinator routes pane filesystem context to mounted Bridge controller")
        func coordinatorRoutesPaneFilesystemContextToMountedBridgeController() async throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appending(path: "agentstudio-bridge-filesystem-refresh-\(UUID().uuidString)")
            let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
            store.restore()
            let paneEventBus = makeTestPaneRuntimeEventBus()
            let viewRegistry = ViewRegistry()
            let coordinator = makeTestWorkspaceSurfaceCoordinator(
                store: store,
                viewRegistry: viewRegistry,
                runtime: SessionRuntime(store: store),
                surfaceManager: BridgeFilesystemRefreshSurfaceManager(),
                runtimeRegistry: RuntimeRegistry(),
                paneEventBus: paneEventBus
            )
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let baseEndpoint = makeBridgeEndpoint(endpointId: "baseline-headMinusOne", kind: .gitRef)
            let headEndpoint = makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree)
            let provider = BridgeReviewSourceProviderFake(
                comparison: BridgeEndpointComparison(
                    baseEndpoint: baseEndpoint,
                    headEndpoint: headEndpoint,
                    changedFiles: [
                        makeBridgeEndpointChangedFile(
                            fileId: "old",
                            path: "Sources/App/Old.swift",
                            sizeBytes: 100
                        )
                    ]
                ),
                contentByHandleId: [:]
            )
            let paneId = UUIDv7.generate()
            let controller = BridgePaneController(
                paneId: paneId,
                state: BridgePaneState(
                    panelKind: .diffViewer,
                    source: .workspace(rootPath: "/tmp/worktree", baseline: .headMinusOne)
                ),
                reviewSourceProvider: provider
            )
            let bridgeView = BridgePaneMountView(paneId: paneId, controller: controller)
            coordinator.registerHostedView(mountedView: bridgeView, for: paneId)
            defer { controller.teardown() }

            let commandId = UUID()
            let loadResult = await controller.handleDiffCommand(
                .loadDiff(
                    DiffArtifact(diffId: UUIDv7.generate(), worktreeId: headEndpoint.worktreeId, patchData: Data())
                ),
                commandId: commandId,
                correlationId: nil
            )
            await provider.setComparison(
                BridgeEndpointComparison(
                    baseEndpoint: baseEndpoint,
                    headEndpoint: headEndpoint,
                    changedFiles: [
                        makeBridgeEndpointChangedFile(
                            fileId: "new",
                            path: "Sources/App/New.swift",
                            sizeBytes: 100
                        )
                    ]
                )
            )

            _ = await paneEventBus.post(
                RuntimeEnvelopeHarness.paneEnvelope(
                    event: .paneFilesystemContext(
                        .cwdSubtreeChanged(
                            context: PaneFilesystemContext(
                                paneId: PaneId(uuid: paneId),
                                repoId: headEndpoint.repoId,
                                cwd: URL(fileURLWithPath: "/tmp/worktree"),
                                worktreeId: headEndpoint.worktreeId
                            ),
                            paths: ["Sources/App/New.swift"],
                            batchSeq: 10
                        )
                    ),
                    paneId: PaneId(uuid: paneId)
                )
            )

            await eventually("Bridge pane filesystem event should route through coordinator") {
                controller.paneState.diff.packageMetadata?.orderedItemIds == ["item-new"]
                    && controller.paneState.diff.packageDelta?.revision == 1
            }

            #expect(loadResult == .success(commandId: commandId))
            #expect(controller.paneState.diff.packageMetadata?.orderedItemIds == ["item-new"])
            #expect(controller.paneState.diff.packageDelta?.revision == 1)
            await coordinator.shutdown()
        }

        @Test("coordinator routes worktree file changes to active Worktree/File Bridge controller")
        func coordinatorRoutesWorktreeFileChangesToActiveWorktreeFileBridgeController() async throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appending(path: "agentstudio-bridge-worktree-file-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir.appending(path: "store")))
            store.restore()
            let paneEventBus = makeTestPaneRuntimeEventBus()
            let viewRegistry = ViewRegistry()
            let coordinator = makeTestWorkspaceSurfaceCoordinator(
                store: store,
                viewRegistry: viewRegistry,
                runtime: SessionRuntime(store: store),
                surfaceManager: BridgeFilesystemRefreshSurfaceManager(),
                runtimeRegistry: RuntimeRegistry(),
                paneEventBus: paneEventBus
            )
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let rootURL = tempDir.appending(path: "repo")
            let fileURL = rootURL.appending(path: "Sources").appending(path: "App").appending(path: "View.swift")
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try "struct View {}\n".write(to: fileURL, atomically: true, encoding: .utf8)
            let repoId = UUID(uuidString: "00000000-0000-0000-0000-000000000501")!
            let worktree = Worktree(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000502")!,
                repoId: repoId,
                name: "repo",
                path: rootURL
            )
            let paneId = UUIDv7.generate()
            let intakeCapture = BridgeWorktreeFileCoordinatorIntakeCapture()
            let controller = makeWorktreeFileBridgeController(
                capture: intakeCapture,
                paneId: paneId,
                repoId: repoId,
                rootURL: rootURL,
                title: "Worktree",
                worktree: worktree
            )
            let bridgeView = BridgePaneMountView(paneId: paneId, controller: controller)
            coordinator.registerHostedView(mountedView: bridgeView, for: paneId)
            defer { controller.teardown() }
            controller.handleBridgeReady()

            try await openCoordinatorWorktreeFileSurface(
                controller: controller,
                capture: intakeCapture,
                clientRequestId: "coordinator-file-change",
                repoId: repoId,
                rootPathToken: worktree.stableKey,
                worktreeId: worktree.id
            )

            try "struct View {}\nlet updated = true\n".write(to: fileURL, atomically: true, encoding: .utf8)
            _ = await paneEventBus.post(
                RuntimeEnvelopeHarness.filesystemEnvelope(
                    event: .filesChanged(
                        changeset: FileChangeset(
                            worktreeId: worktree.id,
                            repoId: repoId,
                            rootPath: rootURL,
                            paths: ["Sources/App/View.swift"],
                            timestamp: ContinuousClock().now,
                            batchSeq: 11
                        )
                    ),
                    repoId: repoId,
                    worktreeId: worktree.id
                )
            )

            await assertEventuallyAsync("Worktree/File change should publish intake invalidation", maxTurns: 200_000) {
                await intakeCapture.containsFrameKind("worktree.fileInvalidated")
            }
            let frameJSON = try #require(await intakeCapture.firstFrame(kind: "worktree.fileInvalidated"))
            let invalidation = try decodeCoordinatorWorktreeFileIntakeFrame(frameJSON)

            #expect(invalidation.invalidation.path == "Sources/App/View.swift")
            #expect(invalidation.invalidation.latestDescriptor?.path == "Sources/App/View.swift")
            #expect(invalidation.invalidation.latestDescriptor?.lineCount == 3)
            await coordinator.shutdown()
        }

        @Test("coordinator routes git snapshots to active Worktree/File Bridge controller")
        func coordinatorRoutesGitSnapshotsToActiveWorktreeFileBridgeController() async throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appending(path: "agentstudio-bridge-worktree-status-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir.appending(path: "store")))
            store.restore()
            let paneEventBus = makeTestPaneRuntimeEventBus()
            let viewRegistry = ViewRegistry()
            let coordinator = makeTestWorkspaceSurfaceCoordinator(
                store: store,
                viewRegistry: viewRegistry,
                runtime: SessionRuntime(store: store),
                surfaceManager: BridgeFilesystemRefreshSurfaceManager(),
                runtimeRegistry: RuntimeRegistry(),
                paneEventBus: paneEventBus
            )
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let rootURL = tempDir.appending(path: "repo")
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            let repoId = UUID(uuidString: "00000000-0000-0000-0000-000000000503")!
            let worktree = Worktree(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000504")!,
                repoId: repoId,
                name: "repo",
                path: rootURL
            )
            let paneId = UUIDv7.generate()
            let intakeCapture = BridgeWorktreeFileCoordinatorIntakeCapture()
            let controller = BridgePaneController(
                paneId: paneId,
                state: BridgePaneState(
                    panelKind: .diffViewer,
                    source: .workspace(rootPath: rootURL.path, baseline: .headMinusOne)
                ),
                metadata: PaneMetadata(
                    paneId: PaneId(uuid: paneId),
                    contentType: .diff,
                    launchDirectory: rootURL,
                    title: "Worktree",
                    facets: PaneContextFacets(
                        repoId: repoId,
                        worktreeId: worktree.id,
                        worktreeName: worktree.name,
                        cwd: rootURL
                    )
                ),
                intakeFrameSink: { _, frameJSON, _ in
                    await intakeCapture.record(frameJSON)
                }
            )
            let bridgeView = BridgePaneMountView(paneId: paneId, controller: controller)
            coordinator.registerHostedView(mountedView: bridgeView, for: paneId)
            defer { controller.teardown() }
            controller.handleBridgeReady()

            let openOutcome = try await controller.handleWorktreeFileSurfaceOpenSourceStream(
                BridgeWorktreeFileSurfaceSourceSpec(
                    clientRequestId: "coordinator-status",
                    repoId: repoId,
                    worktreeId: worktree.id,
                    rootPathToken: worktree.stableKey,
                    cwdScope: nil,
                    pathScope: [],
                    includeStatuses: true,
                    includeComments: false,
                    includeAgentComms: false,
                    freshness: .live
                )
            )
            await activateCoordinatorWorktreeFileSurface(
                controller: controller,
                outcome: openOutcome
            )
            await intakeCapture.removeAll()

            _ = await paneEventBus.post(
                RuntimeEnvelopeHarness.gitEnvelope(
                    event: .snapshotChanged(
                        snapshot: GitWorkingTreeSnapshot(
                            worktreeId: worktree.id,
                            repoId: repoId,
                            rootPath: rootURL,
                            summary: GitWorkingTreeSummary(changed: 2, staged: 1, untracked: 3),
                            branch: "feature/worktree-file"
                        )
                    ),
                    repoId: repoId,
                    worktreeId: worktree.id
                )
            )

            await assertEventuallyAsync("Worktree/File status should publish intake patch", maxTurns: 200_000) {
                await intakeCapture.containsFrameKind("worktree.statusPatch")
            }
            let frameJSON = try #require(await intakeCapture.firstFrame(kind: "worktree.statusPatch"))
            let statusPatch = try decodeCoordinatorWorktreeFileStatusPatchFrame(frameJSON)

            #expect(statusPatch.patch.staged == 1)
            #expect(statusPatch.patch.unstaged == 2)
            #expect(statusPatch.patch.untracked == 3)
            #expect(statusPatch.patch.branchName == "feature/worktree-file")
            await coordinator.shutdown()
        }

        @Test("coordinator does not fan out Worktree/File events to nonmatching Bridge controllers")
        func coordinatorDoesNotFanOutWorktreeFileEventsToNonmatchingBridgeControllers() async throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appending(path: "agentstudio-bridge-worktree-negative-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir.appending(path: "store")))
            store.restore()
            let paneEventBus = makeTestPaneRuntimeEventBus()
            let viewRegistry = ViewRegistry()
            let coordinator = makeTestWorkspaceSurfaceCoordinator(
                store: store,
                viewRegistry: viewRegistry,
                runtime: SessionRuntime(store: store),
                surfaceManager: BridgeFilesystemRefreshSurfaceManager(),
                runtimeRegistry: RuntimeRegistry(),
                paneEventBus: paneEventBus
            )
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let rootURL = tempDir.appending(path: "repo")
            let fileURL = rootURL.appending(path: "Sources").appending(path: "App").appending(path: "View.swift")
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try "struct View {}\n".write(to: fileURL, atomically: true, encoding: .utf8)
            let repoId = UUID(uuidString: "00000000-0000-0000-0000-000000000601")!
            let matchingWorktree = Worktree(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000602")!,
                repoId: repoId,
                name: "repo",
                path: rootURL
            )
            let nonmatchingWorktree = Worktree(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000603")!,
                repoId: repoId,
                name: "repo-other",
                path: rootURL
            )
            let matchingCapture = BridgeWorktreeFileCoordinatorIntakeCapture()
            let nonmatchingCapture = BridgeWorktreeFileCoordinatorIntakeCapture()
            let matchingController = makeWorktreeFileBridgeController(
                capture: matchingCapture,
                repoId: repoId,
                rootURL: rootURL,
                title: "Matching",
                worktree: matchingWorktree
            )
            let nonmatchingController = makeWorktreeFileBridgeController(
                capture: nonmatchingCapture,
                repoId: repoId,
                rootURL: rootURL,
                title: "Nonmatching",
                worktree: nonmatchingWorktree
            )
            registerWorktreeFileBridgeController(matchingController, coordinator: coordinator)
            registerWorktreeFileBridgeController(nonmatchingController, coordinator: coordinator)
            defer {
                matchingController.teardown()
                nonmatchingController.teardown()
            }
            matchingController.handleBridgeReady()
            nonmatchingController.handleBridgeReady()

            try await openCoordinatorWorktreeFileSurface(
                controller: matchingController,
                capture: matchingCapture,
                clientRequestId: "matching",
                repoId: repoId,
                rootPathToken: matchingWorktree.stableKey,
                worktreeId: matchingWorktree.id
            )
            try await openCoordinatorWorktreeFileSurface(
                controller: nonmatchingController,
                capture: nonmatchingCapture,
                clientRequestId: "nonmatching",
                repoId: repoId,
                rootPathToken: nonmatchingWorktree.stableKey,
                worktreeId: nonmatchingWorktree.id
            )

            try "struct View {}\nlet updated = true\n".write(to: fileURL, atomically: true, encoding: .utf8)
            await postCoordinatorWorktreeFileFilesystemAndGitEvents(
                paneEventBus: paneEventBus,
                repoId: repoId,
                rootURL: rootURL,
                worktreeId: matchingWorktree.id
            )

            await assertEventuallyAsync(
                "matching Worktree/File controller should receive both frames", maxTurns: 200_000
            ) {
                let hasInvalidation = await matchingCapture.containsFrameKind("worktree.fileInvalidated")
                let hasStatusPatch = await matchingCapture.containsFrameKind("worktree.statusPatch")
                return hasInvalidation && hasStatusPatch
            }

            #expect(await nonmatchingCapture.frames().isEmpty)
            await coordinator.shutdown()
        }
    }
}

private actor BridgeWorktreeFileCoordinatorIntakeCapture {
    private var capturedFrames: [String] = []

    func record(_ frameJSON: String) {
        capturedFrames.append(frameJSON)
    }

    func frames() -> [String] {
        capturedFrames
    }

    func removeAll() {
        capturedFrames.removeAll()
    }

    func containsFrameKind(_ frameKind: String) -> Bool {
        firstFrame(kind: frameKind) != nil
    }

    func firstFrame(kind frameKind: String) -> String? {
        capturedFrames.first { frameJSON in
            coordinatorWorktreeFileFrameKind(frameJSON) == frameKind
        }
    }
}

private func coordinatorWorktreeFileFrameKind(_ frameJSON: String) -> String? {
    guard let data = frameJSON.data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let payload = object["payload"] as? [String: Any]
    else {
        return nil
    }
    return payload["frameKind"] as? String
}

private struct BridgeWorktreeFileCoordinatorIntakeEnvelope<TPayload: Decodable>: Decodable {
    let payload: TPayload
}

private func decodeCoordinatorWorktreeFileIntakeFrame(
    _ frameJSON: String
) throws -> BridgeWorktreeFileInvalidatedFrame {
    let frameData = try #require(frameJSON.data(using: .utf8))
    return try JSONDecoder().decode(
        BridgeWorktreeFileCoordinatorIntakeEnvelope<BridgeWorktreeFileInvalidatedFrame>.self,
        from: frameData
    ).payload
}

private func decodeCoordinatorWorktreeFileStatusPatchFrame(
    _ frameJSON: String
) throws -> BridgeWorktreeStatusPatchFrame {
    let frameData = try #require(frameJSON.data(using: .utf8))
    return try JSONDecoder().decode(
        BridgeWorktreeFileCoordinatorIntakeEnvelope<BridgeWorktreeStatusPatchFrame>.self,
        from: frameData
    ).payload
}

@MainActor
private func makeWorktreeFileBridgeController(
    capture: BridgeWorktreeFileCoordinatorIntakeCapture,
    paneId: UUID = UUIDv7.generate(),
    repoId: UUID,
    rootURL: URL,
    title: String,
    worktree: Worktree
) -> BridgePaneController {
    BridgePaneController(
        paneId: paneId,
        state: BridgePaneState(
            panelKind: .diffViewer,
            source: .workspace(rootPath: rootURL.path, baseline: .headMinusOne)
        ),
        metadata: PaneMetadata(
            paneId: PaneId(uuid: paneId),
            contentType: .diff,
            launchDirectory: rootURL,
            title: title,
            facets: PaneContextFacets(
                repoId: repoId,
                worktreeId: worktree.id,
                worktreeName: worktree.name,
                cwd: rootURL
            )
        ),
        intakeFrameSink: { _, frameJSON, _ in
            await capture.record(frameJSON)
        }
    )
}

@MainActor
private func registerWorktreeFileBridgeController(
    _ controller: BridgePaneController,
    coordinator: WorkspaceSurfaceCoordinator
) {
    coordinator.registerHostedView(
        mountedView: BridgePaneMountView(paneId: controller.paneId, controller: controller),
        for: controller.paneId
    )
}

@MainActor
private func openCoordinatorWorktreeFileSurface(
    controller: BridgePaneController,
    capture: BridgeWorktreeFileCoordinatorIntakeCapture,
    clientRequestId: String,
    repoId: UUID,
    rootPathToken: String,
    worktreeId: UUID
) async throws {
    let openOutcome = try await controller.handleWorktreeFileSurfaceOpenSourceStream(
        makeCoordinatorWorktreeFileSourceSpec(
            clientRequestId: clientRequestId,
            repoId: repoId,
            rootPathToken: rootPathToken,
            worktreeId: worktreeId
        )
    )
    await activateCoordinatorWorktreeFileSurface(
        controller: controller,
        outcome: openOutcome
    )
    await capture.removeAll()
}

private func makeCoordinatorWorktreeFileSourceSpec(
    clientRequestId: String,
    repoId: UUID,
    rootPathToken: String,
    worktreeId: UUID
) -> BridgeWorktreeFileSurfaceSourceSpec {
    BridgeWorktreeFileSurfaceSourceSpec(
        clientRequestId: clientRequestId,
        repoId: repoId,
        worktreeId: worktreeId,
        rootPathToken: rootPathToken,
        cwdScope: nil,
        pathScope: [],
        includeStatuses: true,
        includeComments: false,
        includeAgentComms: false,
        freshness: .live
    )
}

private func postCoordinatorWorktreeFileFilesystemAndGitEvents(
    paneEventBus: EventBus<RuntimeEnvelope>,
    repoId: UUID,
    rootURL: URL,
    worktreeId: UUID
) async {
    _ = await paneEventBus.post(
        RuntimeEnvelopeHarness.filesystemEnvelope(
            event: .filesChanged(
                changeset: FileChangeset(
                    worktreeId: worktreeId,
                    repoId: repoId,
                    rootPath: rootURL,
                    paths: ["Sources/App/View.swift"],
                    timestamp: ContinuousClock().now,
                    batchSeq: 12
                )
            ),
            repoId: repoId,
            worktreeId: worktreeId
        )
    )
    _ = await paneEventBus.post(
        RuntimeEnvelopeHarness.gitEnvelope(
            event: .snapshotChanged(
                snapshot: GitWorkingTreeSnapshot(
                    worktreeId: worktreeId,
                    repoId: repoId,
                    rootPath: rootURL,
                    summary: GitWorkingTreeSummary(changed: 4, staged: 2, untracked: 1),
                    branch: "feature/matching"
                )
            ),
            repoId: repoId,
            worktreeId: worktreeId
        )
    )
}

@MainActor
private func activateCoordinatorWorktreeFileSurface(
    controller: BridgePaneController,
    outcome: BridgeWorktreeFileSurfaceOpenSourceOutcome
) async {
    await controller.activeWorktreeFileTreeWindowTask?.value
    await controller.handleBridgeIntakeReady(
        BridgeIntakeReadyMethod.Params(
            protocolId: "worktree-file",
            streamId: outcome.streamId,
            generation: outcome.generation
        )
    )
    await controller.handleBridgeActiveViewerModeUpdate(
        BridgeActiveViewerModeUpdateMethod.Params(
            sessionId: "coordinator-worktree-file-\(controller.paneId.uuidString)",
            sequence: 2,
            mode: .file,
            activeSource: BridgeActiveViewerSource(
                protocolId: .worktreeFile,
                streamId: outcome.streamId,
                generation: outcome.generation
            )
        )
    )
    await controller.worktreeFileMetadataScheduler.waitUntilDrained()
}

@MainActor
private final class BridgeFilesystemRefreshSurfaceManager: WorkspaceSurfaceManaging {
    private let cwdStream = AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { continuation in
        continuation.finish()
    }

    var surfaceCWDChanges: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> {
        cwdStream
    }

    func syncFocus(activeSurfaceId _: UUID?) {}

    func createSurface(
        config _: Ghostty.SurfaceConfiguration,
        metadata _: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        .failure(.ghosttyNotInitialized)
    }

    func attach(_: UUID, to _: UUID) -> Ghostty.SurfaceView? {
        nil
    }

    func detach(_: UUID, reason _: SurfaceDetachReason) {}

    func undoClose() -> ManagedSurface? {
        nil
    }

    func requeueUndo(_: UUID) {}

    func destroy(_: UUID) {}
}
