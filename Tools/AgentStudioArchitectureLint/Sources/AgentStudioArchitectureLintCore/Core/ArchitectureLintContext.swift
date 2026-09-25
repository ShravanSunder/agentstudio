import Foundation
import SwiftSyntax
import Synchronization

struct ArchitectureLintContext {
    let path: String
    let source: String
    let sourceFile: SourceFileSyntax
    let workspaceRootPath: String
    private let lineTable: LazySourceLineTable

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
        self.lineTable = LazySourceLineTable(fileName: path, tree: sourceFile)
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

    /// Under a `Sources/` directory, whether the path is absolute or
    /// workspace-relative.
    var isUnderSourcesDirectory: Bool {
        "/\(normalizedPath)".contains("/Sources/")
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
        let location = lineTable.location(for: position)
        return (location.line, location.column)
    }
}

/// One file's line table, built on the first diagnostic and reused for the
/// rest, so the cost is per file rather than per diagnostic.
private final class LazySourceLineTable: Sendable {
    private let fileName: String
    private let tree: SourceFileSyntax
    private let converter = Mutex<SourceLocationConverter?>(nil)

    init(fileName: String, tree: SourceFileSyntax) {
        self.fileName = fileName
        self.tree = tree
    }

    func location(for position: AbsolutePosition) -> SourceLocation {
        converter.withLock { cachedConverter in
            let converter = cachedConverter ?? SourceLocationConverter(fileName: fileName, tree: tree)
            cachedConverter = converter
            return converter.location(for: position)
        }
    }
}
