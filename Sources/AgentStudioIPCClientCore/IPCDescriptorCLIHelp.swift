import AgentStudioPrimitives
import AgentStudioProgrammaticControl
import Foundation

/// Help projects compiled contracts before endpoint or credential resolution.
/// Live command identities are rendered only from an explicit discovery.
enum IPCDescriptorCLIHelp {
    static func localHelp(
        arguments: [String], index: IPCBuiltInMethodIndex, inputs: IPCBuiltInMethodCatalogInputs? = nil
    ) throws -> String? {
        if arguments == ["--help"] || arguments == ["help"] {
            return overview(index: index)
        }
        if arguments.count == 2, arguments[0] == "help", arguments[1] != "--live" {
            return try methodHelp(named: arguments[1], index: index, inputs: inputs)
        }
        if arguments.count == 2, arguments[1] == "--help" {
            return try methodHelp(named: arguments[0], index: index, inputs: inputs)
        }
        return nil
    }

    static func overview(index: IPCBuiltInMethodIndex) -> String {
        let methods = index.entries.map {
            "  \($0.name) — \($0.summary)  [agent: \(agentLabel($0.agentEligibility))]"
        }
        return
            ([
                "Usage: agentstudio [--socket PATH | --metadata PATH] [--token-stdin] [--reload-catalog] METHOD [OPTIONS]",
                "       agentstudio METHOD --help",
                "       agentstudio help [--live]",
                "Methods:",
            ] + methods + [
                "Method help: agentstudio <method> --help",
                "Live commands: agentstudio help --live",
                "Use --json '{...}' or --stdin for a JSON parameter object.",
            ]).joined(separator: "\n")
    }

    static func liveCommands(_ commands: [IPCCommandDescriptor]) -> String {
        (["Live commands:"]
            + commands.sorted { $0.id.rawValue < $1.id.rawValue }.map {
                "  \($0.id.rawValue) — \($0.title): \($0.description)"
            }).joined(separator: "\n")
    }

    private static func agentLabel(_ eligibility: IPCAgentEligibility?) -> String {
        switch eligibility {
        // Legacy nil methods retain the existing self-pane privilege baseline.
        case .ownPane, nil: "own pane"
        case .anyTarget: "read-only"
        case .notYetAllowed: "not yet allowed"
        }
    }

    private static func methodHelp(
        named name: String, index: IPCBuiltInMethodIndex, inputs: IPCBuiltInMethodCatalogInputs?
    ) throws -> String {
        guard let entry = index.entry(named: name) else {
            throw IPCDescriptorInvocationError.unknownMethod(named: name, index: index)
        }
        var lines = [
            "\(entry.name) — \(entry.summary)",
            "Usage: agentstudio \(entry.name) [OPTIONS | --json '{...}' | --stdin]",
        ]
        if case .object(let fields) = try entry.parameterSchema(), !fields.isEmpty {
            lines.append("Parameters:")
            for field in fields {
                let presence = field.presence == .required ? "required" : "optional"
                lines.append(
                    "  \(IPCDescriptorInvocationParser.toolingOptionName(for: field.name)) <value> (\(field.name), \(presence)) — \(field.description)"
                )
            }
        }
        for modelCall in entry.modelCalls {
            lines.append("Model invocation: agentstudio \(modelCall.variant.rawValue)")
        }
        if entry.correlationPolicy == .required {
            lines.append(
                "correlationId is generated when omitted and preserved when supplied, including JSON and stdin.")
        }
        lines.append("Use JSON or stdin for object and array parameters.")
        let exampleInputs = inputs ?? .init(examples: .init(illustrativeIdentifier: UUIDv7.generate()))
        let descriptor = try entry.makeRepresentation(inputs: exampleInputs).erasedDescriptor
        if let example = descriptor.metadata.examples.first {
            guard let parameterText = String(bytes: try example.encodedParameters(), encoding: .utf8) else {
                return lines.joined(separator: "\n")
            }
            let escapedParameterText = parameterText.replacingOccurrences(of: "'", with: "'\\''")
            lines.append("Example: agentstudio \(entry.name) --json '\(escapedParameterText)'")
        }
        return lines.joined(separator: "\n")
    }
}
