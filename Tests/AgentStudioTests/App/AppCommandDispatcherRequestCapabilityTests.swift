import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite("App command dispatcher request capability", .serialized)
struct AppCommandDispatcherRequestCapabilityTests {
    @Test("typed request capability overrides parameterless command capability")
    func typedRequestCapabilityOverridesParameterlessCommandCapability() async throws {
        let dispatcher = AppCommandDispatcher.shared
        let appRouter = MockAppCommandRouter()
        appRouter.requestCapabilityCommands = [.setRepoSidebarVisibilityMode]
        appRouter.parameterlessCanExecuteResult = false
        let request = AppCommandExecutionRequest(
            command: .setRepoSidebarVisibilityMode,
            arguments: .repoSidebarVisibilityMode(.favoritesOnly)
        )

        try await withIsolatedCommandDispatcher(
            configure: {
                dispatcher.handler = nil
                dispatcher.appCommandRouter = appRouter
            },
            body: {
                #expect(dispatcher.canDispatch(request))
                #expect(!dispatcher.canDispatch(request.command))
            }
        )
    }

    @Test("typed request capability is rechecked before execution")
    func typedRequestCapabilityIsRecheckedBeforeExecution() async throws {
        let dispatcher = AppCommandDispatcher.shared
        let appRouter = MockAppCommandRouter()
        appRouter.requestCapabilityCommands = [.setRepoSidebarVisibilityMode]
        appRouter.requestCommands = [.setRepoSidebarVisibilityMode]
        appRouter.parameterlessCanExecuteResult = true
        let request = AppCommandExecutionRequest(
            command: .setRepoSidebarVisibilityMode,
            arguments: .repoSidebarVisibilityMode(.favoritesOnly)
        )

        try await withIsolatedCommandDispatcher(
            configure: {
                dispatcher.handler = nil
                dispatcher.appCommandRouter = appRouter
            },
            body: {
                #expect(dispatcher.canDispatch(request))
                appRouter.requestCapabilityCommands.remove(request.command)

                let outcome = dispatcher.dispatch(request)

                #expect(outcome == .unsupportedCommand)
                #expect(appRouter.handledRequests.isEmpty)
            }
        )
    }

    @Test("no-argument requests preserve workspace-handler routing")
    func requestsWithoutArgumentsPreserveWorkspaceHandlerRouting() async throws {
        let dispatcher = AppCommandDispatcher.shared
        let handler = MockCommandHandler()
        let request = AppCommandExecutionRequest(
            command: .closeTab,
            arguments: .noArguments
        )

        try await withIsolatedCommandDispatcher(
            configure: {
                dispatcher.handler = handler
                dispatcher.appCommandRouter = nil
            },
            body: {
                let outcome = dispatcher.dispatch(request)

                #expect(outcome == .applied)
                #expect(handler.executedCommands.map(\.0) == [.closeTab])
            }
        )
    }
}
