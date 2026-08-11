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
        let paneEventBus = makeTestPaneRuntimeEventBus()
        let coordinator = makeTestWorkspaceSurfaceCoordinator(
            store: store,
            viewRegistry: ViewRegistry(),
            runtime: SessionRuntime(store: store),
            surfaceManager: MockPaneTabCommandSurfaceManager(
                createSurfaceResult: .failure(.ghosttyNotInitialized)
            ),
            runtimeRegistry: RuntimeRegistry(),
            paneEventBus: paneEventBus
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

                let targetedCommand = await commandHandler.nextTargetedCommand()
                let expectedTargetedCommand = RuntimeZoomCommandHandlerProbe.TargetedCommand(
                    command: .zoomPane,
                    target: sourcePane.id,
                    targetType: .pane
                )

                #expect(targetedCommand == expectedTargetedCommand)
                #expect(commandHandler.targetedCommands == [expectedTargetedCommand])
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
    private var targetedCommandWaiter: CheckedContinuation<TargetedCommand, Never>?

    func execute(_: AppCommand) {}

    func execute(_ command: AppCommand, target: UUID, targetType: SearchItemType) {
        let targetedCommand = TargetedCommand(command: command, target: target, targetType: targetType)
        targetedCommands.append(targetedCommand)
        resolveTargetedCommandWaiter(with: targetedCommand)
    }

    func nextTargetedCommand() async -> TargetedCommand {
        if let targetedCommand = targetedCommands.first {
            return targetedCommand
        }

        return await withCheckedContinuation { continuation in
            precondition(targetedCommandWaiter == nil)
            targetedCommandWaiter = continuation
        }
    }

    private func resolveTargetedCommandWaiter(with targetedCommand: TargetedCommand) {
        guard let targetedCommandWaiter else { return }
        self.targetedCommandWaiter = nil
        targetedCommandWaiter.resume(returning: targetedCommand)
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
