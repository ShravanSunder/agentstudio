import Foundation

/// Turns `features.hooks` on inside a Codex `config.toml` without reformatting
/// the file.
///
/// The edit is line-level on purpose. `config.toml` is the user's file, full of
/// their comments, ordering and profiles; round-tripping it through a TOML
/// encoder would rewrite all of it to change one boolean.
package enum CodexFeatureTableEditor {
    package enum Outcome: Equatable, Sendable {
        case alreadyEnabled
        case enabledInExistingTable
        case appendedFeaturesTable

        package var describesAChange: Bool { self != .alreadyEnabled }
    }

    package static let featuresHeader = "[features]"
    package static let hooksAssignment = "hooks = true"

    package static func enablingHooks(in contents: String) -> (contents: String, outcome: Outcome) {
        var lines = contents.components(separatedBy: "\n")
        guard let headerIndex = lines.firstIndex(where: { isFeaturesHeader($0) }) else {
            return (appendingFeaturesTable(to: contents), .appendedFeaturesTable)
        }
        let tableRange = (headerIndex + 1)..<endOfTable(in: lines, after: headerIndex)
        if let assignmentIndex = lines[tableRange].indices.first(where: { isHooksAssignment(lines[$0]) }) {
            if hooksValueIsTrue(lines[assignmentIndex]) {
                return (contents, .alreadyEnabled)
            }
            lines[assignmentIndex] = hooksAssignment
            return (lines.joined(separator: "\n"), .enabledInExistingTable)
        }
        lines.insert(hooksAssignment, at: headerIndex + 1)
        return (lines.joined(separator: "\n"), .enabledInExistingTable)
    }

    /// The table ends at the next table header. `[features.something]` is a
    /// different table, so a key after it does not belong to `[features]`.
    private static func endOfTable(in lines: [String], after headerIndex: Int) -> Int {
        var index = headerIndex + 1
        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("[") { return index }
            index += 1
        }
        return lines.count
    }

    private static func isFeaturesHeader(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == featuresHeader
    }

    private static func isHooksAssignment(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("hooks") else { return false }
        let remainder = trimmed.dropFirst("hooks".count).trimmingCharacters(in: .whitespaces)
        return remainder.hasPrefix("=")
    }

    private static func hooksValueIsTrue(_ line: String) -> Bool {
        guard let separator = line.firstIndex(of: "=") else { return false }
        return line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces) == "true"
    }

    private static func appendingFeaturesTable(to contents: String) -> String {
        guard !contents.isEmpty else { return "\(featuresHeader)\n\(hooksAssignment)\n" }
        let separator = contents.hasSuffix("\n") ? "\n" : "\n\n"
        return "\(contents)\(separator)\(featuresHeader)\n\(hooksAssignment)\n"
    }
}
