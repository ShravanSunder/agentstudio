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
            var commandCatalog: IPCDiscoveredCommandCatalog?
            if bootstrap.contains(where: { $0.metadata.name == global.methodArguments.first }) {
                descriptors = bootstrap
            } else {
                let catalog = try discoveryClient.discoverCatalog()
                if global.methodArguments.first == "command.list" || global.methodArguments.first == "command.execute" {
                    let discovery = try IPCCommandDiscovery(methodCatalog: catalog)
                    let listClient = AgentStudioIPCClient(
                        configuration: global.configuration, descriptors: [discovery.commandListInvocation.descriptor])
                    guard case .success(let response) = try listClient.call(discovery.commandListInvocation) else {
                        throw CLIExit.rejected
                    }
                    let commands = try discovery.decodeCommandCatalog(from: response.normalizedResult)
                    if global.methodArguments.first == "command.list" {
                        _ = try AgentStudioIPCClientArguments.parseMethod(
                            global, descriptors: [discovery.commandListInvocation.descriptor],
                            correlationIDGenerator: { UUIDv7.generate() }, standardInputProvider: readInput)
                        try write(response.normalizedResult)
                        return
                    }
                    commandCatalog = commands
                    descriptors = [commands.executeDescriptor]
                } else {
                    descriptors = try IPCBuiltInMethodCatalog.matchingDiscoveredMethods(catalog, examples: examples)
                }
            }
            var invocation = try AgentStudioIPCClientArguments.parseMethod(
                global, descriptors: descriptors, correlationIDGenerator: { UUIDv7.generate() },
                standardInputProvider: readInput
            ).descriptorInvocation
            if let commandCatalog {
                let request = try JSONDecoder().decode(
                    IPCCommandExecutionRequest.self, from: invocation.normalizedParameters)
                invocation = try commandCatalog.makeInvocation(
                    commandId: request.commandId, correlationId: request.correlationId, arguments: request.arguments)
            }
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
                    if let commandCatalog {
                        _ = try commandCatalog.decodeResult(response.normalizedResult, for: invocation)
                    }
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
