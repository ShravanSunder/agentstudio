import AgentStudioIPCClientCore
import Foundation

@main
struct AgentStudioIPCClientMain {
    static func main() throws {
        do {
            let invocation = try AgentStudioIPCClientArguments.parse(Array(CommandLine.arguments.dropFirst()))
            let client = AgentStudioIPCClient(configuration: invocation.configuration)
            let response = try client.call(invocation.command)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(response)
            guard let output = String(data: data, encoding: .utf8) else {
                throw AgentStudioIPCClientError(reason: .emptyResponse)
            }
            print(output)
        } catch {
            fputs("agentstudio-ipc: \(error)\n", stderr)
            throw error
        }
    }
}
