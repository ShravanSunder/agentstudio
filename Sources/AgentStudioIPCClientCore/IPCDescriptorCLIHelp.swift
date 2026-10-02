import AgentStudioProgrammaticControl

/// Help projects compiled contracts before endpoint or credential resolution.
/// Live command identities are rendered only from an explicit discovery.
enum IPCDescriptorCLIHelp {
    static func localHelp(arguments: [String], descriptors: [IPCAnyMethodDescriptor]) throws -> String? {
        if arguments == ["--help"] || arguments == ["help"] {
            return overview(descriptors: descriptors)
        }
        if arguments.count == 2, arguments[0] == "help", arguments[1] != "--live" {
            return try methodHelp(named: arguments[1], descriptors: descriptors)
        }
        if arguments.count == 2, arguments[1] == "--help" {
            return try methodHelp(named: arguments[0], descriptors: descriptors)
        }
        return nil
    }

    static func overview(descriptors: [IPCAnyMethodDescriptor]) -> String {
        let methods = descriptors.sorted { $0.metadata.name < $1.metadata.name }.map {
            "  \($0.metadata.name) — \($0.metadata.description)"
        }
        return
            ([
                "Usage: agentstudio [--socket PATH | --metadata PATH] [--token-stdin] [--reload-catalog] METHOD [OPTIONS]",
                "       agentstudio METHOD --help",
                "       agentstudio help [--live]",
                "Methods:",
            ] + methods + [
                "Discovery: agentstudio system.capabilities | agentstudio command.list",
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

    private static func methodHelp(named name: String, descriptors: [IPCAnyMethodDescriptor]) throws -> String {
        guard let descriptor = descriptors.first(where: { $0.metadata.name == name }) else {
            throw IPCDescriptorInvocationError(
                reason: .unknownMethod, fieldPath: "$.method", expected: "a compiled method name")
        }
        var lines = [
            "\(descriptor.metadata.name) — \(descriptor.metadata.description)",
            "Usage: agentstudio \(descriptor.metadata.name) [OPTIONS | --json '{...}' | --stdin]",
        ]
        if case .object(let fields) = descriptor.metadata.parameterSchema, !fields.isEmpty {
            lines.append("Parameters:")
            for field in fields {
                let presence = field.presence == .required ? "required" : "optional"
                lines.append(
                    "  \(IPCDescriptorInvocationParser.toolingOptionName(for: field.name)) <value> (\(field.name), \(presence)) — \(field.description)"
                )
            }
        }
        for modelCall in descriptor.metadata.modelCalls {
            lines.append("Model invocation: agentstudio \(modelCall.variant.rawValue)")
        }
        if descriptor.metadata.correlationPolicy == .required {
            lines.append(
                "correlationId is generated when omitted and preserved when supplied, including JSON and stdin.")
        }
        lines.append("Use JSON or stdin for object and array parameters.")
        return lines.joined(separator: "\n")
    }
}
