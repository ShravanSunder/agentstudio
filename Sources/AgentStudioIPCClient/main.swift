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
                    let response: IPCDescriptorClientResponse
                    switch try listClient.call(discovery.commandListInvocation) {
                    case .success(let successfulResponse):
                        response = successfulResponse
                    case .remoteFailure(let failure):
                        throw CLIExit.structured(CLIErrorPresentation(remoteFailure: failure))
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
                    case .remoteFailure(let failure):
                        throw CLIExit.structured(CLIErrorPresentation(remoteFailure: failure))
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
                case .remoteFailure(let failure):
                    throw CLIExit.structured(CLIErrorPresentation(remoteFailure: failure))
                }
            }
        } catch {
            handleFailure(error)
        }
    }

    private static func handleFailure(_ error: Error) -> Never {
        switch error {
        case let failure as IPCCommandDiscoveryError:
            writeStructuredError(CLIErrorPresentation(commandDiscoveryFailure: failure))
        case let failure as IPCDescriptorInvocationError:
            writeStructuredError(CLIErrorPresentation(invocationFailure: failure))
        case let correction as IPCSchemaValidationError:
            writeStructuredError(CLIErrorPresentation(schemaCorrection: correction))
        case let failure as IPCDescriptorRemoteFailure:
            writeStructuredError(CLIErrorPresentation(remoteFailure: failure))
        case let failure as AgentStudioIPCClientError where failure.reason == .invalidArguments:
            writeStructuredError(.localInvalidArguments)
        case let failure as IPCDescriptorClientFailure where failure.disposition == .deliveryUncertain:
            fputs("Delivery uncertain.\n", stderr)
        case let failure as IPCDescriptorClientFailure:
            if case .unsupportedVersion(let correction) = failure.reason {
                writeStructuredError(CLIErrorPresentation(unsupportedVersion: correction))
            } else {
                writeUnavailableError()
            }
        case let error as CLIExit:
            if case .structured(let presentation) = error {
                writeStructuredError(presentation)
            } else {
                writeUnavailableError()
            }
        default:
            writeUnavailableError()
        }
        exit(1)
    }

    private static func writeUnavailableError() {
        fputs("Agent Studio request rejected or unavailable.\n", stderr)
    }

    private static func write(_ data: Data) throws {
        guard let output = String(data: data, encoding: .utf8) else { throw CLIExit.rejected }
        print(output)
    }

    private static func writeStructuredError(_ error: CLIErrorPresentation) {
        guard let encoded = try? JSONEncoder().encode(error),
            let output = String(data: encoded, encoding: .utf8)
        else {
            fputs("Agent Studio request rejected or unavailable.\n", stderr)
            return
        }
        fputs("\(output)\n", stderr)
    }
}

private enum CLIExit: Error {
    case rejected
    case structured(CLIErrorPresentation)
}

private struct CLIErrorPresentation: Codable {
    let reason: String
    let fieldPath: String?
    let expected: String?
    let catalogMethod: String?
    let requiredScope: IPCPermissionScope?

    init(commandDiscoveryFailure: IPCCommandDiscoveryError) {
        switch commandDiscoveryFailure.reason {
        case .unknownCommandIdentifier:
            reason = "unknownCommand"
            fieldPath = commandDiscoveryFailure.fieldPath
            expected = commandDiscoveryFailure.expected
            catalogMethod = "command.list"
        case .argumentVariantNotAllowed:
            reason = "invalidParams"
            fieldPath = commandDiscoveryFailure.fieldPath
            expected = commandDiscoveryFailure.expected
            catalogMethod = "command.list"
        default:
            reason = "invalidParams"
            fieldPath = nil
            expected = nil
            catalogMethod = nil
        }
        requiredScope = nil
    }

    init(remoteFailure: IPCDescriptorRemoteFailure) {
        if let requiredScope = remoteFailure.requiredScope {
            reason = "missingGrant"
            fieldPath = "$.authorization"
            expected = nil
            catalogMethod = nil
            self.requiredScope = requiredScope
            return
        }
        if let correction = remoteFailure.correction {
            reason = "invalidParams"
            fieldPath = correction.fieldPath
            expected = correction.expected
            catalogMethod = nil
            requiredScope = nil
            return
        }
        reason = remoteFailure.documentedReason ?? "requestRejected"
        fieldPath = Self.knownFieldPath(for: reason)
        expected = nil
        catalogMethod = nil
        requiredScope = nil
    }

    init(invocationFailure: IPCDescriptorInvocationError) {
        if invocationFailure.reason == .unknownMethod {
            reason = "unknownMethod"
            fieldPath = "$.method"
            expected = "a method advertised by system.capabilities"
            catalogMethod = "system.capabilities"
        } else {
            reason = "invalidParams"
            fieldPath = invocationFailure.fieldPath
            expected = invocationFailure.expected
            catalogMethod = nil
        }
        requiredScope = nil
    }

    init(schemaCorrection: IPCSchemaValidationError) {
        reason = "invalidParams"
        fieldPath = schemaCorrection.fieldPath
        expected = schemaCorrection.expected
        catalogMethod = nil
        requiredScope = nil
    }

    init(unsupportedVersion correction: IPCSchemaValidationError) {
        reason = "unsupportedVersion"
        fieldPath = Self.safeFieldPath(correction.fieldPath)
        expected = correction.expected
        catalogMethod = nil
        requiredScope = nil
    }

    static let localInvalidArguments = Self(
        reason: "invalidParams", fieldPath: "$", expected: "valid CLI arguments",
        catalogMethod: nil, requiredScope: nil
    )

    private init(
        reason: String, fieldPath: String?, expected: String?, catalogMethod: String?,
        requiredScope: IPCPermissionScope?
    ) {
        self.reason = reason
        self.fieldPath = fieldPath
        self.expected = expected
        self.catalogMethod = catalogMethod
        self.requiredScope = requiredScope
    }

    private static func knownFieldPath(for reason: String) -> String? {
        switch reason {
        case "stateUnavailable", "unknownCommand", "unsupportedCommand": "$.commandId"
        case "missingGrant": "$.authorization"
        default: nil
        }
    }

    private static func safeFieldPath(_ fieldPath: String?) -> String? {
        guard let fieldPath,
            ["$.arguments.kind", "$.authorization", "$.commandId", "$.compatibility"].contains(fieldPath)
        else {
            return nil
        }
        return fieldPath
    }
}
