import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

/// The catalog methods are the only responses this app composes that are
/// legitimately larger than any request. Every other capabilities test runs in
/// process against the composition and never reaches `NDJSONFrameEncoder`,
/// which is how a server that answered `system.capabilities` with a framing
/// failure shipped with a green suite.
@MainActor
@Suite("App IPC catalog frame transport", .serialized)
struct AgentStudioIPCCatalogFrameTransportTests {
    init() { installTestCoreAtomsIfNeeded() }

    @Test("system.capabilities crosses the socket in one frame larger than the request bound")
    func systemCapabilitiesCrossesTheSocket() async throws {
        let harness = try await SessionsVerticalHarness.make()
        defer { harness.tearDown() }

        let frame = try await harness.responseFrame(method: "system.capabilities", params: .object([:]))
        let frameByteCount = frame.utf8.count

        // Asserting the size proves the case is real: a catalog that fits the
        // request bound would not have exercised the outbound bound at all.
        #expect(
            frameByteCount > IPCFramePolicy.maximumRequestFrameBytes,
            "system.capabilities frame measured \(frameByteCount) bytes"
        )
        #expect(frameByteCount <= IPCFramePolicy.maximumResponseFrameBytes)

        let message = try JSONRPCCodec.decodeResponse(frame)
        #expect(message.error == nil)
        let result = try #require(message.result)
        let catalog = try JSONDecoder().decode(
            IPCMethodCatalogResult.self, from: try JSONEncoder().encode(result)
        )
        #expect(catalog.methods.contains { $0.name == "system.capabilities" })
        #expect(catalog.methods.contains { $0.name == "session.message" })
    }

    @Test("command.list crosses the socket and carries the debug command catalog")
    func commandListCrossesTheSocket() async throws {
        let harness = try await SessionsVerticalHarness.make()
        defer { harness.tearDown() }

        let frame = try await harness.responseFrame(method: "command.list", params: .object([:]))
        let message = try JSONRPCCodec.decodeResponse(frame)

        #expect(message.error == nil)
        let result = try #require(message.result)
        guard case .object(let fields) = result, case .array(let commands)? = fields["commands"] else {
            Issue.record("command.list result did not carry a commands array")
            return
        }
        #expect(commands.count == 146)
    }
}
