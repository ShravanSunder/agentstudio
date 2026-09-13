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
        if let metadataURL {
            let data = try Data(contentsOf: metadataURL)
            let metadata = try JSONDecoder().decode(AgentStudioIPCClientRuntimeMetadata.self, from: data)
            guard metadata.protocol == IPCProtocolCatalogCompatibility.current.wireProtocolIdentifier else {
                throw AgentStudioIPCClientError(reason: .invalidArguments)
            }
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
