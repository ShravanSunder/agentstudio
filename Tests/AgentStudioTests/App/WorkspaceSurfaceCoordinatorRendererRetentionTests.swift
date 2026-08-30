import AppKit
import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTerminal
@testable import AgentStudioTestSupport

@MainActor
@Suite("Workspace surface renderer retention", .serialized)
struct WorkspaceSurfaceCoordinatorRendererRetentionTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("repair permanently releases the exact renderer without entering close undo")
    func repairPermanentlyReleasesExactRenderer() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDirectory) }
        let pane = harness.store.createPane(launchDirectory: harness.tempDirectory, provider: .zmx)
        harness.store.appendTab(Tab(paneId: pane.id))
        let surfaceID = UUIDv7.generate()
        let mountedView = TerminalPaneMountView(
            restoredSurfaceId: surfaceID,
            paneId: pane.id,
            title: "Repair"
        )
        harness.coordinator.registerHostedView(mountedView: mountedView, for: pane.id)

        harness.coordinator.execute(.repair(.recreateSurface(paneId: pane.id)))

        #expect(
            harness.surfaceManager.permanentReleaseCalls == [
                .init(surfaceID: surfaceID, reason: .repairReplacement)
            ]
        )
        #expect(harness.surfaceManager.detachCalls.isEmpty)
    }

    @Test("workspace undo capacity eviction permanently releases the evicted pane surface")
    func undoCapacityEvictionReleasesEvictedPaneSurface() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDirectory) }
        var closedPaneIDs: [UUID] = []
        for index in 0...harness.coordinator.maxUndoStackSize {
            let pane = harness.store.createPane(
                content: .webview(
                    WebviewState(url: URL(string: "https://example.com/\(index)")!, showNavigation: true)
                ),
                metadata: PaneMetadata(title: "Pane \(index)")
            )
            let tab = Tab(paneId: pane.id)
            harness.store.appendTab(tab)
            harness.coordinator.execute(.closeTab(tabId: tab.id))
            closedPaneIDs.append(pane.id)
        }
        let evictedPaneID = try #require(closedPaneIDs.first)

        #expect(
            harness.surfaceManager.closedSurfaceReleaseCalls == [
                .init(paneID: evictedPaneID, reason: .explicitRemoval)
            ]
        )
    }

    @Test("floating terminal attach failure releases the created surface as creation rollback")
    func floatingTerminalAttachFailureUsesCreationRollback() {
        let surfaceID = UUIDv7.generate()
        let surfaceView = Ghostty.SurfaceView(
            bareManagedSurfaceID: surfaceID,
            appCommandDispatcher: RendererRetentionNoOpAppCommandDispatcher()
        )
        let managedSurface = ManagedSurface(
            id: surfaceID,
            surface: surfaceView,
            metadata: SurfaceMetadata()
        )
        let harness = makeHarness(createSurfaceResult: .success(managedSurface))
        defer { try? FileManager.default.removeItem(at: harness.tempDirectory) }
        let pane = harness.store.createPane(launchDirectory: harness.tempDirectory, provider: .zmx)

        _ = harness.coordinator.createTopologyIndependentTerminalView(
            for: pane,
            initialFrame: CGRect(x: 0, y: 0, width: 1000, height: 600)
        )

        #expect(
            harness.surfaceManager.permanentReleaseCalls == [
                .init(surfaceID: surfaceID, reason: .creationRollback)
            ]
        )
        #expect(harness.surfaceManager.detachCalls.isEmpty)
    }

    private struct Harness {
        let store: WorkspaceStore
        let coordinator: WorkspaceSurfaceCoordinator
        let surfaceManager: RendererRetentionSurfaceManager
        let tempDirectory: URL
    }

    private func makeHarness(
        createSurfaceResult: Result<ManagedSurface, SurfaceError> = .failure(.ghosttyNotInitialized)
    ) -> Harness {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-renderer-retention-\(UUID().uuidString)")
        let store = WorkspaceStore()
        let surfaceManager = RendererRetentionSurfaceManager(createSurfaceResult: createSurfaceResult)
        let coordinator = WorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: ViewRegistry(),
            runtime: SessionRuntime(store: store),
            surfaceManager: surfaceManager,
            runtimeRegistry: RuntimeRegistry(),
            windowLifecycleStore: WindowLifecycleAtom(),
            bridgePaneAttendance: BridgePaneAttendanceAtom()
        )
        return Harness(
            store: store,
            coordinator: coordinator,
            surfaceManager: surfaceManager,
            tempDirectory: tempDirectory
        )
    }
}

@MainActor
private final class RendererRetentionSurfaceManager: WorkspaceSurfaceManaging {
    struct PermanentReleaseCall: Equatable {
        let surfaceID: UUID
        let reason: SurfacePermanentReleaseReason
    }

    struct ClosedSurfaceReleaseCall: Equatable {
        let paneID: UUID
        let reason: SurfacePermanentReleaseReason
    }

    private let createSurfaceResult: Result<ManagedSurface, SurfaceError>
    private(set) var detachCalls: [(surfaceID: UUID, reason: SurfaceDetachReason)] = []
    private(set) var permanentReleaseCalls: [PermanentReleaseCall] = []
    private(set) var closedSurfaceReleaseCalls: [ClosedSurfaceReleaseCall] = []

    init(createSurfaceResult: Result<ManagedSurface, SurfaceError>) {
        self.createSurfaceResult = createSurfaceResult
    }

    func syncFocus(activeSurfaceId _: UUID?) {}

    func createSurface(
        config _: Ghostty.SurfaceConfiguration,
        metadata _: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        createSurfaceResult
    }

    func attach(_: UUID, to _: UUID) -> Ghostty.SurfaceView? { nil }

    func detach(_ surfaceID: UUID, reason: SurfaceDetachReason) {
        detachCalls.append((surfaceID, reason))
    }

    func permanentlyRelease(
        _ surfaceID: UUID,
        reason: SurfacePermanentReleaseReason
    ) -> SurfacePermanentReleaseResult {
        permanentReleaseCalls.append(.init(surfaceID: surfaceID, reason: reason))
        return .released
    }

    func permanentlyReleaseClosedSurface(
        forPaneID paneID: UUID,
        reason: SurfacePermanentReleaseReason
    ) -> SurfacePermanentReleaseResult {
        closedSurfaceReleaseCalls.append(.init(paneID: paneID, reason: reason))
        return .released
    }

    func destroy(_: UUID) {}
}

@MainActor
private final class RendererRetentionNoOpAppCommandDispatcher: AppCommandDispatching {
    func dispatch(_: AppCommand) {}
    func dispatch(_: AppCommand, target _: UUID, targetType _: SearchItemType) {}
    func canDispatch(_: AppCommand) -> Bool { false }
    func canDispatch(_: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool { false }
    func bridgePaneCommandTarget(worktreeId _: UUID) -> BridgePaneCommandTarget? { nil }
    func dispatchMovePaneToTab(sourcePaneId _: UUID, sourceTabId _: UUID?, targetTabId _: UUID) {}
}
