import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite("App command dispatcher request capability", .serialized)
struct AppCommandDispatcherRequestCapabilityTests {
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
