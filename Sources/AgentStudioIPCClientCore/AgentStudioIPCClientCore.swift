import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
import Foundation

public struct AgentStudioIPCClientConfiguration: Equatable, Sendable {
    public let socketPath: String
    public let authToken: String?
    public let maxFrameBytes: Int

    public init(socketPath: String, authToken: String? = nil, maxFrameBytes: Int = 1_048_576) {
        self.socketPath = socketPath
        self.authToken = authToken
        self.maxFrameBytes = maxFrameBytes
    }

    public func withAuthToken(_ authToken: String?) -> Self {
        Self(socketPath: socketPath, authToken: authToken, maxFrameBytes: maxFrameBytes)
    }
}

public struct AgentStudioIPCClientRuntimeMetadata: Decodable, Equatable, Sendable {
    public let socketPath: String
    public let `protocol`: String

    public init(socketPath: String, protocol: String) {
        self.socketPath = socketPath
        self.protocol = `protocol`
    }
}

public enum AgentStudioIPCClientDiscovery {
    public static func socketPath(
        explicitSocketPath: String?,
        environment: [String: String],
        metadataURL: URL?
    ) throws -> String {
        if let explicitSocketPath, !explicitSocketPath.isEmpty {
            return explicitSocketPath
        }
        if let environmentSocketPath = environment["AGENTSTUDIO_IPC_SOCKET"], !environmentSocketPath.isEmpty {
            return environmentSocketPath
        }
        if let legacyEnvironmentSocketPath = environment["AGENTSTUDIO_IPC_SOCKET_PATH"],
            !legacyEnvironmentSocketPath.isEmpty
        {
            return legacyEnvironmentSocketPath
        }
        if let metadataURL {
            let data = try Data(contentsOf: metadataURL)
            let metadata = try JSONDecoder().decode(AgentStudioIPCClientRuntimeMetadata.self, from: data)
            return metadata.socketPath
        }

        throw AgentStudioIPCClientError(reason: .socketNotFound)
    }
}

public struct AgentStudioIPCClientError: Error, Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        case socketNotFound
        case invalidArguments
        case emptyResponse
        case responseIdMismatch
        case authenticationFailed
    }

    public let reason: Reason

    public init(reason: Reason) {
        self.reason = reason
    }
}

public enum AgentStudioIPCClientCommand: Equatable, Sendable {
    case authLogin
    case authStatus
    case identify
    case capabilities
    case listWindows
    case listWorkspaces
    case listPanes
    case currentPane
    case paneFocus(handle: String)
    case commandList
    case commandExecute(IPCCommandExecuteParams)
    case terminalStatus(handle: String)
    case terminalSend(handle: String, input: String, correlationId: UUID?)
    case terminalWait(
        handle: String, condition: IPCTerminalWaitCondition, timeoutSeconds: Double, afterSequence: UInt64?)
    case bridgeDiffLoad(IPCBridgeReviewOpenParams)
    case bridgeDiffRefresh(IPCBridgeReviewRefreshParams)
    case bridgeDiffGetPackage(handle: String)
    case bridgeDiffRenderState(handle: String)
    case bridgeDiffSelectFile(IPCBridgeReviewSelectFileParams)
    case bridgeFileViewGetContent(IPCBridgeContentGetParams)
    case bridgeTelemetrySnapshot(handle: String)
    case bridgeTelemetryFlush(handle: String)
    case eventsSubscribe(eventNames: [IPCEventName])
    case eventsUnsubscribe(subscriptionId: UUID)

    public var methodName: String {
        switch self {
        case .authLogin:
            "auth.login"
        case .authStatus:
            "auth.status"
        case .identify:
            "system.identify"
        case .capabilities:
            "system.capabilities"
        case .listWindows:
            "window.list"
        case .listWorkspaces:
            "workspace.list"
        case .listPanes:
            "pane.list"
        case .currentPane:
            "pane.current"
        case .paneFocus:
            "pane.focus"
        case .commandList:
            "command.list"
        case .commandExecute:
            "command.execute"
        case .terminalStatus:
            "terminal.status"
        case .terminalSend:
            "terminal.send"
        case .terminalWait:
            "terminal.wait"
        case .bridgeDiffLoad:
            "bridge.diff.load"
        case .bridgeDiffRefresh:
            "bridge.diff.refresh"
        case .bridgeDiffGetPackage:
            "bridge.diff.getPackage"
        case .bridgeDiffRenderState:
            "bridge.diff.renderState"
        case .bridgeDiffSelectFile:
            "bridge.diff.selectFile"
        case .bridgeFileViewGetContent:
            "bridge.fileView.getContent"
        case .bridgeTelemetrySnapshot:
            "bridge.telemetry.snapshot"
        case .bridgeTelemetryFlush:
            "bridge.telemetry.flush"
        case .eventsSubscribe:
            "events.subscribe"
        case .eventsUnsubscribe:
            "events.unsubscribe"
        }
    }

    public var requiresStreamingResponse: Bool {
        switch self {
        case .eventsSubscribe:
            true
        case .authLogin, .authStatus, .identify, .capabilities, .listWindows, .listWorkspaces, .listPanes,
            .currentPane, .paneFocus, .commandList, .commandExecute, .terminalStatus, .terminalSend, .terminalWait,
            .bridgeDiffLoad, .bridgeDiffRefresh, .bridgeDiffGetPackage, .bridgeDiffRenderState,
            .bridgeDiffSelectFile, .bridgeFileViewGetContent, .bridgeTelemetrySnapshot, .bridgeTelemetryFlush,
            .eventsUnsubscribe:
            false
        }
    }

    public func params(authToken: String?) throws -> JSONValue {
        switch self {
        case .authLogin:
            guard let authToken, !authToken.isEmpty else {
                throw AgentStudioIPCClientError(reason: .invalidArguments)
            }
            return .object(["token": .string(authToken)])
        case .authStatus, .identify, .capabilities, .listWindows, .listWorkspaces, .listPanes, .currentPane,
            .commandList:
            return .object([:])
        case .paneFocus(let handle):
            return .object(["handle": .string(handle)])
        case .commandExecute(let params):
            return try JSONRPCCodec.encodeJSONValue(params)
        case .terminalStatus(let handle):
            return .object(["handle": .string(handle)])
        case .terminalSend(let handle, let input, let correlationId):
            var params: [String: JSONValue] = [
                "handle": .string(handle),
                "input": .string(input),
            ]
            if let correlationId {
                params["correlationId"] = .string(correlationId.uuidString)
            }
            return .object(params)
        case .terminalWait(let handle, let condition, let timeoutSeconds, let afterSequence):
            var params: [String: JSONValue] = [
                "handle": .string(handle),
                "condition": .string(condition.rawValue),
                "timeoutSeconds": .number(timeoutSeconds),
            ]
            if let afterSequence {
                params["afterSequence"] = .number(Double(afterSequence))
            }
            return .object(params)
        case .bridgeDiffLoad(let params):
            return try JSONRPCCodec.encodeJSONValue(params)
        case .bridgeDiffRefresh(let params):
            return try JSONRPCCodec.encodeJSONValue(params)
        case .bridgeDiffGetPackage(let handle):
            return .object(["handle": .string(handle)])
        case .bridgeDiffRenderState(let handle):
            return .object(["handle": .string(handle)])
        case .bridgeDiffSelectFile(let params):
            return try JSONRPCCodec.encodeJSONValue(params)
        case .bridgeFileViewGetContent(let params):
            return try JSONRPCCodec.encodeJSONValue(params)
        case .bridgeTelemetrySnapshot(let handle):
            return .object(["handle": .string(handle)])
        case .bridgeTelemetryFlush(let handle):
            return .object(["handle": .string(handle)])
        case .eventsSubscribe(let eventNames):
            return .object([
                "eventNames": .array(eventNames.map { .string($0.rawValue) })
            ])
        case .eventsUnsubscribe(let subscriptionId):
            return .object(["subscriptionId": .string(subscriptionId.uuidString)])
        }
    }
}

public struct AgentStudioIPCClient: Sendable {
    public let configuration: AgentStudioIPCClientConfiguration

    public init(configuration: AgentStudioIPCClientConfiguration) {
        self.configuration = configuration
    }

    public func login(requestId: Int = 1) throws -> JSONRPCResponseMessage {
        guard let authToken = configuration.authToken, !authToken.isEmpty else {
            throw AgentStudioIPCClientError(reason: .invalidArguments)
        }
        _ = authToken
        return try call(.authLogin, requestId: requestId)
    }

    public func call(_ command: AgentStudioIPCClientCommand, requestId: Int = 1) throws -> JSONRPCResponseMessage {
        let connection = try UnixSocketClient.connect(
            endpoint: UnixSocketEndpoint(path: configuration.socketPath)
        )
        defer {
            connection.close()
        }

        var frameReader = AgentStudioIPCClientFrameReader(maxFrameBytes: configuration.maxFrameBytes)
        let commandRequestId = try sendAuthenticatedCommand(
            command,
            requestId: requestId,
            connection: connection,
            frameReader: &frameReader
        )
        return try receiveResponse(id: commandRequestId, connection: connection, frameReader: &frameReader)
    }

    public func stream(
        _ command: AgentStudioIPCClientCommand,
        requestId: Int = 1,
        onFrame: (String) throws -> Void
    ) throws {
        guard command.requiresStreamingResponse else {
            let response = try call(command, requestId: requestId)
            try onFrame(try JSONRPCCodec.encodeResponse(JSONRPCResponse.message(response)))
            return
        }

        let connection = try UnixSocketClient.connect(
            endpoint: UnixSocketEndpoint(path: configuration.socketPath)
        )
        defer {
            connection.close()
        }

        var frameReader = AgentStudioIPCClientFrameReader(maxFrameBytes: configuration.maxFrameBytes)
        let commandRequestId = try sendAuthenticatedCommand(
            command,
            requestId: requestId,
            connection: connection,
            frameReader: &frameReader
        )

        var sawSubscriptionResponse = false
        while true {
            let frame: String
            do {
                frame = try frameReader.receiveFrame(connection: connection)
            } catch let error as AgentStudioIPCClientError
                where error.reason == .emptyResponse && sawSubscriptionResponse
            {
                return
            }
            if let response = try? JSONRPCCodec.decodeResponse(frame) {
                guard response.id == .number(commandRequestId) else {
                    if sawSubscriptionResponse {
                        try onFrame(frame)
                        continue
                    }
                    throw AgentStudioIPCClientError(reason: .responseIdMismatch)
                }
                sawSubscriptionResponse = true
                try onFrame(frame)
                continue
            }

            guard sawSubscriptionResponse else {
                throw AgentStudioIPCClientError(reason: .responseIdMismatch)
            }
            try onFrame(frame)
        }
    }

    public func requestFrame(_ command: AgentStudioIPCClientCommand, requestId: Int = 1) throws -> String {
        let request = try JSONRPCClientRequest(
            id: .number(requestId),
            method: command.methodName,
            params: command.params(authToken: configuration.authToken)
        )
        return try JSONRPCCodec.encodeRequest(request)
    }

    private func sendAuthenticatedCommand(
        _ command: AgentStudioIPCClientCommand,
        requestId: Int,
        connection: UnixSocketConnection,
        frameReader: inout AgentStudioIPCClientFrameReader
    ) throws -> Int {
        if configuration.authToken != nil, command != .authLogin {
            try send(.authLogin, requestId: requestId, connection: connection)
            let loginResponse = try receiveResponse(id: requestId, connection: connection, frameReader: &frameReader)
            guard loginResponse.error == nil else {
                throw AgentStudioIPCClientError(reason: .authenticationFailed)
            }
            let commandRequestId = requestId + 1
            try send(command, requestId: commandRequestId, connection: connection)
            return commandRequestId
        }

        try send(command, requestId: requestId, connection: connection)
        return requestId
    }

    private func send(
        _ command: AgentStudioIPCClientCommand,
        requestId: Int,
        connection: UnixSocketConnection
    ) throws {
        try connection.send(
            try NDJSONFrameEncoder.encode(
                requestFrame(command, requestId: requestId),
                maxFrameBytes: configuration.maxFrameBytes
            ))
    }

    private func receiveResponse(
        id: Int,
        connection: UnixSocketConnection,
        frameReader: inout AgentStudioIPCClientFrameReader
    ) throws -> JSONRPCResponseMessage {
        while true {
            let frame = try frameReader.receiveFrame(connection: connection)
            let response = try JSONRPCCodec.decodeResponse(frame)
            guard response.id == .number(id) else {
                throw AgentStudioIPCClientError(reason: .responseIdMismatch)
            }
            return response
        }
    }

}

private struct AgentStudioIPCClientFrameReader {
    private let maxFrameBytes: Int
    private var decoder: NDJSONFrameDecoder
    private var queuedFrames: [String] = []

    init(maxFrameBytes: Int) {
        self.maxFrameBytes = maxFrameBytes
        decoder = NDJSONFrameDecoder(maxFrameBytes: maxFrameBytes)
    }

    mutating func receiveFrame(connection: UnixSocketConnection) throws -> String {
        if !queuedFrames.isEmpty {
            return queuedFrames.removeFirst()
        }

        while true {
            let data = try connection.receive(maxBytes: min(maxFrameBytes, 16_384))
            guard !data.isEmpty else {
                throw AgentStudioIPCClientError(reason: .emptyResponse)
            }
            queuedFrames.append(contentsOf: try decoder.append(data))
            if !queuedFrames.isEmpty {
                return queuedFrames.removeFirst()
            }
        }
    }
}

extension JSONRPCResponse {
    fileprivate static func message(_ message: JSONRPCResponseMessage) throws -> Self {
        if let result = message.result {
            return .success(id: message.id, result: result)
        }
        if let error = message.error {
            return .failure(id: message.id, error: error)
        }
        throw JSONRPCError(reason: .invalidResponse, message: "Response message had neither result nor error")
    }
}
