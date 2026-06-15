import AgentStudioIPCClientCore
import AgentStudioIPCTransport
import Foundation

@main
struct AgentStudioPaneAgentMain {
    static func main() throws {
        let environment = ProcessInfo.processInfo.environment
        let socketPath = try AgentStudioIPCClientDiscovery.socketPath(
            explicitSocketPath: nil,
            environment: environment,
            metadataURL: nil
        )
        let bootstrapFileDescriptor = try AgentStudioIPCBootstrapTokenReader.bootstrapFileDescriptor(
            environment: environment
        )
        let token = try AgentStudioIPCBootstrapTokenReader.readTokenAndClose(
            fileDescriptor: bootstrapFileDescriptor
        )
        let client = AgentStudioIPCClient(
            configuration: AgentStudioIPCClientConfiguration(socketPath: socketPath, authToken: token)
        )
        let response = try client.call(.identify, requestId: 1)
        if let error = response.error {
            throw AgentStudioPaneAgentError.authenticationFailed(error.message)
        }
        if let expectedRuntimeId = environment["AGENTSTUDIO_IPC_RUNTIME_ID"],
            case .object(let result)? = response.result,
            result["runtimeId"] != .string(expectedRuntimeId)
        {
            throw AgentStudioPaneAgentError.runtimeMismatch
        }
    }
}

private enum AgentStudioPaneAgentError: Error {
    case authenticationFailed(String)
    case runtimeMismatch
}
