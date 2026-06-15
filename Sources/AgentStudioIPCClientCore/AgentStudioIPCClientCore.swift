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
    }

    public let reason: Reason

    public init(reason: Reason) {
        self.reason = reason
    }
}

public enum AgentStudioIPCClientCommand: Equatable, Sendable {
    case authLogin(token: String)
    case identify
    case capabilities
    case listWindows
    case listWorkspaces
    case listPanes
    case currentPane
    case paneFocus(handle: String)
    case terminalSend(handle: String, input: String, correlationId: UUID?)
    case terminalWait(handle: String, condition: IPCTerminalWaitCondition, timeoutSeconds: Double)
    case eventsSubscribe(eventNames: [IPCEventName])
    case eventsUnsubscribe(subscriptionId: UUID)

    public var methodName: String {
        switch self {
        case .authLogin:
            "auth.login"
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
        case .terminalSend:
            "terminal.send"
        case .terminalWait:
            "terminal.wait"
        case .eventsSubscribe:
            "events.subscribe"
        case .eventsUnsubscribe:
            "events.unsubscribe"
        }
    }

    public var params: JSONValue {
        switch self {
        case .authLogin(let token):
            return .object(["token": .string(token)])
        case .identify, .capabilities, .listWindows, .listWorkspaces, .listPanes, .currentPane:
            return .object([:])
        case .paneFocus(let handle):
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
        case .terminalWait(let handle, let condition, let timeoutSeconds):
            return .object([
                "handle": .string(handle),
                "condition": .string(condition.rawValue),
                "timeoutSeconds": .number(timeoutSeconds),
            ])
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
        return try call(.authLogin(token: authToken), requestId: requestId)
    }

    public func call(_ command: AgentStudioIPCClientCommand, requestId: Int = 1) throws -> JSONRPCResponseMessage {
        let request = try requestFrame(command, requestId: requestId)
        let connection = try UnixSocketClient.connect(
            endpoint: UnixSocketEndpoint(path: configuration.socketPath)
        )
        defer {
            connection.close()
        }

        try connection.send(try NDJSONFrameEncoder.encode(request, maxFrameBytes: configuration.maxFrameBytes))

        var decoder = NDJSONFrameDecoder(maxFrameBytes: configuration.maxFrameBytes)
        while true {
            let data = try connection.receive(maxBytes: min(configuration.maxFrameBytes, 16_384))
            guard !data.isEmpty else {
                throw AgentStudioIPCClientError(reason: .emptyResponse)
            }
            let frames = try decoder.append(data)
            guard let frame = frames.first else {
                continue
            }
            let response = try JSONRPCCodec.decodeResponse(frame)
            guard response.id == .number(requestId) else {
                throw AgentStudioIPCClientError(reason: .responseIdMismatch)
            }
            return response
        }
    }

    public func requestFrame(_ command: AgentStudioIPCClientCommand, requestId: Int = 1) throws -> String {
        let request = try JSONRPCClientRequest(
            id: .number(requestId),
            method: command.methodName,
            params: command.params
        )
        return try JSONRPCCodec.encodeRequest(request)
    }
}
