import AgentStudioIPCClientCore
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation

@main
struct AgentStudioIPCClientMain {
    static func main() {
        do {
            let readInput = { FileHandle.standardInput.readDataToEndOfFile() }
            let global = try AgentStudioIPCClientArguments.parseGlobal(
                Array(CommandLine.arguments.dropFirst()), environment: ProcessInfo.processInfo.environment,
                standardInputProvider: readInput
            )
            let examples = IPCBuiltInMethodExampleContext(illustrativeIdentifier: UUIDv7.generate())
            let bootstrap = try IPCBuiltInMethodCatalog.bootstrapDescriptors(examples: examples)
            let discoveryClient = AgentStudioIPCClient(configuration: global.configuration, descriptors: bootstrap)
            if global.methodArguments == ["system.capabilities"] {
                try write(JSONEncoder().encode(discoveryClient.discoverCatalog()))
                return
            }
            let descriptors: [IPCAnyMethodDescriptor]
            if bootstrap.contains(where: { $0.metadata.name == global.methodArguments.first }) {
                descriptors = bootstrap
            } else {
                descriptors = try IPCBuiltInMethodCatalog.matchingDiscoveredMethods(
                    discoveryClient.discoverCatalog(), examples: examples
                )
            }
            let invocation = try AgentStudioIPCClientArguments.parseMethod(
                global, descriptors: descriptors, correlationIDGenerator: { UUIDv7.generate() },
                standardInputProvider: readInput
            ).descriptorInvocation
            let client = AgentStudioIPCClient(configuration: global.configuration, descriptors: descriptors)
            if invocation.descriptor.metadata.responseDelivery == .subscription {
                try client.stream(invocation) { frame in
                    switch frame {
                    case .initialResponse(let response): try write(response.normalizedResult)
                    case .notification(let notification): print(notification)
                    case .remoteFailure: throw CLIExit.rejected
                    }
                }
            } else {
                switch try client.call(invocation) {
                case .success(let response):
                    if case .model(let presentation) = invocation.presentation, !presentation.showsDetail {
                        print(presentation.successReply)
                    } else {
                        try write(response.normalizedResult)
                    }
                case .remoteFailure:
                    throw CLIExit.rejected
                }
            }
        } catch let failure as IPCDescriptorClientFailure where failure.disposition == .deliveryUncertain {
            fputs("Delivery uncertain.\n", stderr)
            exit(1)
        } catch {
            fputs("Agent Studio request rejected or unavailable.\n", stderr)
            exit(1)
        }
    }

    private static func write(_ data: Data) throws {
        guard let output = String(data: data, encoding: .utf8) else { throw CLIExit.rejected }
        print(output)
    }
}

private enum CLIExit: Error { case rejected }
