import AgentStudioIPCClientCore
import Foundation

@main
struct AgentStudioIPCClientMain {
    static func main() throws {
        do {
            let invocation = try AgentStudioIPCClientArguments.parse(Array(CommandLine.arguments.dropFirst()))
            let configuration =
                if invocation.readsAuthTokenFromStandardInput {
                    invocation.configuration.withAuthToken(try readStandardInputToken())
                } else {
                    invocation.configuration
                }
            let client = AgentStudioIPCClient(configuration: configuration)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]

            if invocation.command.requiresStreamingResponse {
                try client.stream(invocation.command) { frame in
                    print(frame)
                }
            } else {
                let response = try client.call(invocation.command)
                let data = try encoder.encode(response)
                guard let output = String(data: data, encoding: .utf8) else {
                    throw AgentStudioIPCClientError(reason: .emptyResponse)
                }
                print(output)
            }
        } catch {
            fputs("agentstudio-ipc: \(error)\n", stderr)
            throw error
        }
    }

    private static func readStandardInputToken() throws -> String {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard
            let token = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !token.isEmpty
        else {
            throw AgentStudioIPCClientError(reason: .invalidArguments)
        }
        return token
    }
}
