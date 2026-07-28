import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct ZoomRuntimeDispatchTests {
    @Test("runtime terminal toggleSplitZoom translates to targeted semantic Pane Zoom")
    func runtimeToggleSplitZoomDispatchesTargetedZoomPane() async throws {
        installTestAtomRegistryIfNeeded()
        let store = WorkspaceStore()
        let coordinator = makeTestWorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: ViewRegistry(),
            runtime: SessionRuntime(store: store),
            surfaceManager: MockPaneTabCommandSurfaceManager(
                createSurfaceResult: .failure(.ghosttyNotInitialized)
            ),
            runtimeRegistry: RuntimeRegistry()
        )
        let sourcePane = store.createPane()
        let sourceTab = Tab(paneId: sourcePane.id)
        store.appendTab(sourceTab)
        store.setActiveTab(sourceTab.id)
        let fakeRuntime = FakePaneRuntime(paneId: PaneId(existingUUID: sourcePane.id))
        coordinator.registerRuntime(fakeRuntime)
        let commandHandler = RuntimeZoomCommandHandlerProbe()

        try await withIsolatedCommandDispatcher(
            configure: {
                AppCommandDispatcher.shared.handler = commandHandler
                AppCommandDispatcher.shared.appCommandRouter = nil
            },
            body: {
                fakeRuntime.emit(
                    makeRuntimeEnvelope(
                        source: .pane(PaneId(existingUUID: sourcePane.id)),
                        paneKind: .terminal,
                        seq: 1,
                        commandId: nil,
                        correlationId: nil,
                        timestamp: ContinuousClock().now,
                        epoch: 0,
                        event: .terminal(.toggleSplitZoom)
                    )
                )

                await eventually("toggleSplitZoom should dispatch targeted semantic Pane Zoom") {
                    commandHandler.targetedCommands.count == 1
                }

                #expect(
                    commandHandler.targetedCommands == [
                        RuntimeZoomCommandHandlerProbe.TargetedCommand(
                            command: .zoomPane,
                            target: sourcePane.id,
                            targetType: .pane
                        )
                    ]
                )
            }
        )

        await coordinator.shutdown()
    }
}

@MainActor
private final class RuntimeZoomCommandHandlerProbe: WorkspaceCommandHandling {
    struct TargetedCommand: Equatable {
        let command: AppCommand
        let target: UUID
        let targetType: SearchItemType
    }

    private(set) var targetedCommands: [TargetedCommand] = []

    func execute(_: AppCommand) {}

    func execute(_ command: AppCommand, target: UUID, targetType: SearchItemType) {
        targetedCommands.append(
            TargetedCommand(
                command: command,
                target: target,
                targetType: targetType
            )
        )
    }

    func canExecute(_: AppCommand) -> Bool {
        false
    }

    func canExecute(_ command: AppCommand, target _: UUID, targetType: SearchItemType) -> Bool {
        command == .zoomPane && targetType == .pane
    }

    func executeExtractPaneToTab(tabId _: UUID, paneId _: UUID, targetTabIndex _: Int?) {}

    func executeMovePaneToTab(sourcePaneId _: UUID, sourceTabId _: UUID?, targetTabId _: UUID) {}
}
