import AppKit
import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceSurfaceCoordinatorRestoreMutationTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("unavailable zmx during restore preserves composition and presents failure")
    func unavailableZmxDuringRestorePreservesComposition() async {
        // Arrange
        let harness = makeHarness()
        let pane = harness.store.createPane(title: "Durable title", provider: .zmx)

        // Act
        _ = harness.coordinator.createViewForContent(
            pane: pane,
            initialFrame: CGRect(x: 0, y: 0, width: 900, height: 600),
            treatAsRestoredSessionStart: true
        )

        // Assert
        #expect(harness.store.paneAtom.pane(pane.id)?.metadata.title == "Durable title")
        #expect(harness.surfaceManager.createSurfaceCallCount == 0)
        #expect(harness.coordinator.viewRegistry.terminalStatusPlaceholderView(for: pane.id)?.mode == .failedToStart)

        await harness.coordinator.shutdown()
        try? FileManager.default.removeItem(at: harness.tempDirectory)
    }

    @Test("zmx fallback for a fresh pane retains its ephemeral title marker")
    func freshZmxFallbackMarksPaneEphemeral() async {
        // Arrange
        let harness = makeHarness()
        let pane = harness.store.createPane(title: "Fresh title", provider: .zmx)

        // Act
        _ = harness.coordinator.createViewForContent(
            pane: pane,
            initialFrame: CGRect(x: 0, y: 0, width: 900, height: 600)
        )

        // Assert
        #expect(harness.store.paneAtom.pane(pane.id)?.metadata.title == "Fresh title [ephemeral]")
        #expect(harness.surfaceManager.createSurfaceCallCount == 1)

        await harness.coordinator.shutdown()
        try? FileManager.default.removeItem(at: harness.tempDirectory)
    }

    private struct Harness {
        let store: WorkspaceStore
        let coordinator: WorkspaceSurfaceCoordinator
        let surfaceManager: RestoreMutationSurfaceManager
        let tempDirectory: URL
    }

    private func makeHarness() -> Harness {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-restore-mutation-\(UUID().uuidString)")
        let store = WorkspaceStore()
        let sessionConfiguration = SessionConfiguration(
            isEnabled: false,
            zmxPath: nil,
            zmxDir: tempDirectory.appending(path: "zmx").path,
            healthCheckInterval: 30,
            maxCheckpointAge: 60
        )
        let surfaceManager = RestoreMutationSurfaceManager()
        let coordinator = makeTestWorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: ViewRegistry(),
            runtime: SessionRuntime(store: store),
            surfaceManager: surfaceManager,
            runtimeRegistry: RuntimeRegistry()
        )
        coordinator.sessionConfig = sessionConfiguration
        coordinator.terminalRestoreRuntime = TerminalRestoreRuntime(
            sessionConfiguration: sessionConfiguration
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
private final class RestoreMutationSurfaceManager: WorkspaceSurfaceManaging {
    private let cwdChanges = AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { continuation in
        continuation.finish()
    }
    private(set) var createSurfaceCallCount = 0

    var surfaceCWDChanges: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> {
        cwdChanges
    }

    func syncFocus(activeSurfaceId _: UUID?) {}

    func createSurface(
        config _: Ghostty.SurfaceConfiguration,
        metadata _: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        createSurfaceCallCount += 1
        return .failure(.ghosttyNotInitialized)
    }

    func attach(_: UUID, to _: UUID) -> Ghostty.SurfaceView? { nil }
    func detach(_: UUID, reason _: SurfaceDetachReason) {}
    func undoClose() -> ManagedSurface? { nil }
    func requeueUndo(_: UUID) {}
    func destroy(_: UUID) {}
}
