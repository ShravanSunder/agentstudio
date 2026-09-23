import Foundation

public struct ArchitectureLintCommand {
    private let fileManager: FileManager
    private let standardOutput: FileHandle
    private let standardError: FileHandle
    private let rules: [any ArchitectureRule]
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
        workspaceRootPath: String = FileManager.default.currentDirectoryPath
    ) {
        self.fileManager = fileManager
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.rules = rules
        self.workspaceRootPath = workspaceRootPath
    }

    public func run(arguments: [String]) -> Int32 {
        let parsedArguments: ArchitectureLintArguments
        do {
            parsedArguments = try ArchitectureLintArguments.parse(arguments)
        } catch {
            writeError("agentstudio-architecture-lint: \(error)\n")
            return 2
        }

        switch parsedArguments.mode {
        case .help:
            writeOutput(helpText)
            return 0
        case .printRules:
            for rule in rules.sorted(by: { $0.id < $1.id }) {
                writeOutput("\(rule.id) \(rule.severity.rawValue)\n")
            }
            return 0
        case .lint:
            break
        }

        let requestedRoots = parsedArguments.roots.isEmpty ? ["Sources", "Tests"] : parsedArguments.roots
        do {
            let discovery = SourceFileDiscovery(fileManager: fileManager)
            let onlyFiles = try discovery.swiftFiles(under: parsedArguments.onlyPaths.map(workspacePath))
            let rootFiles = try discovery.swiftFiles(under: requestedRoots.map(workspacePath))
            let rootFileSet = Set(rootFiles)
            let files = rootFiles + onlyFiles.filter { !rootFileSet.contains($0) }
            let run = try ArchitectureLintEngine(rules: rules, workspaceRootPath: workspaceRootPath)
                .lint(
                    files: files,
                    validatedFiles: parsedArguments.onlyPaths.isEmpty ? nil : Set(onlyFiles)
                )
            for diagnostic in run.diagnostics {
                writeOutput(diagnostic.rendered)
            }
            if parsedArguments.printsTimings {
                writeOutput(run.timings.renderedLines)
            }
            return run.diagnostics.contains { $0.severity.affectsExitCode } ? 1 : 0
        } catch {
            writeError("agentstudio-architecture-lint: \(error)\n")
            return 2
        }
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
          agentstudio-architecture-lint [--print-rules] [--timings] [--only file]... [paths...]

        Defaults to linting Sources and Tests when no paths are provided.
        --only validates just the named files; every path is still parsed so
        cross-file rules see the whole corpus.
        --timings prints per-stage and per-rule times; they never change the exit code.
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
