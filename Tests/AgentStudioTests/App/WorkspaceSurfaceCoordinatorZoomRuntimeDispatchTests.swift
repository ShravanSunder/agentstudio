import Foundation
import Synchronization
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
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
        await assertEventuallyAsync("coordinator bus subscriber should be active") {
            await paneEventBus.diagnosticsSnapshot().activeSubscribers.contains {
                $0.subscriberName == "WorkspaceSurfaceCoordinator"
            }
        }
        let sourcePane = store.createPane()
        let sourceTab = Tab(paneId: sourcePane.id)
        store.appendTab(sourceTab)
        store.setActiveTab(sourceTab.id)
        let fakeRuntime = FakePaneRuntime(paneId: PaneId(existingUUID: sourcePane.id))
        coordinator.registerRuntime(fakeRuntime)
        let commandHandler = RuntimeZoomCommandHandlerProbe()

        do {
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

                    let targetedCommand = try await commandHandler.nextTargetedCommand()
                    let expectedTargetedCommand = RuntimeZoomCommandHandlerProbe.TargetedCommand(
                        command: .zoomPane,
                        target: sourcePane.id,
                        targetType: .pane
                    )

                    #expect(targetedCommand == expectedTargetedCommand)
                    #expect(commandHandler.targetedCommands == [expectedTargetedCommand])
                }
            )
        } catch {
            await coordinator.shutdown()
            throw error
        }

        await coordinator.shutdown()
    }

    @Test("command probe consumes targeted commands in arrival order")
    func commandProbeConsumesTargetedCommandsInArrivalOrder() async throws {
        let commandHandler = RuntimeZoomCommandHandlerProbe()
        let firstTarget = UUIDv7.generate()
        let secondTarget = UUIDv7.generate()

        commandHandler.execute(.zoomPane, target: firstTarget, targetType: .pane)
        commandHandler.execute(.zoomPane, target: secondTarget, targetType: .pane)

        let firstCommand = try await commandHandler.nextTargetedCommand()
        let secondCommand = try await commandHandler.nextTargetedCommand()

        #expect(firstCommand.target == firstTarget)
        #expect(secondCommand.target == secondTarget)
    }

    @Test("command probe timeout cleans up its waiter for the next command")
    func commandProbeTimeoutCleansUpWaiter() async throws {
        let clock = TestPushClock()
        let commandHandler = RuntimeZoomCommandHandlerProbe(clock: clock)
        let timedOutWait = Task { @MainActor in
            try await commandHandler.nextTargetedCommand(timeout: .seconds(1))
        }
        await clock.waitForPendingSleepCount()

        clock.advance(by: .seconds(1))

        await #expect(throws: RuntimeZoomCommandHandlerProbe.WaitError.timedOut) {
            try await timedOutWait.value
        }

        let nextTarget = UUIDv7.generate()
        let nextWait = Task { @MainActor in
            try await commandHandler.nextTargetedCommand(timeout: .seconds(1))
        }
        await clock.waitForPendingSleepCount()
        commandHandler.execute(.zoomPane, target: nextTarget, targetType: .pane)

        let nextCommand = try await nextWait.value

        #expect(nextCommand.target == nextTarget)
        #expect(clock.pendingSleepCount == 0)
    }

    @Test("command probe cancellation cleans up its waiter")
    func commandProbeCancellationCleansUpWaiter() async throws {
        let clock = TestPushClock()
        let commandHandler = RuntimeZoomCommandHandlerProbe(clock: clock)
        let cancelledWait = Task { @MainActor in
            try await commandHandler.nextTargetedCommand(timeout: .seconds(1))
        }
        await clock.waitForPendingSleepCount()

        cancelledWait.cancel()

        await #expect(throws: CancellationError.self) {
            try await cancelledWait.value
        }
        await clock.waitForPendingSleepCount(exactly: 0)

        let nextTarget = UUIDv7.generate()
        commandHandler.execute(.zoomPane, target: nextTarget, targetType: .pane)

        let nextCommand = try await commandHandler.nextTargetedCommand()

        #expect(nextCommand.target == nextTarget)
    }

    @Test("stale cancellation cannot cancel the next command waiter")
    func staleCancellationCannotCancelNextWaiter() async throws {
        let clock = TestPushClock()
        let cancellationQueue = DeferredMainActorOperationQueue()
        let commandHandler = RuntimeZoomCommandHandlerProbe(
            clock: clock,
            scheduleCancellation: cancellationQueue.schedule
        )
        let firstWait = Task { @MainActor in
            try await commandHandler.nextTargetedCommand(timeout: .seconds(1))
        }
        await clock.waitForPendingSleepCount()

        firstWait.cancel()
        let firstTarget = UUIDv7.generate()
        commandHandler.execute(.zoomPane, target: firstTarget, targetType: .pane)
        let firstCommand = try await firstWait.value
        await clock.waitForPendingSleepCount(exactly: 0)

        let secondWait = Task { @MainActor in
            try await commandHandler.nextTargetedCommand(timeout: .seconds(1))
        }
        await clock.waitForPendingSleepCount()
        cancellationQueue.runNext()
        let secondTarget = UUIDv7.generate()
        commandHandler.execute(.zoomPane, target: secondTarget, targetType: .pane)

        let secondCommand = try await secondWait.value

        #expect(firstCommand.target == firstTarget)
        #expect(secondCommand.target == secondTarget)
        #expect(clock.pendingSleepCount == 0)
    }

    @Test("pre-cancelled command wait creates no waiter or timeout")
    func preCancelledCommandWaitCreatesNoWaiterOrTimeout() async throws {
        let clock = TestPushClock()
        let commandHandler = RuntimeZoomCommandHandlerProbe(clock: clock)
        let cancelledWait = Task { @MainActor in
            while !Task.isCancelled {
                await Task.yield()
            }
            return try await commandHandler.nextTargetedCommand(timeout: .seconds(1))
        }

        cancelledWait.cancel()

        await #expect(throws: CancellationError.self) {
            try await cancelledWait.value
        }
        #expect(clock.pendingSleepCount == 0)

        let nextTarget = UUIDv7.generate()
        commandHandler.execute(.zoomPane, target: nextTarget, targetType: .pane)

        let nextCommand = try await commandHandler.nextTargetedCommand()

        #expect(nextCommand.target == nextTarget)
    }
}

private final class DeferredMainActorOperationQueue: Sendable {
    typealias Operation = @MainActor @Sendable () -> Void

    private let operations = Mutex<[Operation]>([])

    func schedule(_ operation: @escaping Operation) {
        operations.withLock { $0.append(operation) }
    }

    @MainActor
    func runNext() {
        let operation = operations.withLock { operations in
            precondition(!operations.isEmpty)
            return operations.removeFirst()
        }
        operation()
    }
}

@MainActor
private final class RuntimeZoomCommandHandlerProbe: WorkspaceCommandHandling {
    typealias ScheduleCancellation = @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void

    enum WaitError: Error {
        case timedOut
    }

    struct TargetedCommand: Equatable {
        let command: AppCommand
        let target: UUID
        let targetType: SearchItemType
    }

    private struct TargetedCommandWaiter {
        let id: Int
        let continuation: CheckedContinuation<TargetedCommand, any Error>
    }

    private(set) var targetedCommands: [TargetedCommand] = []
    private var nextTargetedCommandIndex = 0
    private var nextTargetedCommandWaiterID = 0
    private var targetedCommandWaiter: TargetedCommandWaiter?
    private var targetedCommandTimeoutTask: Task<Void, Never>?
    private let delay: AsyncDelay
    private let scheduleCancellation: ScheduleCancellation

    init() {
        delay = .taskSleep
        scheduleCancellation = Self.scheduleCancellationOnMainActor
    }

    init<TClock: Clock & Sendable>(
        clock: TClock,
        scheduleCancellation: @escaping ScheduleCancellation =
            RuntimeZoomCommandHandlerProbe.scheduleCancellationOnMainActor
    ) where TClock.Duration == Duration {
        delay = .clock(clock)
        self.scheduleCancellation = scheduleCancellation
    }

    func execute(_: AppCommand) {}

    func execute(_ command: AppCommand, target: UUID, targetType: SearchItemType) {
        let targetedCommand = TargetedCommand(command: command, target: target, targetType: targetType)
        targetedCommands.append(targetedCommand)
        resolveTargetedCommandWaiterIfPossible()
    }

    func nextTargetedCommand(timeout: Duration = .seconds(5)) async throws -> TargetedCommand {
        if nextTargetedCommandIndex < targetedCommands.count {
            let targetedCommand = targetedCommands[nextTargetedCommandIndex]
            nextTargetedCommandIndex += 1
            return targetedCommand
        }

        let waiterID = nextTargetedCommandWaiterID
        nextTargetedCommandWaiterID += 1

        return try await withTaskCancellationHandler(
            operation: {
                try await withCheckedThrowingContinuation { continuation in
                    precondition(targetedCommandWaiter == nil)
                    guard !Task.isCancelled else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    targetedCommandWaiter = TargetedCommandWaiter(id: waiterID, continuation: continuation)
                    targetedCommandTimeoutTask = Task { [delay, weak self] in
                        do {
                            try await delay.wait(timeout)
                        } catch {
                            return
                        }
                        guard !Task.isCancelled else { return }
                        self?.finishTargetedCommandWait(
                            waiterID: waiterID,
                            with: .failure(WaitError.timedOut)
                        )
                    }
                }
            },
            onCancel: { [scheduleCancellation] in
                scheduleCancellation { [weak self] in
                    self?.finishTargetedCommandWait(
                        waiterID: waiterID,
                        with: .failure(CancellationError())
                    )
                }
            }
        )
    }

    nonisolated private static func scheduleCancellationOnMainActor(
        _ operation: @escaping @MainActor @Sendable () -> Void
    ) {
        Task { @MainActor in
            operation()
        }
    }

    private func resolveTargetedCommandWaiterIfPossible() {
        guard let targetedCommandWaiter, nextTargetedCommandIndex < targetedCommands.count else { return }
        let targetedCommand = targetedCommands[nextTargetedCommandIndex]
        nextTargetedCommandIndex += 1
        finishTargetedCommandWait(
            waiterID: targetedCommandWaiter.id,
            with: .success(targetedCommand)
        )
    }

    private func finishTargetedCommandWait(
        waiterID: Int,
        with result: Result<TargetedCommand, any Error>
    ) {
        guard let targetedCommandWaiter, targetedCommandWaiter.id == waiterID else { return }
        self.targetedCommandWaiter = nil
        targetedCommandTimeoutTask?.cancel()
        targetedCommandTimeoutTask = nil
        targetedCommandWaiter.continuation.resume(with: result)
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
