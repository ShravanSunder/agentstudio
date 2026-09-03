import Hummingbird
import HummingbirdTesting
import NIOPosix

@testable import AgentStudioBridge
@testable import AgentStudioBridgeDevelopmentServer

func withBridgeDevelopmentHTTPRouterTestClient<Value: Sendable>(
    host: BridgeDevelopmentProductHost,
    healthIsReady: @escaping @Sendable () async -> Bool = { true },
    test: @escaping @Sendable (any TestClientProtocol) async throws -> Value
) async throws -> Value {
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let application = BridgeDevelopmentHTTPApplication.make(
        host: host,
        eventLoopGroupProvider: .shared(eventLoopGroup),
        healthIsReady: healthIsReady
    )
    do {
        let value = try await application.test(.router, test)
        try await eventLoopGroup.shutdownGracefully()
        return value
    } catch {
        try? await eventLoopGroup.shutdownGracefully()
        throw error
    }
}
