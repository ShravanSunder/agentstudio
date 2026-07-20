import Foundation
import SwiftSyntax

struct ArchitectureLintContext {
    let path: String
    let source: String
    let sourceFile: SourceFileSyntax
    private let workspaceRootPath: String

    init(
        path: String,
        source: String,
        sourceFile: SourceFileSyntax,
        workspaceRootPath: String = FileManager.default.currentDirectoryPath
    ) {
        self.path = path
        self.source = source
        self.sourceFile = sourceFile
        self.workspaceRootPath = workspaceRootPath
    }

    var normalizedPath: String {
        path.replacingOccurrences(of: "\\", with: "/")
    }

    var workspaceRelativePath: String? {
        let normalizedWorkingDirectory =
            workspaceRootPath
            .replacingOccurrences(of: "\\", with: "/")
        let path = normalizedAbsolutePath
        if path == normalizedWorkingDirectory {
            return ""
        }
        let workingDirectoryPrefix = "\(normalizedWorkingDirectory)/"
        guard path.hasPrefix(workingDirectoryPrefix) else {
            return nil
        }
        return String(path.dropFirst(workingDirectoryPrefix.count))
    }

    var syntaxScopeSourceIdentity: String {
        workspaceRelativePath ?? normalizedAbsolutePath
    }

    private var normalizedAbsolutePath: String {
        if normalizedPath.hasPrefix("/") {
            return normalizedPath
        }
        return URL(
            fileURLWithPath: normalizedPath,
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        ).standardizedFileURL.path
    }

    func location(for position: AbsolutePosition) -> (line: Int, column: Int) {
        let converter = SourceLocationConverter(fileName: path, tree: sourceFile)
        let location = converter.location(for: position)
        return (location.line, location.column)
    }
}
