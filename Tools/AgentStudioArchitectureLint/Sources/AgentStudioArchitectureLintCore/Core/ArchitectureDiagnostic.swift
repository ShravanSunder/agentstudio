import Foundation

struct ArchitectureDiagnostic: Comparable, Equatable {
    let path: String
    let line: Int
    let column: Int
    let severity: ArchitectureSeverity
    let ruleID: String
    let message: String

    var rendered: String {
        "\(path):\(line):\(column): \(severity.rawValue): [\(ruleID)] \(message)\n"
    }

    static func < (left: Self, right: Self) -> Bool {
        if left.path != right.path {
            return left.path < right.path
        }
        if left.line != right.line {
            return left.line < right.line
        }
        if left.column != right.column {
            return left.column < right.column
        }
        return left.ruleID < right.ruleID
    }
}

enum ArchitectureSeverity: String, Comparable {
    case error
    case warning

    static func < (left: Self, right: Self) -> Bool {
        left.rawValue < right.rawValue
    }
}
