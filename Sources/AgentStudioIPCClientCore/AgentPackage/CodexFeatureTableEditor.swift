import Foundation

/// Turns `features.hooks` on inside a Codex `config.toml` without reformatting
/// the file.
///
/// The edit is line-level on purpose. `config.toml` is the user's file, full of
/// their comments, ordering and profiles; round-tripping it through a TOML
/// encoder would rewrite all of it to change one boolean.
///
/// A line scanner can be wrong about TOML in exactly two ways that matter here:
/// a `[features]` header it fails to recognise, and a `[features]` line that is
/// really text inside a multi-line string. Either one would end with a second
/// `[features]` table appended to the file, which TOML rejects as a duplicate
/// table and which would stop Codex loading its own configuration. So the scan
/// either locates the table with certainty or refuses the edit.
package enum CodexFeatureTableEditor {
    package enum Outcome: Equatable, Sendable {
        case alreadyEnabled
        case enabledInExistingTable
        case appendedFeaturesTable

        package var describesAChange: Bool { self != .alreadyEnabled }
    }

    package static let featuresHeader = "[features]"
    package static let featuresTableName = "features"
    package static let hooksAssignment = "hooks = true"

    /// TOML's multi-line string delimiters. A line scanner cannot tell a table
    /// header written inside one of these from a real header, so a file that
    /// carries both a `[features]` line and a multi-line string is not safe to
    /// edit line by line.
    private static let multiLineStringDelimiters = ["\"\"\"", "'''"]

    /// - Parameter configurationPath: named only so a refusal can say which
    ///   file was left alone.
    package static func enablingHooks(
        in contents: String,
        configurationPath: String
    ) throws -> (contents: String, outcome: Outcome) {
        var lines = contents.components(separatedBy: "\n")
        let candidates = lines.indices.filter { mentionsFeaturesTable(lines[$0]) }

        // No line even spells `[features]`, so no real table can be hiding and
        // appending one cannot duplicate anything.
        guard let headerIndex = candidates.first else {
            return (appendingFeaturesTable(to: contents), .appendedFeaturesTable)
        }
        guard candidates.count == 1,
            case .header(let header) = tableHeader(in: lines[headerIndex]),
            !header.isArrayOfTables,
            !carriesMultiLineString(contents)
        else {
            throw AgentPackageInstallationError.featuresTableNotLocatable(configurationPath)
        }

        let tableRange = (headerIndex + 1)..<endOfTable(in: lines, after: headerIndex)
        if let assignmentIndex = lines[tableRange].indices.first(where: { isHooksAssignment(lines[$0]) }) {
            if hooksValueIsTrue(lines[assignmentIndex]) {
                return (contents, .alreadyEnabled)
            }
            lines[assignmentIndex] = matchingLineEnding(of: lines[assignmentIndex], text: hooksAssignment)
            return (lines.joined(separator: "\n"), .enabledInExistingTable)
        }
        lines.insert(
            matchingLineEnding(of: lines[headerIndex], text: hooksAssignment), at: headerIndex + 1)
        return (lines.joined(separator: "\n"), .enabledInExistingTable)
    }

    // MARK: - Scanning

    private struct TableHeaderLine {
        let name: String
        let isArrayOfTables: Bool
    }

    private enum HeaderScan {
        case notAHeader
        case header(TableHeaderLine)
        /// Starts a bracket but does not close into a name this scanner trusts.
        case unrecognized(String)
    }

    /// The table ends at the next table header. `[features.something]` is a
    /// different table, so a key after it does not belong to `[features]`.
    private static func endOfTable(in lines: [String], after headerIndex: Int) -> Int {
        var index = headerIndex + 1
        while index < lines.count {
            if case .notAHeader = tableHeader(in: lines[index]) {
                index += 1
                continue
            }
            return index
        }
        return lines.count
    }

    /// True when the line is, or is trying to be, the plain `[features]` table
    /// header. A line that trips this and then fails to parse cleanly is what
    /// makes the whole edit refuse rather than append.
    private static func mentionsFeaturesTable(_ line: String) -> Bool {
        switch tableHeader(in: line) {
        case .notAHeader:
            return false
        case .header(let header):
            return header.name == featuresTableName
        case .unrecognized(let trimmed):
            return trimmed.hasPrefix("[\(featuresTableName)")
        }
    }

    private static func tableHeader(in line: String) -> HeaderScan {
        let trimmed = strippingCarriageReturn(line).trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[") else { return .notAHeader }
        let isArrayOfTables = trimmed.hasPrefix("[[")
        let closing = isArrayOfTables ? "]]" : "]"
        let body = trimmed.dropFirst(isArrayOfTables ? 2 : 1)
        guard let close = body.range(of: closing) else { return .unrecognized(trimmed) }
        let name = body[body.startIndex..<close.lowerBound].trimmingCharacters(in: .whitespaces)
        let remainder = body[close.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, remainder.isEmpty || remainder.hasPrefix("#") else {
            return .unrecognized(trimmed)
        }
        return .header(TableHeaderLine(name: name, isArrayOfTables: isArrayOfTables))
    }

    private static func carriesMultiLineString(_ contents: String) -> Bool {
        multiLineStringDelimiters.contains { contents.contains($0) }
    }

    private static func isHooksAssignment(_ line: String) -> Bool {
        let trimmed = strippingCarriageReturn(line).trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("hooks") else { return false }
        let remainder = trimmed.dropFirst("hooks".count).trimmingCharacters(in: .whitespaces)
        return remainder.hasPrefix("=")
    }

    /// An inline comment after the value is the user's, so `hooks = true # keep`
    /// counts as already enabled and the line is never rewritten.
    private static func hooksValueIsTrue(_ line: String) -> Bool {
        guard let separator = line.firstIndex(of: "=") else { return false }
        let value = String(line[line.index(after: separator)...])
        return strippingComment(strippingCarriageReturn(value))
            .trimmingCharacters(in: .whitespaces) == "true"
    }

    // MARK: - Writing

    private static func appendingFeaturesTable(to contents: String) -> String {
        let terminator = contents.contains("\r\n") ? "\r\n" : "\n"
        guard !contents.isEmpty else {
            return "\(featuresHeader)\(terminator)\(hooksAssignment)\(terminator)"
        }
        let separator = contents.hasSuffix(terminator) ? terminator : terminator + terminator
        return "\(contents)\(separator)\(featuresHeader)\(terminator)\(hooksAssignment)\(terminator)"
    }

    /// Keeps a CRLF file CRLF: the lines were split on `\n`, so a replacement
    /// has to carry the `\r` its neighbours still carry.
    private static func matchingLineEnding(of line: String, text: String) -> String {
        line.hasSuffix("\r") ? "\(text)\r" : text
    }

    private static func strippingCarriageReturn(_ line: String) -> String {
        line.hasSuffix("\r") ? String(line.dropLast()) : line
    }

    private static func strippingComment(_ text: String) -> String {
        guard let comment = text.firstIndex(of: "#") else { return text }
        return String(text[text.startIndex..<comment])
    }
}
