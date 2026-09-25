import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTerminal
@testable import AgentStudioTestSupport

@MainActor
@Suite("WorkspaceSurfaceCoordinator structural runtime events", .serialized)
struct GhosttyStructureRuntimeEventTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("Ghostty structural runtime events do not submit workspace mutations")
    func structuralRuntimeEventsDoNotMutateWorkspace() async throws {
        var submittedWorkspaceActions: [WorkspaceActionCommand] = []
        let commandHandler = StructuralRuntimeCommandHandler()
        let context = try makeStructuralRuntimeContext()
        defer { try? FileManager.default.removeItem(at: context.tempDir) }
        context.coordinator.workspaceActionSubmission = { action in
            submittedWorkspaceActions.append(action)
        }

        let initialTabs = context.store.tabs
        let initialPaneIds = Set(context.store.paneAtom.paneSnapshot().keys)
        let initialActiveTabId = context.store.activeTabId
        let initialZoomPresentation = context.store.panePresentationAtom.zoomPresentation(forTab: context.sourceTabId)

        do {
            try await withIsolatedCommandDispatcher(
                configure: {
                    AppCommandDispatcher.shared.handler = commandHandler
                    AppCommandDispatcher.shared.appCommandRouter = nil
                },
                body: {
                    for (index, event) in structuralEvents().enumerated() {
                        await emit(event, index: index, through: context.runtime, sourcePaneId: context.sourcePaneId)
                    }

                    #expect(submittedWorkspaceActions.isEmpty)
                    #expect(commandHandler.targetedCommands.isEmpty)
                    #expect(context.store.tabs == initialTabs)
                    #expect(Set(context.store.paneAtom.paneSnapshot().keys) == initialPaneIds)
                    #expect(context.store.activeTabId == initialActiveTabId)
                    #expect(
                        context.store.panePresentationAtom.zoomPresentation(forTab: context.sourceTabId)
                            == initialZoomPresentation
                    )
                }
            )
        } catch {
            await context.coordinator.shutdown()
            throw error
        }

        await context.coordinator.shutdown()
    }

    private func makeStructuralRuntimeContext() throws -> GhosttyStructureRuntimeContext {
        installTestAtomRegistryIfNeeded()
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-ghostty-structure-events-\(UUIDv7.generate())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let store = WorkspaceStore()
        let repo = store.addRepo(at: tempDir)
        let worktree = try #require(repo.worktrees.first)
        let paneFacets = PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path)
        let sourcePane = store.createPane(
            launchDirectory: worktree.path,
            title: "Structure source",
            provider: .zmx,
            facets: paneFacets
        )
        let rightPane = store.createPane(
            launchDirectory: worktree.path,
            title: "Structure right split",
            provider: .zmx,
            facets: paneFacets
        )
        let thirdPane = store.createPane(
            launchDirectory: worktree.path,
            title: "Structure third split",
            provider: .zmx,
            facets: paneFacets
        )
        let otherTabPane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/structure-other")!)),
            metadata: PaneMetadata(title: "Other tab")
        )
        let lastTabPane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/structure-last")!)),
            metadata: PaneMetadata(title: "Last tab")
        )

        let sourceTab = Tab(paneId: sourcePane.id)
        store.appendTab(sourceTab)
        #expect(
            store.insertPane(
                rightPane.id,
                inTab: sourceTab.id,
                at: sourcePane.id,
                direction: .horizontal,
                position: .after,
                sizingMode: .halveTarget
            )
        )
        #expect(
            store.insertPane(
                thirdPane.id,
                inTab: sourceTab.id,
                at: rightPane.id,
                direction: .horizontal,
                position: .after,
                sizingMode: .halveTarget
            )
        )
        store.appendTab(Tab(paneId: otherTabPane.id))
        store.appendTab(Tab(paneId: lastTabPane.id))
        store.setActiveTab(sourceTab.id)

        let coordinator = makeTestWorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: ViewRegistry(),
            runtime: SessionRuntime(store: store),
            surfaceManager: StructuralRuntimeSurfaceManager(),
            runtimeRegistry: RuntimeRegistry()
        )
        let runtime = FakePaneRuntime(paneId: PaneId(existingUUID: sourcePane.id))
        coordinator.registerRuntime(runtime)
        return GhosttyStructureRuntimeContext(
            tempDir: tempDir,
            store: store,
            coordinator: coordinator,
            runtime: runtime,
            sourcePaneId: sourcePane.id,
            sourceTabId: sourceTab.id
        )
    }

    private func structuralEvents() -> [GhosttyEvent] {
        [
            .newTab,
            .newSplit(direction: .right),
            .gotoSplit(direction: .next),
            .resizeSplit(amount: 10, direction: .right),
            .equalizeSplits,
            .toggleSplitZoom,
            .closeTab(mode: .otherTabs),
            .gotoTab(target: .next),
            .moveTab(amount: 1),
        ]
    }

    private func emit(
        _ event: GhosttyEvent,
        index: Int,
        through runtime: FakePaneRuntime,
        sourcePaneId: UUID
    ) async {
        let structuralSequence = UInt64(index * 2 + 1)
        let source = EventSource.pane(PaneId(existingUUID: sourcePaneId))
        let appEventStream = await AppEventBus.shared.subscribe(
            policy: .criticalUnbounded,
            subscriberName: "GhosttyStructureRuntimeEventTests.barrier.\(index)"
        )

        // Consume the event stream independently while the MainActor coordinator publishes the barrier.
        // swiftlint:disable:next no_task_detached
        let bellWaiter = Task.detached { () -> Bool in
            for await appEvent in appEventStream {
                if case .worktreeBellRang(let paneId) = appEvent, paneId == sourcePaneId {
                    return true
                }
            }
            return false
        }

        runtime.emit(
            makeRuntimeEnvelope(
                source: source,
                paneKind: .terminal,
                seq: structuralSequence,
                commandId: nil,
                correlationId: nil,
                timestamp: ContinuousClock().now,
                epoch: 0,
                event: .terminal(event)
            )
        )
        runtime.emit(
            makeRuntimeEnvelope(
                source: source,
                paneKind: .terminal,
                seq: structuralSequence + 1,
                commandId: nil,
                correlationId: nil,
                timestamp: ContinuousClock().now,
                epoch: 0,
                event: .terminal(.bellRang)
            )
        )

        #expect(await bellWaiter.value, "Coordinator did not finish the event preceding the bell barrier")
    }
}

@MainActor
private struct GhosttyStructureRuntimeContext {
    let tempDir: URL
    let store: WorkspaceStore
    let coordinator: WorkspaceSurfaceCoordinator
    let runtime: FakePaneRuntime
    let sourcePaneId: UUID
    let sourceTabId: UUID
}

@MainActor
private final class StructuralRuntimeCommandHandler: WorkspaceCommandHandling {
    private(set) var commands: [AppCommand] = []
    private(set) var targetedCommands: [AppCommand] = []

    func execute(_ command: AppCommand) {
        commands.append(command)
    }

    func execute(_ command: AppCommand, target: UUID, targetType: SearchItemType) {
        _ = target
        _ = targetType
        targetedCommands.append(command)
    }

    func canExecute(_ command: AppCommand) -> Bool {
        _ = command
        return true
    }

    func executeExtractPaneToTab(tabId: UUID, paneId: UUID, targetTabInsertionIndex: Int?) {
        _ = tabId
        _ = paneId
        _ = targetTabInsertionIndex
    }

    func executeMovePaneToTab(sourcePaneId: UUID, sourceTabId: UUID?, targetTabId: UUID) {
        _ = sourcePaneId
        _ = sourceTabId
        _ = targetTabId
    }
}

@MainActor
private final class StructuralRuntimeSurfaceManager: WorkspaceSurfaceManaging {
    func syncFocus(activeSurfaceId: UUID?) {
        _ = activeSurfaceId
    }

    func createSurface(
        config: Ghostty.SurfaceConfiguration,
        metadata: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        _ = config
        _ = metadata
        return .failure(.ghosttyNotInitialized)
    }

    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView? {
        _ = surfaceId
        _ = paneId
        return nil
    }

    func detach(_ surfaceId: UUID, reason: SurfaceDetachReason) {
        _ = surfaceId
        _ = reason
    }

    func undoClose(forPaneId paneId: UUID) -> ManagedSurface? {
        _ = paneId
        return nil
    }

    func destroy(_ surfaceId: UUID) {
        _ = surfaceId
    }

    func releaseUndoSurfaces(forPaneIDs paneIDs: Set<UUID>) {
        _ = paneIDs
    }

    func retainSurfacesForUndo(forPaneIDs paneIDs: Set<UUID>) {
        _ = paneIDs
    }

    func retireActiveAndHiddenSurfaces(forPaneIDs paneIDs: Set<UUID>) {
        _ = paneIDs
    }
}
