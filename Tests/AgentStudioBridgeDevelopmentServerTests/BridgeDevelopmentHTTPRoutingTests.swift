import AgentStudioTestSupport
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Testing

@testable import AgentStudioBridge
@testable import AgentStudioBridgeDevelopmentServer

@Suite("Bridge development HTTP routing")
struct BridgeDevelopmentHTTPRoutingTests {
    @Test("server configuration is fixed to IPv4 loopback")
    func serverConfigurationUsesLoopback() throws {
        // Arrange / Act
        let configuration = try BridgeDevelopmentServerConfiguration(
            worktreeRoot: URL(fileURLWithPath: "/tmp/repository"),
            reviewBase: "HEAD",
            port: 43_871
        )

        // Assert
        #expect(configuration.applicationConfiguration.address == .hostname("127.0.0.1", port: 43_871))
    }

    @Test("health route reports readiness without a response body")
    func healthRouteReportsReadiness() async throws {
        // Arrange
        let repositoryURL = try FilesystemTestGitRepo.create(
            named: "bridge-development-http-health"
        )
        defer { FilesystemTestGitRepo.destroy(repositoryURL) }
        try FilesystemTestGitRepo.seedTrackedAndUntrackedChanges(at: repositoryURL)
        let host = try await BridgeDevelopmentProductHost(
            source: BridgeDevelopmentProductSource(
                worktreeRoot: repositoryURL,
                reviewBase: "HEAD"
            ),
            makeReviewProvider: { _, _ in BridgeObservabilitySmokeReviewSourceProvider() }
        )
        let application = BridgeDevelopmentHTTPApplication.make(host: host)

        // Act / Assert
        try await application.test(.router) { client in
            try await client.execute(
                uri: "/__bridge-product/health",
                method: .get
            ) { response in
                #expect(response.status == .noContent)
                #expect(response.body.readableBytes == 0)
            }
        }
        await host.shutdown()
    }

    @Test("bootstrap route returns the existing binary session envelope")
    func bootstrapRouteReturnsSessionEnvelope() async throws {
        // Arrange
        let repositoryURL = try FilesystemTestGitRepo.create(
            named: "bridge-development-http-bootstrap"
        )
        defer { FilesystemTestGitRepo.destroy(repositoryURL) }
        try FilesystemTestGitRepo.seedTrackedAndUntrackedChanges(at: repositoryURL)
        let host = try await BridgeDevelopmentProductHost(
            source: BridgeDevelopmentProductSource(
                worktreeRoot: repositoryURL,
                reviewBase: "HEAD"
            ),
            makeReviewProvider: { _, _ in BridgeObservabilitySmokeReviewSourceProvider() }
        )
        let application = BridgeDevelopmentHTTPApplication.make(host: host)
        let body = ByteBuffer(
            string:
                #"{"navigationIntent":{"commandId":"open-file-view","commandKind":"activateContext","surface":"file"},"reason":"initial"}"#
        )

        // Act / Assert
        try await application.test(.router) { client in
            try await client.execute(
                uri: "/__bridge-product/bootstrap",
                method: .post,
                headers: [.contentType: "application/json"],
                body: body
            ) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "application/octet-stream")
                #expect(response.body.readableBytes > 37)
                #expect(response.body.getInteger(at: 0, as: UInt8.self) == 1)
            }
        }
        await host.shutdown()
    }

    @Test("command route forwards worker admission through the existing product adapter")
    func commandRouteForwardsWorkerAdmission() async throws {
        // Arrange
        let repositoryURL = try FilesystemTestGitRepo.create(
            named: "bridge-development-http-command"
        )
        defer { FilesystemTestGitRepo.destroy(repositoryURL) }
        try FilesystemTestGitRepo.seedTrackedAndUntrackedChanges(at: repositoryURL)
        let host = try await BridgeDevelopmentProductHost(
            source: BridgeDevelopmentProductSource(
                worktreeRoot: repositoryURL,
                reviewBase: "HEAD"
            ),
            makeReviewProvider: { _, _ in BridgeObservabilitySmokeReviewSourceProvider() }
        )
        let application = BridgeDevelopmentHTTPApplication.make(host: host)

        // Act / Assert
        try await application.test(.router) { client in
            let bootstrapResponse = try await client.execute(
                uri: "/__bridge-product/bootstrap",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(
                    string:
                        #"{"navigationIntent":{"commandId":"open-file-view","commandKind":"activateContext","surface":"file"},"reason":"initial"}"#
                )
            )
            let envelope = try decodeHTTPBootstrapEnvelope(
                Data(bootstrapResponse.body.readableBytesView)
            )
            let capability = try BridgeProductCapabilityHeaderEncoding.encode(
                Array(envelope.capabilityBytes)
            )
            let requestBody = try JSONSerialization.data(
                withJSONObject: [
                    "kind": "workerSession.open",
                    "paneSessionId": envelope.bootstrap.paneSessionId,
                    "request": NSNull(),
                    "requestId": "request-open-development-http",
                    "requestSequence": 1,
                    "wireVersion": BridgeProductWireContract.version,
                    "workerInstanceId": envelope.bootstrap.workerInstanceId,
                ],
                options: [.sortedKeys]
            )
            let capabilityHeader = try #require(
                HTTPField.Name(BridgeProductWireContract.capabilityHeaderName)
            )
            try await client.execute(
                uri: "/__bridge-product/command",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    capabilityHeader: capability,
                ],
                body: ByteBuffer(data: requestBody)
            ) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "application/json")
                let controlResponse = try BridgeProductStrictJSON.decode(
                    BridgeProductControlResponse.self,
                    from: Data(response.body.readableBytesView)
                )
                guard case .workerSessionAccepted(let accepted) = controlResponse else {
                    Issue.record("Expected workerSession.accepted through the HTTP carrier")
                    return
                }
                #expect(accepted.correlation.paneSessionId == envelope.bootstrap.paneSessionId)
                #expect(accepted.correlation.workerInstanceId == envelope.bootstrap.workerInstanceId)
            }
        }
        await host.shutdown()
    }
}

private struct DecodedHTTPBootstrapEnvelope {
    let bootstrap: BridgeProductSessionBootstrap
    let capabilityBytes: Data
}

private func decodeHTTPBootstrapEnvelope(
    _ data: Data
) throws -> DecodedHTTPBootstrapEnvelope {
    let envelopeVersionByteCount = 1
    let metadataLengthByteCount = 4
    let prefixByteCount = envelopeVersionByteCount + metadataLengthByteCount
    guard data.count >= prefixByteCount + BridgeProductWireContract.capabilityByteLength else {
        throw CocoaError(.fileReadCorruptFile)
    }
    #expect(data[0] == 1)
    let metadataByteCount = data[1..<prefixByteCount].reduce(0) { length, byte in
        (length << 8) | Int(byte)
    }
    let metadataRange = prefixByteCount..<(prefixByteCount + metadataByteCount)
    let capabilityRange = metadataRange.upperBound..<data.count
    guard metadataRange.upperBound <= data.count,
        capabilityRange.count == BridgeProductWireContract.capabilityByteLength
    else {
        throw CocoaError(.fileReadCorruptFile)
    }
    return try DecodedHTTPBootstrapEnvelope(
        bootstrap: JSONDecoder().decode(
            BridgeProductSessionBootstrap.self,
            from: data.subdata(in: metadataRange)
        ),
        capabilityBytes: data.subdata(in: capabilityRange)
    )
}
