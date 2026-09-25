import Foundation

/// Permitted violation counts per rule and file: the only place debt lives.
///
/// Existing violations are frozen by count, and a count may only fall. The
/// file is tab-separated with a header, sorted by rule then path, one row per
/// rule and repository-relative path, so a pull request's change to it is a
/// readable diff that the ratchet check compares with the merge base.
///
/// Named-owner allowlists are not debt and do not live here; they stay in
/// `ArchitectureAllowlists` with one owner and reason each.
struct ArchitectureDebtLedger: Equatable {
    static let header = "rule_id\tpath\tcount"

    /// Where the ledger was read from, as diagnostics should name it.
    let sourcePath: String
    let entries: [DebtLedgerEntry]

    var rendered: String {
        let rows = entries.sorted { $0.key < $1.key }.map { entry in
            "\(entry.key.ruleID)\t\(entry.key.path)\t\(entry.count)"
        }
        return ([Self.header] + rows).joined(separator: "\n") + "\n"
    }

    static func load(path: String, displayPath: String) throws -> Self {
        let contents: String
        do {
            contents = try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            throw DebtLedgerError.unreadable(path: displayPath, reason: "\(error)")
        }
        return try parse(contents: contents, sourcePath: displayPath)
    }

    static func parse(contents: String, sourcePath: String) throws -> Self {
        var lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }
        guard lines.first == header else {
            throw DebtLedgerError.malformed(
                path: sourcePath,
                line: 1,
                reason: "first line must be the header \"rule_id<TAB>path<TAB>count\""
            )
        }

        var entries: [DebtLedgerEntry] = []
        for (index, line) in lines.enumerated().dropFirst() {
            let lineNumber = index + 1
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 3 else {
                throw DebtLedgerError.malformed(
                    path: sourcePath,
                    line: lineNumber,
                    reason: "expected 3 tab-separated fields (rule_id, path, count), found \(fields.count)"
                )
            }
            let (ruleID, path, countText) = (fields[0], fields[1], fields[2])
            guard !ruleID.isEmpty, !path.isEmpty, !path.hasPrefix("/"), !path.contains("..") else {
                throw DebtLedgerError.malformed(
                    path: sourcePath,
                    line: lineNumber,
                    reason: "rule_id and a repository-relative path are required"
                )
            }
            guard let count = Int(countText), count >= 1 else {
                throw DebtLedgerError.malformed(
                    path: sourcePath,
                    line: lineNumber,
                    reason: "count must be a whole number of at least 1; remove the row instead of writing 0"
                )
            }
            let entry = DebtLedgerEntry(key: DebtLedgerKey(ruleID: ruleID, path: path), count: count, line: lineNumber)
            if let previous = entries.last, !(previous.key < entry.key) {
                throw DebtLedgerError.malformed(
                    path: sourcePath,
                    line: lineNumber,
                    reason: previous.key == entry.key
                        ? "duplicate row for \(ruleID) \(path)"
                        : "rows must be sorted by rule_id, then path"
                )
            }
            entries.append(entry)
        }
        return Self(sourcePath: sourcePath, entries: entries)
    }
}

struct DebtLedgerKey: Hashable, Comparable, Sendable {
    let ruleID: String
    /// Repository-relative, forward slashes, no leading slash.
    let path: String

    static func < (left: Self, right: Self) -> Bool {
        if left.ruleID != right.ruleID {
            return left.ruleID < right.ruleID
        }
        return left.path < right.path
    }
}

struct DebtLedgerEntry: Equatable, Sendable {
    let key: DebtLedgerKey
    let count: Int
    /// 1-based line in the ledger file, for diagnostics that point at the row.
    let line: Int
}

enum DebtLedgerError: Error, CustomStringConvertible, Equatable {
    case unreadable(path: String, reason: String)
    case malformed(path: String, line: Int, reason: String)

    var description: String {
        switch self {
        case .unreadable(let path, let reason):
            "cannot read debt ledger \(path): \(reason)"
        case .malformed(let path, let line, let reason):
            "\(path):\(line): malformed debt ledger: \(reason)"
        }
    }
}
