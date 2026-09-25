import Foundation

/// A rule over an agent instruction document (`AGENTS.md`) rather than a
/// Swift syntax tree. Runs in the same validation phase and reports through
/// the same diagnostics, ledger and exit code as Swift rules.
protocol ArchitectureDocumentRule: Sendable {
    var id: String { get }
    var severity: ArchitectureSeverity { get }

    func validate(document: AgentDocumentContext) -> [ArchitectureDiagnostic]
}

struct AgentDocumentContext: Sendable {
    static let fileName = "AGENTS.md"

    let path: String
    let contents: String
    let workspaceRootPath: String

    var workspaceRelativePath: String? {
        let rootPrefix = "\(workspaceRootPath)/"
        guard path.hasPrefix(rootPrefix) else {
            return nil
        }
        return String(path.dropFirst(rootPrefix.count))
    }

    var directoryPath: String {
        URL(fileURLWithPath: path).deletingLastPathComponent().path
    }

    static func isAgentDocument(_ path: String) -> Bool {
        URL(fileURLWithPath: path).lastPathComponent == fileName
    }
}
