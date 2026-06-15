import Foundation
import SwiftSyntax

struct ArchitectureLintContext {
    let path: String
    let source: String
    let sourceFile: SourceFileSyntax

    var normalizedPath: String {
        path.replacingOccurrences(of: "\\", with: "/")
    }

    func location(for position: AbsolutePosition) -> (line: Int, column: Int) {
        let converter = SourceLocationConverter(fileName: path, tree: sourceFile)
        let location = converter.location(for: position)
        return (location.line, location.column)
    }
}
