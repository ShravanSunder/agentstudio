import AgentStudioIPCClientCore
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation

@main
struct AgentStudioIPCClientMain {
    static func main() {
        do {
            let readInput: @Sendable () -> Data = { FileHandle.standardInput.readDataToEndOfFile() }
            let environment = ProcessInfo.processInfo.environment
            let rawArguments = Array(CommandLine.arguments.dropFirst())
            if let code = providerCommandExit(
                arguments: rawArguments, environment: environment, readInput: readInput
            ) {
                exit(code)
            }
            let global = try AgentStudioIPCClientArguments.parseGlobal(
                rawArguments, environment: environment,
                standardInputProvider: readInput
            )
            let offlineHandler = PaneNotificationOfflineHandler(environment: environment)
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
                let catalog: IPCMethodCatalogResult
                do {
                    catalog = try discoveryClient.discoverCatalog()
                } catch let unreachable as IPCDescriptorClientFailure where unreachable.permitsOfflineQueue {
                    try queueNotificationWhileOffline(
                        global: global, examples: examples, handler: offlineHandler,
                        standardInputProvider: readInput, unreachable: unreachable
                    )
                    return
                }
                if global.methodArguments.first == "command.list" || global.methodArguments.first == "command.execute" {
                    switch try resolveDiscoveredCommandDescriptors(
                        global: global, bootstrap: bootstrap, catalog: catalog,
                        standardInputProvider: readInput
                    ) {
                    case .completed:
                        return
                    case .resolved(let resolvedDescriptors, let resolvedCatalog):
                        descriptors = resolvedDescriptors
                        commandCatalog = resolvedCatalog
                    }
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
                let result: IPCDescriptorClientCallResult
                do {
                    result = try client.call(invocation)
                } catch let unreachable as IPCDescriptorClientFailure where unreachable.permitsOfflineQueue {
                    try queueWhileOffline(
                        invocation: invocation, handler: offlineHandler,
                        requestLine: { try client.requestFrame(invocation) }, unreachable: unreachable
                    )
                    return
                }
                switch result {
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
                    throw modelFailureExit(failure, invocation: invocation)
                }
            }
        } catch {
            handleFailure(error)
        }
    }

    /// A refused model call answers in the same one-line register it asked in.
    /// Tooling callers and `--detail` keep the structured envelope.
    private static func modelFailureExit(
        _ failure: IPCDescriptorRemoteFailure,
        invocation: IPCDescriptorInvocation
    ) -> CLIExit {
        guard case .model(let presentation) = invocation.presentation,
            !presentation.showsDetail,
            let reply = IPCModelInvocationFailureReply.line(forDocumentedReason: failure.documentedReason)
        else {
            return .structured(CLIErrorPresentation(remoteFailure: failure))
        }
        return .modelReply(reply)
    }

    /// `command.list` answers from the discovery response itself, so it finishes
    /// here rather than continuing to a second call.
    private static func resolveDiscoveredCommandDescriptors(
        global: IPCClientGlobalArguments,
        bootstrap: [IPCAnyMethodDescriptor],
        catalog: IPCMethodCatalogResult,
        standardInputProvider: () throws -> Data
    ) throws -> DiscoveredCommandDescriptors {
        let discovery = try IPCCommandDiscovery(methodCatalog: catalog)
        let authenticationDescriptors = bootstrap.filter { $0.metadata.name == "auth.login" }
        guard authenticationDescriptors.count == 1 else { throw CLIExit.rejected }
        let listClient = AgentStudioIPCClient(
            configuration: global.configuration,
            descriptors: authenticationDescriptors + [discovery.commandListInvocation.descriptor]
        )
        let response: IPCDescriptorClientResponse
        switch try listClient.call(discovery.commandListInvocation) {
        case .success(let successfulResponse):
            response = successfulResponse
        case .remoteFailure(let failure):
            throw CLIExit.structured(CLIErrorPresentation(remoteFailure: failure))
        }
        let commands = try discovery.decodeCommandCatalog(from: response.normalizedResult)
        guard global.methodArguments.first != "command.list" else {
            _ = try AgentStudioIPCClientArguments.parseMethod(
                global, descriptors: [discovery.commandListInvocation.descriptor],
                correlationIDGenerator: { UUIDv7.generate() }, standardInputProvider: standardInputProvider)
            try write(response.normalizedResult)
            return .completed
        }
        return .resolved(
            authenticationDescriptors + [commands.executeDescriptor], commandCatalog: commands)
    }

    /// Discovery never reached the app, so the notification is classified from
    /// the compiled descriptors. Anything that is not an eligible model
    /// notification keeps the original unreachable failure.
    private static func queueNotificationWhileOffline(
        global: IPCClientGlobalArguments,
        examples: IPCBuiltInMethodExampleContext,
        handler: PaneNotificationOfflineHandler,
        standardInputProvider: () throws -> Data,
        unreachable: IPCDescriptorClientFailure
    ) throws {
        let descriptors = try IPCBuiltInMethodCatalog.offlineNotificationDescriptors(examples: examples)
        guard
            let invocation = try? AgentStudioIPCClientArguments.parseMethod(
                global, descriptors: descriptors, correlationIDGenerator: { UUIDv7.generate() },
                standardInputProvider: standardInputProvider
            ).descriptorInvocation
        else {
            throw unreachable
        }
        let client = AgentStudioIPCClient(configuration: global.configuration, descriptors: descriptors)
        try queueWhileOffline(
            invocation: invocation, handler: handler,
            requestLine: { try client.requestFrame(invocation) }, unreachable: unreachable
        )
    }

    private static func queueWhileOffline(
        invocation: IPCDescriptorInvocation,
        handler: PaneNotificationOfflineHandler,
        requestLine: () throws -> String,
        unreachable: IPCDescriptorClientFailure
    ) throws {
        switch try handler.handleUnreachableApp(invocation: invocation, requestLine: requestLine) {
        case .queued(let reply):
            print(reply)
        case .clearUnavailableWhileOffline:
            throw CLIExit.message("Can't clear while Agent Studio is offline.")
        case .notQueued:
            throw unreachable
        }
    }

    /// Provider hooks and the package installer are not IPC methods, so they
    /// are dispatched before descriptor parsing: one runs as the provider's own
    /// child process and the other edits the provider's configuration on disk.
    ///
    /// Claude Code's router is asked first. The provider-keyed parser matches
    /// `hook <provider> <event>` and `package install <provider>` for every
    /// provider name, so running it first would answer a Claude Code invocation
    /// with "unknown provider" instead of letting Claude Code's own path run.
    ///
    /// - Returns: the process exit code when the arguments address a provider
    ///   command, and `nil` when they belong to the descriptor CLI.
    private static func providerCommandExit(
        arguments: [String],
        environment: [String: String],
        readInput: @escaping @Sendable () -> Data
    ) -> Int32? {
        if let code = ClaudeCodeProviderRouter.exitCode(
            arguments: arguments, environment: environment,
            executablePath: CommandLine.arguments[0], standardInput: readInput,
            identifierGenerator: { UUIDv7.generate() }
        ) {
            return code
        }
        guard let subcommand = AgentPackageSubcommand.parse(arguments) else { return nil }
        return AgentPackageCommandRunner.run(subcommand, props: agentPackageProps(readInput: readInput))
    }

    private static func agentPackageProps(
        readInput: @escaping @Sendable () -> Data
    ) -> AgentPackageCommandRunner.Props {
        AgentPackageCommandRunner.Props(
            environment: ProcessInfo.processInfo.environment,
            executableURL: Bundle.main.executableURL,
            standardInput: readInput,
            correlationIdProvider: { UUIDv7.generate() },
            exampleIdentifierProvider: { UUIDv7.generate() },
            standardOutputSink: { print($0) },
            standardErrorSink: { fputs("\($0)\n", stderr) }
        )
    }

    private static func handleFailure(_ error: Error) -> Never {
        switch error {
        case let failure as PaneNotificationSpoolWriteError:
            fputs("Agent Studio could not durably queue this notification: \(failure.reason.rawValue)\n", stderr)
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
        case let failure as AgentStudioIPCClientError where failure.reason == .debugAppNotRunning:
            fputs("Debug app not running; start it with the debug launcher.\n", stderr)
        case let failure as IPCDescriptorClientFailure where failure.disposition == .deliveryUncertain:
            fputs("Delivery uncertain.\n", stderr)
        case let failure as IPCDescriptorClientFailure:
            if case .unsupportedVersion(let correction) = failure.reason {
                writeStructuredError(CLIErrorPresentation(unsupportedVersion: correction))
            } else {
                writeUnavailableError()
            }
        case let error as CLIExit:
            switch error {
            case .structured(let presentation): writeStructuredError(presentation)
            case .modelReply(let reply): fputs("\(reply)\n", stderr)
            case .message(let message): fputs("\(message)\n", stderr)
            case .rejected: writeUnavailableError()
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

private enum DiscoveredCommandDescriptors {
    case completed
    case resolved([IPCAnyMethodDescriptor], commandCatalog: IPCDiscoveredCommandCatalog)
}

private enum CLIExit: Error {
    case rejected
    case message(String)
    case structured(CLIErrorPresentation)
    case modelReply(String)
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
