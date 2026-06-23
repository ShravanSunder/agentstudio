import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class RPCRouterPrivilegedIngressTests {
    private struct NoResponse: Codable, Sendable {}

    private struct ReviewOpenStreamProbeMethod: RPCMethod {
        struct Params: Decodable {}

        typealias Result = NoResponse
        static let method = "review.openStream"
    }

    private actor SendableBox<Value> {
        private var value: Value

        init(_ value: Value) {
            self.value = value
        }

        func set(_ newValue: Value) {
            value = newValue
        }

        func get() -> Value {
            value
        }
    }

    @Test
    func test_pageWorldLegacyOriginCannotDispatchPrivilegedOpenStream() async throws {
        // Arrange
        let router = RPCRouter()
        let wasCalled = SendableBox(false)
        var errorCode: Int?

        router.register(method: ReviewOpenStreamProbeMethod.self) { _ in
            await wasCalled.set(true)
            return nil
        }
        router.onError = { code, _, _ in errorCode = code }

        // Act
        await router.dispatch(
            json: #"{"jsonrpc":"2.0","method":"review.openStream","params":{},"__bridgeOrigin":"pageWorldLegacy"}"#,
            isBridgeReady: true
        )

        // Assert
        #expect(await wasCalled.get() == false)
        #expect(errorCode == -32_600)
    }
}
