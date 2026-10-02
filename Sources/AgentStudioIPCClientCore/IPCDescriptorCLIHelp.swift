import AgentStudioProgrammaticControl

/// Help projects compiled contracts before endpoint or credential resolution.
/// Live command identities are rendered only from an explicit discovery.
enum IPCDescriptorCLIHelp {
    static func localHelp(arguments: [String], index: IPCBuiltInMethodIndex) throws -> String? {
        if arguments == ["--help"] || arguments == ["help"] {
            return overview(index: index)
        }
        if arguments.count == 2, arguments[0] == "help", arguments[1] != "--live" {
            return try methodHelp(named: arguments[1], index: index)
        }
        if arguments.count == 2, arguments[1] == "--help" {
            return try methodHelp(named: arguments[0], index: index)
        }
        return nil
    }

    static func overview(index: IPCBuiltInMethodIndex) -> String {
        let methods = index.entries.map {
            "  \($0.name) — \($0.summary)"
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

    private static func methodHelp(named name: String, index: IPCBuiltInMethodIndex) throws -> String {
        guard let entry = index.entry(named: name) else {
            throw IPCDescriptorInvocationError(
                reason: .unknownMethod, fieldPath: "$.method", expected: "a compiled method name")
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
        return lines.joined(separator: "\n")
    }
}
