import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
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
