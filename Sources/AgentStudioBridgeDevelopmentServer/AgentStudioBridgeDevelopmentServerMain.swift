import AgentStudioBridge
import AgentStudioCore
import Foundation
import ServiceLifecycle

@main
enum AgentStudioBridgeDevelopmentServerMain {
    static func main() async throws {
        #if DEBUG
            let configuration = try commandLineConfiguration(arguments: CommandLine.arguments)
            let coreComposition = try await BridgeDevelopmentServerCoreComposition.prepare(
                configuration: configuration
            )
            let host = try await BridgeDevelopmentProductHost(
                source: coreComposition.productSource,
                worktreeAnnotationStore: coreComposition.worktreeAnnotationStore,
                worktreeAnnotationOutputCoordinator:
                    coreComposition.worktreeAnnotationOutputCoordinator,
                originatingWorkspaceID: coreComposition.originatingWorkspaceID,
                reviewSharedContentRootURL: configuration.reviewSharedContentRootURL,
                contributionTargetCommit: { target in
                    coreComposition.applyContributionTarget(target)
                }
            )
            let observation = BridgeDevelopmentSeededWorktreeObservation(
                source: coreComposition.productSource,
                invalidationSink: { invalidation in
                    await host.handleObservedWorktreeInvalidation(invalidation)
                }
            )
            let runtime = BridgeDevelopmentServerRuntime(
                coreComposition: coreComposition,
                host: host,
                observation: observation
            )
            do {
                try await runtime.start()
                let application = BridgeDevelopmentHTTPApplication.make(
                    host: host,
                    configuration: configuration.applicationConfiguration
                )
                let serviceGroup = ServiceGroup(
                    configuration: .init(
                        services: [
                            application,
                            BridgeDevelopmentServerRuntimeShutdownService(runtime: runtime),
                        ],
                        gracefulShutdownSignals: [.sigterm, .sigint],
                        logger: application.logger
                    )
                )
                try await serviceGroup.run()
                try await runtime.shutdown()
            } catch {
                try? await runtime.shutdown()
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
        guard let dataRootPath = values["--data-root"],
            let paneIDValue = values["--pane-id"],
            let paneID = UUID(uuidString: paneIDValue),
            let seedWorktreePath = values["--seed-worktree"],
            let seedTarget = values["--seed-target"],
            let portValue = values["--port"],
            let port = Int(portValue)
        else {
            throw BridgeDevelopmentServerMainError.invalidArguments
        }
        return try BridgeDevelopmentServerConfiguration(
            dataRoot: URL(fileURLWithPath: dataRootPath),
            paneID: paneID,
            port: port,
            seedContributionTarget: .ref(name: seedTarget),
            seedWorktreeRoot: URL(fileURLWithPath: seedWorktreePath)
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
            guard
                ["--data-root", "--pane-id", "--port", "--seed-target", "--seed-worktree"]
                    .contains(key),
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
