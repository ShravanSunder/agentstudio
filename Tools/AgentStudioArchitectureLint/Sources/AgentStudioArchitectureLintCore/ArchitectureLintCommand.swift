import Foundation
import SwiftParser

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
        if arguments.contains("--help") {
            writeOutput(helpText)
            return 0
        }
        if arguments.contains("--print-rules") {
            for rule in rules.sorted(by: { $0.id < $1.id }) {
                writeOutput("\(rule.id) \(rule.severity.rawValue)\n")
            }
            return 0
        }

        let roots = arguments.filter { !$0.hasPrefix("-") }
        let discoveryRoots = roots.isEmpty ? ["Sources", "Tests"] : roots

        do {
            let files = try SourceFileDiscovery(fileManager: fileManager)
                .swiftFiles(under: discoveryRoots)
            let diagnostics = try lint(files: files)
            for diagnostic in diagnostics.sorted() {
                writeOutput(diagnostic.rendered)
            }
            return diagnostics.isEmpty ? 0 : 1
        } catch {
            writeError("agentstudio-architecture-lint: \(error)\n")
            return 2
        }
    }

    private func lint(files: [String]) throws -> [ArchitectureDiagnostic] {
        var seenSourceIdentities: Set<String> = []
        let contexts = try files.compactMap { file -> ArchitectureLintContext? in
            let source = try String(contentsOfFile: file, encoding: .utf8)
            let sourceFile = Parser.parse(source: source)
            let context = ArchitectureLintContext(
                path: file,
                source: source,
                sourceFile: sourceFile,
                workspaceRootPath: workspaceRootPath
            )
            guard seenSourceIdentities.insert(context.syntaxScopeSourceIdentity).inserted else {
                return nil
            }
            return context
        }

        var diagnostics: [ArchitectureDiagnostic] = []
        for rule in rules {
            let preparedRule = rule.prepared(for: contexts)
            for context in contexts {
                diagnostics.append(contentsOf: preparedRule.validate(context: context))
            }
        }
        return diagnostics
    }

    private var helpText: String {
        """
        Usage:
          agentstudio-architecture-lint [--print-rules] [paths...]

        Defaults to linting Sources and Tests when no paths are provided.
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
