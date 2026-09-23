/// The command line, parsed once. An unknown option is an error rather than a
/// silently ignored word, so a mistyped flag cannot turn a check off.
struct ArchitectureLintArguments: Equatable {
    enum Mode: Equatable {
        case help
        case printRules
        case lint
    }

    var mode: Mode = .lint
    /// Files and directories to parse. Empty means `Sources` and `Tests`.
    var roots: [String] = []
    /// When non-empty, only these files are validated; every root is still
    /// parsed so cross-file indexes match a full run.
    var onlyPaths: [String] = []
    var printsTimings = false

    static func parse(_ arguments: [String]) throws -> Self {
        var parsed = Self()
        var remaining = arguments[...]
        while let argument = remaining.popFirst() {
            switch argument {
            case "--help":
                parsed.mode = .help
            case "--print-rules":
                parsed.mode = .printRules
            case "--timings":
                parsed.printsTimings = true
            case "--only":
                parsed.onlyPaths.append(try value(for: argument, from: &remaining))
            default:
                guard !argument.hasPrefix("-") else {
                    throw ArchitectureLintArgumentsError.unknownOption(argument)
                }
                parsed.roots.append(argument)
            }
        }
        return parsed
    }

    private static func value(for option: String, from remaining: inout ArraySlice<String>) throws -> String {
        guard let value = remaining.popFirst(), !value.hasPrefix("-") else {
            throw ArchitectureLintArgumentsError.missingValue(option)
        }
        return value
    }
}

enum ArchitectureLintArgumentsError: Error, CustomStringConvertible {
    case unknownOption(String)
    case missingValue(String)

    var description: String {
        switch self {
        case .unknownOption(let option):
            "unknown option \(option)"
        case .missingValue(let option):
            "\(option) needs a value"
        }
    }
}
