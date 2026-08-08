import AgentStudioBridge
import Foundation
import ServiceLifecycle

@main
enum AgentStudioBridgeDevelopmentServerMain {
    static func main() async throws {
        #if DEBUG
            let configuration = try commandLineConfiguration(arguments: CommandLine.arguments)
            let host = try await BridgeDevelopmentProductHost(
                source: BridgeDevelopmentProductSource(
                    worktreeRoot: configuration.worktreeRoot,
                    reviewBase: configuration.reviewBase
                )
            )
            do {
                let application = BridgeDevelopmentHTTPApplication.make(
                    host: host,
                    configuration: configuration.applicationConfiguration
                )
                let serviceGroup = ServiceGroup(
                    configuration: .init(
                        services: [
                            application,
                            BridgeDevelopmentProductHostShutdownService(host: host),
                        ],
                        gracefulShutdownSignals: [.sigterm, .sigint],
                        logger: application.logger
                    )
                )
                try await serviceGroup.run()
                await host.shutdown()
            } catch {
                await host.shutdown()
                throw error
            }
        #else
            throw BridgeDevelopmentServerMainError.debugBuildRequired
        #endif
    }

    private static func commandLineConfiguration(
        arguments: [String]
    ) throws -> BridgeDevelopmentServerConfiguration {
        let values = try commandLineValues(arguments: arguments)
        guard let worktreePath = values["--worktree"],
            let reviewBase = values["--base"],
            let portValue = values["--port"],
            let port = Int(portValue)
        else {
            throw BridgeDevelopmentServerMainError.invalidArguments
        }
        return try BridgeDevelopmentServerConfiguration(
            worktreeRoot: URL(fileURLWithPath: worktreePath),
            reviewBase: reviewBase,
            port: port
        )
    }

    private static func commandLineValues(arguments: [String]) throws -> [String: String] {
        let values = Array(arguments.dropFirst())
        guard values.count.isMultiple(of: 2) else {
            throw BridgeDevelopmentServerMainError.invalidArguments
        }
        var result: [String: String] = [:]
        for index in stride(from: 0, to: values.count, by: 2) {
            let key = values[index]
            guard ["--worktree", "--base", "--port"].contains(key),
                result.updateValue(values[index + 1], forKey: key) == nil
            else {
                throw BridgeDevelopmentServerMainError.invalidArguments
            }
        }
        return result
    }
}

private enum BridgeDevelopmentServerMainError: Error {
    case debugBuildRequired
    case invalidArguments
}
