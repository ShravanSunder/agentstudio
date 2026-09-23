import AgentStudioAppIPC
import AgentStudioIPCClientCore
import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
import AgentStudioTestSupport
import Foundation
import Testing

func sendRequest(socketPath: String, request: JSONRPCClientRequest) throws -> JSONRPCResponseMessage {
    let connection = try UnixSocketClient.connect(endpoint: UnixSocketEndpoint(path: socketPath))
    defer {
        connection.close()
    }
    try sendRequest(connection: connection, request: request)
    var reader = TestFrameReader()
    return try reader.receiveResponse(connection: connection)
}

func sendRequestWithoutBlockingMainActor(socketPath: String, request: JSONRPCClientRequest) async throws
    -> JSONRPCResponseMessage
{
    let connection = try UnixSocketClient.connect(endpoint: UnixSocketEndpoint(path: socketPath))
    defer {
        connection.close()
    }
    try sendRequest(connection: connection, request: request)
    var reader = TestFrameReader()
    return try await reader.receiveResponseWithoutBlockingMainActor(connection: connection)
}

func sendRequest(connection: UnixSocketConnection, request: JSONRPCClientRequest) throws {
    try connection.send(
        try NDJSONFrameEncoder.encode(
            JSONRPCCodec.encodeRequest(request),
            maxFrameBytes: 65_536
        ))
}

func login(
    connection: UnixSocketConnection,
    token: AgentStudioIPCSubjectToken,
    requestId: Int,
    reader: inout TestFrameReader
) throws {
    try sendRequest(
        connection: connection,
        request: JSONRPCClientRequest(
            id: .number(requestId),
            method: "auth.login",
            params: .object(["token": .string(token.rawValue)])
        )
    )
    let response = try reader.receiveResponse(connection: connection)
    try #require(response.id == .number(requestId))
    try #require(response.error == nil)
}

func loginWithoutBlockingMainActor(
    connection: UnixSocketConnection,
    token: AgentStudioIPCSubjectToken,
    requestId: Int,
    reader: inout TestFrameReader
) async throws {
    try sendRequest(
        connection: connection,
        request: JSONRPCClientRequest(
            id: .number(requestId),
            method: "auth.login",
            params: .object(["token": .string(token.rawValue)])
        )
    )
    let response = try await reader.receiveResponseWithoutBlockingMainActor(connection: connection)
    try #require(response.id == .number(requestId))

    var rejectionContext = "auth.login rejection was not observed"
    if response.error != nil {
        do {
            try sendRequest(
                connection: connection,
                request: JSONRPCClientRequest(
                    id: .number(requestId + 1_000_000),
                    method: "auth.status",
                    params: .object([:])
                )
            )
            let status = try await reader.receiveResponseWithoutBlockingMainActor(connection: connection)
            let authenticated: Bool?
            if case .object(let result)? = status.result,
                case .bool(let value)? = result["authenticated"]
            {
                authenticated = value
            } else {
                authenticated = nil
            }
            rejectionContext =
                "post-rejection auth.status error code: \(status.error?.code.description ?? "none"); "
                + "authenticated: \(authenticated?.description ?? "unknown")"
        } catch {
            rejectionContext = "post-rejection auth.status transport failed"
        }
    }
    try #require(response.error == nil, Comment(rawValue: rejectionContext))
}

func decodeResponseResult<T: Decodable>(
    _ type: T.Type,
    from response: JSONRPCResponseMessage
) throws -> T {
    let result = try #require(response.result)
    return try decodeJSONValue(type, from: result)
}

func decodeJSONValue<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(type, from: data)
}

struct TestFrameReader {
    var decoder = NDJSONFrameDecoder(maxFrameBytes: 1_048_576)
    var queuedFrames: [String] = []

    mutating func receiveResponse(connection: UnixSocketConnection) throws -> JSONRPCResponseMessage {
        try JSONRPCCodec.decodeResponse(receiveFrame(connection: connection))
    }

    mutating func receiveFrame(connection: UnixSocketConnection) throws -> String {
        if !queuedFrames.isEmpty {
            return queuedFrames.removeFirst()
        }
        while true {
            let data = try connection.receive(maxBytes: 4096)
            queuedFrames.append(contentsOf: try decoder.append(data))
            if !queuedFrames.isEmpty {
                return queuedFrames.removeFirst()
            }
        }
    }

    func hasBufferedFrame(containing text: String) -> Bool {
        queuedFrames.contains { $0.contains(text) }
    }

    mutating func receiveResponseWithoutBlockingMainActor(connection: UnixSocketConnection) async throws
        -> JSONRPCResponseMessage
    {
        if !queuedFrames.isEmpty {
            return try JSONRPCCodec.decodeResponse(queuedFrames.removeFirst())
        }
        while true {
            let data = try await receiveDataWithoutBlockingMainActor(connection: connection)
            queuedFrames.append(contentsOf: try decoder.append(data))
            if !queuedFrames.isEmpty {
                return try JSONRPCCodec.decodeResponse(queuedFrames.removeFirst())
            }
        }
    }

    private func receiveDataWithoutBlockingMainActor(connection: UnixSocketConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    continuation.resume(returning: try connection.receive(maxBytes: 4096))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// `AgentStudioIPCClient` is synchronous: every call sends a frame and then
/// blocks in `UnixSocketConnection.receive` until the app answers. From a test
/// body that block lands on the cooperative executor, which is where the
/// server's own connection handler needs to run, so these shims move the wait
/// to a libdispatch thread. See `withoutBlockingCooperativePool`.
extension AgentStudioIPCClient {
    func discoverCatalogWithoutBlockingCooperativePool(
        requestID: Int = 1
    ) async throws -> IPCMethodCatalogResult {
        try await withoutBlockingCooperativePool { try discoverCatalog(requestID: requestID) }
    }

    func callWithoutBlockingCooperativePool(
        _ invocation: IPCDescriptorInvocation,
        requestID: Int = 1
    ) async throws -> IPCDescriptorClientCallResult {
        try await withoutBlockingCooperativePool { try call(invocation, requestID: requestID) }
    }
}

/// The socket-path form of `sendRequest`, off the cooperative pool. The
/// connection is opened, used and closed inside the one hop.
func sendRequestWithoutBlockingCooperativePool(
    socketPath: String,
    request: JSONRPCClientRequest
) async throws -> JSONRPCResponseMessage {
    try await withoutBlockingCooperativePool { try sendRequest(socketPath: socketPath, request: request) }
}

/// Reads one request inside a `UnixSocketListener.start` handler.
///
/// This blocking receive is correct where it is used: the listener invokes its
/// handler on its own serial dispatch queue, never on the cooperative executor,
/// so parking here costs a libdispatch thread rather than one the IPC server
/// needs. It lives in this file so the blocking primitive stays in the handful
/// of allowlisted places the lint rule knows about.
func receiveListenerHandlerRequest(
    connection: UnixSocketConnection,
    decoder: inout NDJSONFrameDecoder
) throws -> JSONRPCRequest {
    while true {
        let data = try connection.receive(maxBytes: 4096)
        let frames = try decoder.append(data)
        if let frame = frames.first {
            return try JSONRPCCodec.decodeRequest(frame)
        }
    }
}
