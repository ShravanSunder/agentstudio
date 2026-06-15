import Foundation
import SwiftParser

public struct ArchitectureLintCommand {
    private let fileManager: FileManager
    private let standardOutput: FileHandle
    private let standardError: FileHandle
    private let rules: [any ArchitectureRule]

    public init(
        fileManager: FileManager,
        standardOutput: FileHandle,
        standardError: FileHandle
    ) {
        self.init(
            fileManager: fileManager,
            standardOutput: standardOutput,
            standardError: standardError,
            rules: ArchitectureRuleRegistry.rules
        )
    }

    init(
        fileManager: FileManager,
        standardOutput: FileHandle,
        standardError: FileHandle,
        rules: [any ArchitectureRule]
    ) {
        self.fileManager = fileManager
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.rules = rules
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
        var diagnostics: [ArchitectureDiagnostic] = []
        for file in files {
            let source = try String(contentsOfFile: file, encoding: .utf8)
            let sourceFile = Parser.parse(source: source)
            let context = ArchitectureLintContext(
                path: file,
                source: source,
                sourceFile: sourceFile
            )
            for rule in rules {
                diagnostics.append(contentsOf: rule.validate(context: context))
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
