import Darwin
import Foundation

public struct ArchitectureLintCommand {
    private let fileManager: FileManager
    private let standardOutput: FileHandle
    private let standardError: FileHandle
    private let rules: [any ArchitectureRule]
    private let documentRules: [any ArchitectureDocumentRule]
    private let workspaceRootPath: String

    public init(
        fileManager: FileManager,
        standardOutput: FileHandle,
        standardError: FileHandle
    ) {
        self.init(
            fileManager: fileManager,
            standardOutput: standardOutput,
            standardError: standardError,
            rules: ArchitectureRuleRegistry.rules,
            workspaceRootPath: FileManager.default.currentDirectoryPath
        )
    }

    init(
        fileManager: FileManager,
        standardOutput: FileHandle,
        standardError: FileHandle,
        rules: [any ArchitectureRule],
        documentRules: [any ArchitectureDocumentRule] = ArchitectureRuleRegistry.documentRules,
        workspaceRootPath: String = FileManager.default.currentDirectoryPath
    ) {
        self.fileManager = fileManager
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.rules = rules
        self.documentRules = documentRules
        self.workspaceRootPath = Self.canonicalWorkspaceRootPath(workspaceRootPath)
    }

    private static func canonicalWorkspaceRootPath(_ path: String) -> String {
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        guard let resolvedPath = standardizedPath.withCString({ Darwin.realpath($0, nil) }) else {
            return standardizedPath
        }
        defer { Darwin.free(resolvedPath) }
        return String(cString: resolvedPath)
    }

    public func run(arguments: [String]) -> Int32 {
        let parsedArguments: ArchitectureLintArguments
        do {
            parsedArguments = try ArchitectureLintArguments.parse(arguments)
        } catch {
            writeError("agentstudio-architecture-lint: \(error)\n")
            return 2
        }

        do {
            switch parsedArguments.mode {
            case .help:
                writeOutput(helpText)
                return 0
            case .printRules:
                let inventory =
                    rules.map { ($0.id, $0.severity) } + documentRules.map { ($0.id, $0.severity) }
                for (id, severity) in inventory.sorted(by: { $0.0 < $1.0 }) {
                    writeOutput("\(id) \(severity.rawValue)\n")
                }
                return 0
            case .checkLedgerRatchet(let basePath):
                return try checkLedgerRatchet(arguments: parsedArguments, basePath: basePath)
            case .lint:
                return try lint(arguments: parsedArguments)
            }
        } catch {
            writeError("agentstudio-architecture-lint: \(error)\n")
            return 2
        }
    }

    private func lint(arguments: ArchitectureLintArguments) throws -> Int32 {
        let requestedRoots = arguments.roots.isEmpty ? ["Sources", "Tests"] : arguments.roots
        let discovery = SourceFileDiscovery(fileManager: fileManager)
        let onlyFiles = try discovery.lintedFiles(under: arguments.onlyPaths.map(workspacePath))
        let rootFiles = try discovery.lintedFiles(under: requestedRoots.map(workspacePath))
        let rootFileSet = Set(rootFiles)
        let files = rootFiles + onlyFiles.filter { !rootFileSet.contains($0) }
        let run = try ArchitectureLintEngine(
            rules: rules,
            documentRules: documentRules,
            workspaceRootPath: workspaceRootPath
        )
        .lint(
            files: files,
            validatedFiles: arguments.onlyPaths.isEmpty ? nil : Set(onlyFiles)
        )

        var diagnostics = run.siteDiagnostics
        if let ledgerPath = arguments.ledgerPath {
            var ledger = try loadLedger(ledgerPath)
            var outcome = run.reconciled(with: ledger)
            if arguments.lowersLedgerCounts {
                let loweredLedger = run.reconciliation(with: ledger).lowered(observedCounts: outcome.observedCounts)
                if loweredLedger != ledger {
                    try loweredLedger.rendered.write(
                        toFile: workspacePath(ledgerPath),
                        atomically: true,
                        encoding: .utf8
                    )
                    writeOutput("agentstudio-architecture-lint: lowered counts in \(ledgerPath)\n")
                }
                ledger = loweredLedger
                outcome = run.reconciled(with: ledger)
            }
            diagnostics = outcome.diagnostics
        }

        for diagnostic in diagnostics {
            writeOutput(diagnostic.rendered)
        }
        if arguments.printsTimings {
            writeOutput(run.timings.renderedLines)
        }
        return diagnostics.isEmpty ? 0 : 1
    }

    /// A merge base without a ledger has nothing to ratchet against: the
    /// ledger is new in that change, and every row it adds is its baseline.
    private func checkLedgerRatchet(arguments: ArchitectureLintArguments, basePath: String) throws -> Int32 {
        guard let ledgerPath = arguments.ledgerPath else {
            throw ArchitectureLintArgumentsError.requiresLedger
        }
        let current = try loadLedger(ledgerPath)
        guard fileManager.fileExists(atPath: workspacePath(basePath)) else {
            writeOutput("agentstudio-architecture-lint: no debt ledger at the merge base; nothing to ratchet\n")
            return 0
        }
        let base = try ArchitectureDebtLedger.load(path: workspacePath(basePath), displayPath: basePath)
        let violations = DebtLedgerRatchet.violations(current: current, base: base)
        for violation in violations {
            writeOutput(violation.rendered)
        }
        return violations.isEmpty ? 0 : 1
    }

    private func loadLedger(_ ledgerPath: String) throws -> ArchitectureDebtLedger {
        try ArchitectureDebtLedger.load(path: workspacePath(ledgerPath), displayPath: ledgerPath)
    }

    /// A root or scoped path as an absolute, standardized path, so the same
    /// file named two ways is one file.
    private func workspacePath(_ path: String) -> String {
        guard !path.hasPrefix("/") else {
            return URL(fileURLWithPath: path).standardizedFileURL.path
        }
        return URL(
            fileURLWithPath: path,
            relativeTo: URL(fileURLWithPath: workspaceRootPath, isDirectory: true)
        ).standardizedFileURL.path
    }

    private var helpText: String {
        """
        Usage:
          agentstudio-architecture-lint [--timings] [--ledger file [--lower-ledger-counts]] [--only file]... [paths...]
          agentstudio-architecture-lint --ledger file --check-ledger-ratchet base-file
          agentstudio-architecture-lint --print-rules

        Defaults to linting Sources and Tests when no paths are provided.
        --only validates just the named files; every path is still parsed so
        cross-file rules see the whole corpus.
        --timings prints per-stage and per-rule times; they never change the exit code.
        --ledger reconciles violation sites with the debt ledger: a file may hold
        exactly its permitted count per rule. --lower-ledger-counts rewrites
        the ledger down to what this run found; it never raises a count.
        --check-ledger-ratchet fails when --ledger raises a count or adds a row
        compared with base-file (the ledger at the merge base).
        Diagnostics use path:line:column: severity: [rule] message.

        """
    }

    private func writeOutput(_ text: String) {
        if let data = text.data(using: .utf8) {
            standardOutput.write(data)
        }
    }

    private func writeError(_ text: String) {
        if let data = text.data(using: .utf8) {
            standardError.write(data)
        }
    }
}
