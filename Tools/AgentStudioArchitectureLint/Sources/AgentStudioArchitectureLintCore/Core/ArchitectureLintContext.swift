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
        let targetOffset = max(0, position.utf8Offset)
        var currentOffset = 0
        var line = 1
        var column = 1

        for byte in source.utf8 {
            if currentOffset >= targetOffset {
                break
            }
            currentOffset += 1
            if byte == 10 {
                line += 1
                column = 1
            } else {
                column += 1
            }
        }

        return (line, column)
    }
}
