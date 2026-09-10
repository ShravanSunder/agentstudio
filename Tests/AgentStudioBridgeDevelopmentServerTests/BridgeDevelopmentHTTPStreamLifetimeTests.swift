import Darwin
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import NIOCore
import Synchronization
import Testing
import WebKit

@testable import AgentStudioBridgeDevelopmentServer

@Suite("Bridge development HTTP stream lifetime")
struct BridgeDevelopmentHTTPStreamLifetimeTests {
    @Test(
        "production connection lifetime forwards dynamic stream responses and permits explicit close",
        arguments: [206, 403, 409]
    )
    func connectionLifetimeForwardsDynamicStreamContract(statusCode: Int) async throws {
        // Arrange
        let probe = HTTPStreamLifetimeProbe()
        let responseURL = try #require(URL(string: "http://localhost/metadata"))
        let router = Router(context: BridgeDevelopmentHTTPRequestContext.self)
        router.post("/metadata") { request, context -> Response in
            let requestBytes = try await request.body.collect(upTo: 1024)
            #expect(String(buffer: requestBytes) == "request")
            let responseHead = try #require(
                HTTPURLResponse(
                    url: responseURL,
                    statusCode: statusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Type": "application/octet-stream",
                        "Access-Control-Allow-Origin": "http://localhost",
                    ]
                ))
            let (results, continuation) = AsyncThrowingStream<URLSchemeTaskResult, any Error>.makeStream()
            continuation.yield(.response(responseHead))
            continuation.yield(.data(Data("metadata-\(statusCode)".utf8)))
            continuation.finish()
            return try await BridgeDevelopmentHTTPProductResponse.make(
                from: results, onConnectionClose: context.onConnectionClose)
        }
        let application = Application(responder: router.buildResponder())

        // Act / Assert
        try await application.test(.live) { serverClient in
            let port = try #require(serverClient.port)
            try await TestClient.withClient(host: "localhost", port: port) { client in
                let channel = try await client.getChannel()
                channel.closeFuture.whenComplete { _ in probe.recordConnectionClose() }
                let response = try await client.execute(
                    .init("/metadata", method: .post, body: ByteBuffer(string: "request")))
                #expect(response.status.code == statusCode)
                #expect(response.headers[.contentType] == "application/octet-stream")
                #expect(response.headers[.accessControlAllowOrigin] == "http://localhost")
                #expect(response.body.map { String(buffer: $0) } == "metadata-\(statusCode)")
                let secondResponse = try await client.execute(
                    .init("/metadata", method: .post, body: ByteBuffer(string: "request")))
                #expect(secondResponse.status.code == statusCode)
                #expect(secondResponse.body.map { String(buffer: $0) } == "metadata-\(statusCode)")
                try await client.close(mode: .all)
                #expect(await probe.waitForConnectionClose())
            }
        }
    }

    @Test("production connection lifetime cancels an idle stream after connection reset")
    func connectionLifetimeCancelsIdleStreamAfterReset() async throws {
        // Arrange
        let probe = HTTPStreamLifetimeProbe()
        let responseURL = try #require(URL(string: "http://localhost/metadata"))
        let (results, continuation) = AsyncThrowingStream<URLSchemeTaskResult, any Error>.makeStream()
        continuation.onTermination = { termination in
            if case .cancelled = termination { probe.recordCancellation() }
        }
        defer { continuation.finish() }
        let responseHead = try #require(
            HTTPURLResponse(
                url: responseURL,
                statusCode: 206,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/octet-stream"]
            ))
        continuation.yield(.response(responseHead))
        continuation.yield(.data(Data([1])))

        let router = Router(context: BridgeDevelopmentHTTPRequestContext.self)
        router.post("/metadata") { request, context -> Response in
            let requestBytes = try await request.body.collect(upTo: 1024)
            #expect(String(buffer: requestBytes) == "request")
            var response = try await BridgeDevelopmentHTTPProductResponse.make(
                from: results, onConnectionClose: context.onConnectionClose)
            response.body = response.body.map { buffer in
                probe.recordBodyWrite()
                return buffer
            }
            return response
        }
        let application = Application(responder: router.buildResponder())

        // Act
        try await application.test(.live) { serverClient in
            let port = try #require(serverClient.port)
            try await TestClient.withClient(host: "localhost", port: port) { client in
                try await client.executeAndDontWaitForResponse(
                    .init("/metadata", method: .post, body: ByteBuffer(string: "request")))
                #expect(await probe.waitForBodyWrite())
                // A reset is a real disconnect, unlike a valid request-side FIN.
                let socket = try #require(try await client.getChannel() as? any SocketOptionProvider)
                try await socket.setSoLinger(linger(l_onoff: 1, l_linger: 0)).get()
                try await client.close(mode: .all)

                // Assert — cancellation must not require another response chunk.
                let upstreamWasCancelled = await probe.waitForCancellation()
                continuation.finish()
                #expect(upstreamWasCancelled)
            }
        }
    }

    @Test("ordinary finite routes preserve dynamic responses and keep-alive", arguments: [200, 403, 409])
    func ordinaryFiniteRoutesPreserveKeepAlive(statusCode: Int) async throws {
        // Arrange
        let responseURL = try #require(URL(string: "http://localhost/finite"))
        let router = Router()
        router.post("/finite") { request, _ -> Response in
            let requestBytes = try await request.body.collect(upTo: 1024)
            let responseHead = try #require(
                HTTPURLResponse(
                    url: responseURL,
                    statusCode: statusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Type": "application/json",
                        "Access-Control-Allow-Origin": "http://localhost",
                    ]
                ))
            let (results, continuation) = AsyncThrowingStream<URLSchemeTaskResult, any Error>.makeStream()
            continuation.yield(.response(responseHead))
            continuation.yield(.data(Data(requestBytes.readableBytesView)))
            continuation.finish()
            return try await BridgeDevelopmentHTTPProductResponse.make(from: results)
        }
        let application = Application(responder: router.buildResponder())

        // Act / Assert — both requests use the same TestClient connection.
        try await application.test(.live) { client in
            for body in ["first", "second"] {
                try await client.execute(
                    uri: "/finite", method: .post, body: ByteBuffer(string: body)
                ) { response in
                    #expect(response.status.code == statusCode)
                    #expect(response.headers[.contentType] == "application/json")
                    #expect(response.headers[.accessControlAllowOrigin] == "http://localhost")
                    #expect(String(buffer: response.body) == body)
                }
            }
        }
    }

    @Test("ordinary finite routes permit request half-close while a response is pending")
    func ordinaryFiniteRoutePermitsRequestHalfClose() async throws {
        // Arrange
        let probe = HTTPStreamLifetimeProbe()
        let responseURL = try #require(URL(string: "http://localhost/finite"))
        let (results, continuation) = AsyncThrowingStream<URLSchemeTaskResult, any Error>.makeStream()
        defer { continuation.finish() }
        let router = Router()
        router.post("/finite") { request, _ -> Response in
            _ = try await request.body.collect(upTo: 1024)
            probe.recordBodyWrite()
            return try await BridgeDevelopmentHTTPProductResponse.make(from: results)
        }
        let application = Application(responder: router.buildResponder())

        try await application.test(.live) { serverClient in
            let port = try #require(serverClient.port)
            try await TestClient.withClient(host: "localhost", port: port) { client in
                async let pendingResponse = client.execute(
                    .init("/finite", method: .post, body: ByteBuffer(string: "request")))
                #expect(await probe.waitForBodyWrite())

                // Act
                try await client.close(mode: .output)
                let responseHead = try #require(
                    HTTPURLResponse(
                        url: responseURL,
                        statusCode: 202,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/json"]
                    ))
                continuation.yield(.response(responseHead))
                continuation.yield(.data(Data("complete".utf8)))
                continuation.finish()

                // Assert
                let response = try await pendingResponse
                #expect(response.status.code == 202)
                #expect(response.headers[.contentType] == "application/json")
                #expect(response.body.map { String(buffer: $0) } == "complete")
            }
        }
    }
}

private final class HTTPStreamLifetimeProbe: Sendable {
    private let cancellationRecorded = Mutex(false)
    private let bodyWriteRecorded = Mutex(false)
    private let connectionCloseRecorded = Mutex(false)

    func recordCancellation() { cancellationRecorded.withLock { $0 = true } }
    func recordBodyWrite() { bodyWriteRecorded.withLock { $0 = true } }
    func recordConnectionClose() { connectionCloseRecorded.withLock { $0 = true } }

    func waitForCancellation() async -> Bool {
        let deadline = ContinuousClock.now + .seconds(1)
        while ContinuousClock.now < deadline {
            if cancellationRecorded.withLock({ $0 }) { return true }
            await Task.yield()
        }
        return cancellationRecorded.withLock { $0 }
    }

    func waitForBodyWrite() async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if bodyWriteRecorded.withLock({ $0 }) { return true }
            await Task.yield()
        }
        return bodyWriteRecorded.withLock { $0 }
    }

    func waitForConnectionClose() async -> Bool {
        let deadline = ContinuousClock.now + .seconds(1)
        while ContinuousClock.now < deadline {
            if connectionCloseRecorded.withLock({ $0 }) { return true }
            await Task.yield()
        }
        return connectionCloseRecorded.withLock { $0 }
    }

}
