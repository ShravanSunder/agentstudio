import AgentStudioIPCTransport
import Foundation

/// The connection owns these synchronous operations. The production binding
/// retains the transport's partial-write loop and descriptor lifetime rules.
package struct AppIPCConnectionIO: Sendable {
    package let receive: @Sendable (Int) throws -> Data
    package let send: @Sendable (Data) throws -> Void
    package let close: @Sendable () -> Void

    package init(
        receive: @escaping @Sendable (Int) throws -> Data,
        send: @escaping @Sendable (Data) throws -> Void,
        close: @escaping @Sendable () -> Void
    ) {
        self.receive = receive
        self.send = send
        self.close = close
    }

    package static func live(_ connection: UnixSocketConnection) -> Self {
        Self(
            receive: { try connection.receive(maxBytes: $0) },
            send: { try connection.send($0) },
            close: { connection.close() }
        )
    }
}

package enum AppIPCFrameEnqueueResult: Equatable, Sendable {
    case accepted
    case overloaded
}

package actor AgentStudioAppIPCConnectionWriter {
    private let io: AppIPCConnectionIO
    private let maxFrameBytes: Int

    package init(io: AppIPCConnectionIO, maxFrameBytes: Int) {
        self.io = io
        self.maxFrameBytes = maxFrameBytes
    }

    @discardableResult
    package func sendResponse(_ response: JSONRPCResponse) throws -> AppIPCFrameEnqueueResult {
        try sendFrame(JSONRPCCodec.encodeResponse(response))
    }

    @discardableResult
    package func sendError(id: JSONRPCIdentifier?, code: Int, message: String, data: JSONValue? = nil) throws
        -> AppIPCFrameEnqueueResult
    {
        try sendResponse(
            JSONRPCResponse.failure(
                id: id,
                error: JSONRPCErrorPayload(code: code, message: message, data: data)
            ))
    }

    @discardableResult
    package func sendFrame(_ frame: String) throws -> AppIPCFrameEnqueueResult {
        try io.send(try NDJSONFrameEncoder.encode(frame, maxFrameBytes: maxFrameBytes))
        return .accepted
    }
}

package actor AgentStudioAppIPCSocketEventSubscriber: IPCEventSubscriber {
    private let writer: AgentStudioAppIPCConnectionWriter

    package init(writer: AgentStudioAppIPCConnectionWriter) {
        self.writer = writer
    }

    package func deliver(_ frame: String) async throws -> IPCEventDeliveryResult {
        try await writer.sendFrame(frame)
        return .delivered
    }
}
