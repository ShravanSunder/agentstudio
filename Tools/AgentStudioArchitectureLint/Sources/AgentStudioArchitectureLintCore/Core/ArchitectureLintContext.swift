import Foundation
import SwiftSyntax

struct ArchitectureLintContext {
    let path: String
    let source: String
    let sourceFile: SourceFileSyntax

    var normalizedPath: String {
        path.replacingOccurrences(of: "\\", with: "/")
    }

    var workspaceRelativePath: String? {
        let normalizedWorkingDirectory = FileManager.default.currentDirectoryPath
            .replacingOccurrences(of: "\\", with: "/")
        let path = normalizedPath
        guard path.hasPrefix("/") else {
            return path
        }
        if path == normalizedWorkingDirectory {
            return ""
        }
        let workingDirectoryPrefix = "\(normalizedWorkingDirectory)/"
        guard path.hasPrefix(workingDirectoryPrefix) else {
            return nil
        }
        return String(path.dropFirst(workingDirectoryPrefix.count))
    }

    func location(for position: AbsolutePosition) -> (line: Int, column: Int) {
        let converter = SourceLocationConverter(fileName: path, tree: sourceFile)
        let location = converter.location(for: position)
        return (location.line, location.column)
    }
}
