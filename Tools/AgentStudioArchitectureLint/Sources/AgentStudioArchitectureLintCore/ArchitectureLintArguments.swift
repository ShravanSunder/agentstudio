/// The command line, parsed once. An unknown option is an error rather than a
/// silently ignored word, so a mistyped flag cannot turn a check off.
struct ArchitectureLintArguments: Equatable {
    enum Mode: Equatable {
        case help
        case printRules
        case lint
        /// Compare `--ledger` with a ledger read from the merge base.
        case checkLedgerRatchet(basePath: String)

        var readsLedger: Bool {
            guard case .checkLedgerRatchet = self else {
                return false
            }
            return true
        }
    }

    var mode: Mode = .lint
    /// Files and directories to parse. Empty means `Sources` and `Tests`.
    var roots: [String] = []
    /// When non-empty, only these files are validated; every root is still
    /// parsed so cross-file indexes match a full run.
    var onlyPaths: [String] = []
    var printsTimings = false
    /// The debt ledger to reconcile against. Without it every site is new.
    var ledgerPath: String?
    /// Rewrite the ledger with the counts this run found, lowering only.
    var lowersLedgerCounts = false

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
            case "--ledger":
                parsed.ledgerPath = try value(for: argument, from: &remaining)
            case "--lower-ledger-counts":
                parsed.lowersLedgerCounts = true
            case "--check-ledger-ratchet":
                parsed.mode = .checkLedgerRatchet(basePath: try value(for: argument, from: &remaining))
            default:
                guard !argument.hasPrefix("-") else {
                    throw ArchitectureLintArgumentsError.unknownOption(argument)
                }
                parsed.roots.append(argument)
            }
        }
        if parsed.ledgerPath == nil, parsed.lowersLedgerCounts || parsed.mode.readsLedger {
            throw ArchitectureLintArgumentsError.requiresLedger
        }
        if parsed.lowersLedgerCounts, !parsed.onlyPaths.isEmpty {
            throw ArchitectureLintArgumentsError.lowerLedgerCountsNeedsFullRun
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
    case requiresLedger
    case lowerLedgerCountsNeedsFullRun

    var description: String {
        switch self {
        case .unknownOption(let option):
            "unknown option \(option)"
        case .missingValue(let option):
            "\(option) needs a value"
        case .requiresLedger:
            "--lower-ledger-counts and --check-ledger-ratchet need --ledger <file>"
        case .lowerLedgerCountsNeedsFullRun:
            "--lower-ledger-counts needs a full run; it cannot be combined with --only"
        }
    }
}
