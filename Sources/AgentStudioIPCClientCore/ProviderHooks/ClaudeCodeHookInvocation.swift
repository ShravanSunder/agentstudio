import AgentStudioProgrammaticControl
import Foundation

/// Everything one `agentstudio hook claude <Event>` invocation needs from its
/// process, named so tests drive it without a process.
package struct ClaudeCodeHookInvocationInputs {
    package let arguments: [String]
    package let environment: [String: String]
    package let standardInput: () throws -> Data
    package let identifierGenerator: () -> UUID
    package let diagnosticSink: (String) -> Void

    package init(
        arguments: [String],
        environment: [String: String],
        standardInput: @escaping () throws -> Data,
        identifierGenerator: @escaping () -> UUID,
        diagnosticSink: @escaping (String) -> Void
    ) {
        self.arguments = arguments
        self.environment = environment
        self.standardInput = standardInput
        self.identifierGenerator = identifierGenerator
        self.diagnosticSink = diagnosticSink
    }
}

/// Runs one Claude Code hook: read the hook document from stdin, project it,
/// and submit it as `session.event` over the pane's authenticated connection.
///
/// The hook is a bystander in Claude Code's turn. It always exits 0 and always
/// leaves stdout empty, because Claude Code parses hook stdout as a decision
/// document and treats a non-zero exit as a hook failure the user sees. Every
/// refusal, missing credential and transport failure is therefore a silent
/// success here, at most one line on stderr and never any payload content.
package enum ClaudeCodeHookInvocation {
    package static let commandPrefix = ["hook", "claude"]

    /// - Returns: the process exit code when `arguments` address this command,
    ///   and `nil` when they belong to another command.
    package static func handle(_ inputs: ClaudeCodeHookInvocationInputs) -> Int32? {
        guard Array(inputs.arguments.prefix(commandPrefix.count)) == commandPrefix else {
            return nil
        }
        let remainder = Array(inputs.arguments.dropFirst(commandPrefix.count))
        guard let announcedEvent = remainder.first, !announcedEvent.hasPrefix("--") else {
            inputs.diagnosticSink("agentstudio hook claude: missing hook event name")
            return 0
        }
        let providerVersion =
            parsedProviderVersion(Array(remainder.dropFirst())) ?? ClaudeCodeProviderIdentity.supportedExactVersion
        guard let executablePath = inputs.environment["AGENTSTUDIO_CLI"], !executablePath.isEmpty,
            inputs.environment["AGENTSTUDIO_PANE_TOKEN"].map({ !$0.isEmpty }) == true
        else {
            return 0
        }
        submit(announcedEvent: announcedEvent, providerVersion: providerVersion, inputs: inputs)
        return 0
    }

    private static func submit(
        announcedEvent: String,
        providerVersion: String,
        inputs: ClaudeCodeHookInvocationInputs
    ) {
        do {
            let payload = try JSONDecoder().decode(
                ClaudeCodeHookPayload.self, from: try inputs.standardInput()
            )
            let outcome = ClaudeCodeHookProjection.project(
                announcedEvent: announcedEvent,
                payload: payload,
                providerVersion: providerVersion,
                correlationIdentifier: inputs.identifierGenerator(),
                freshOccurrenceIdentifier: inputs.identifierGenerator
            )
            guard case .projected(let params) = outcome else { return }
            try send(params: params, environment: inputs.environment)
        } catch {
            inputs.diagnosticSink("agentstudio hook claude: \(announcedEvent) not reported")
        }
    }

    private static func send(params: IPCSessionEventParams, environment: [String: String]) throws {
        let configuration = AgentStudioIPCClientConfiguration(
            socketPath: try AgentStudioIPCClientDiscovery.socketPath(
                explicitSocketPath: nil, environment: environment, metadataURL: nil
            ),
            authToken: environment["AGENTSTUDIO_PANE_TOKEN"]
        )
        let examples = IPCBuiltInMethodExampleContext(illustrativeIdentifier: params.correlationId)
        let bootstrap = try IPCBuiltInMethodCatalog.bootstrapDescriptors(examples: examples)
        // A hook fires several times a turn under a short provider timeout, so
        // it resolves session.event from its own compiled contract rather than
        // fetching the whole catalog first.
        let descriptors = try IPCBuiltInMethodCatalog.locallyResolvableDescriptors(examples: examples)
        guard let descriptor = descriptors.first(where: { $0.metadata.name == "session.event" }) else {
            throw ClaudeCodeHookInvocationError.sessionEventUnavailable
        }
        let client = AgentStudioIPCClient(
            configuration: configuration, descriptors: bootstrap + [descriptor]
        )
        let result = try client.call(
            IPCDescriptorInvocation(
                descriptor: descriptor,
                normalizedParameters: try descriptor.normalizeParameters(JSONEncoder().encode(params)),
                presentation: .tooling
            )
        )
        guard case .success = result else { throw ClaudeCodeHookInvocationError.reportRejected }
    }

    private static func parsedProviderVersion(_ arguments: [String]) -> String? {
        guard let flagIndex = arguments.firstIndex(of: "--provider-version"),
            case let valueIndex = arguments.index(after: flagIndex),
            valueIndex < arguments.count
        else {
            return nil
        }
        let value = arguments[valueIndex]
        return value.isEmpty ? nil : value
    }
}

package enum ClaudeCodeHookInvocationError: Error, Equatable, Sendable {
    case sessionEventUnavailable
    case reportRejected
}
