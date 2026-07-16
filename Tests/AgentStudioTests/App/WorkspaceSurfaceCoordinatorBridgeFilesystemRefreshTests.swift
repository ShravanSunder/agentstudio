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
            let store = WorkspaceStore(
                workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner())
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
                                paneId: PaneId(existingUUID: paneId),
                                repoId: headEndpoint.repoId,
                                cwd: URL(fileURLWithPath: "/tmp/worktree"),
                                worktreeId: headEndpoint.worktreeId
                            ),
                            paths: ["Sources/App/New.swift"],
                            batchSeq: 10
                        )
                    ),
                    paneId: PaneId(existingUUID: paneId)
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
    }
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
