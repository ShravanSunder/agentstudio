import Foundation

enum FilesystemPathDisposition: Sendable, Equatable {
    case projected
    case gitInternal
    case ignoredByPolicy
}

/// Lightweight, cached filtering policy for filesystem projection payloads.
///
/// Current policy:
/// - suppress `.git` internals from projection-facing changed-path payloads
/// - apply root-level `.gitignore` rules for projection payload suppression
struct FilesystemPathFilter: Sendable {
    private let ignoredRules: [GitIgnoreRule]

    static func load(forRootPath rootPath: URL) -> Self {
        let gitIgnorePath = rootPath.appending(path: ".gitignore")
        guard let fileContents = try? String(contentsOf: gitIgnorePath, encoding: .utf8) else {
            return Self(ignoredRules: [])
        }

        let rules =
            fileContents
            .split(whereSeparator: \.isNewline)
            .compactMap { GitIgnoreRule(rawLine: String($0)) }
        return Self(ignoredRules: rules)
    }

    func classify(relativePath: String) -> FilesystemPathDisposition {
        if Self.isGitInternal(relativePath: relativePath) {
            return .gitInternal
        }
        if isIgnored(relativePath: relativePath) {
            return .ignoredByPolicy
        }
        return .projected
    }

    func isIgnored(relativePath: String) -> Bool {
        let normalizedPath = Self.normalized(relativePath: relativePath)
        guard !normalizedPath.isEmpty, normalizedPath != "." else { return false }

        var ignored = false
        for rule in ignoredRules {
            if rule.matches(relativePath: normalizedPath) {
                ignored = !rule.isNegated
            }
        }
        return ignored
    }

    static func isGitInternal(relativePath: String) -> Bool {
        let normalizedPath = normalized(relativePath: relativePath)
        guard !normalizedPath.isEmpty else { return false }
        let pathComponents = normalizedPath.split(separator: "/")
        return pathComponents.contains(".git")
    }

    private static func normalized(relativePath: String) -> String {
        var normalizedPath = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalizedPath.hasPrefix("./") {
            normalizedPath.removeFirst(2)
        }
        while normalizedPath.hasPrefix("/") {
            normalizedPath.removeFirst()
        }
        return normalizedPath
    }
}

private struct GitIgnoreRule: Sendable {
    let isNegated: Bool
    let anchoredToRoot: Bool
    let directoryOnly: Bool
    let originalPattern: String
    let regex: String

    init?(rawLine: String) {
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.hasPrefix("#") else { return nil }

        var workingLine = trimmed
        let isNegated = workingLine.hasPrefix("!")
        if isNegated {
            workingLine.removeFirst()
        }

        let anchoredToRoot = workingLine.hasPrefix("/")
        if anchoredToRoot {
            workingLine.removeFirst()
        }

        let directoryOnly = workingLine.hasSuffix("/")
        if directoryOnly {
            workingLine.removeLast()
        }

        guard !workingLine.isEmpty else { return nil }
        let regexPattern = Self.makeRegexPattern(
            pattern: workingLine,
            anchoredToRoot: anchoredToRoot,
            directoryOnly: directoryOnly
        )

        self.isNegated = isNegated
        self.anchoredToRoot = anchoredToRoot
        self.directoryOnly = directoryOnly
        self.originalPattern = workingLine
        self.regex = regexPattern
    }

    func matches(relativePath: String) -> Bool {
        guard let compiledRegex = try? NSRegularExpression(pattern: self.regex) else { return false }
        let pathRange = NSRange(relativePath.startIndex..<relativePath.endIndex, in: relativePath)
        return compiledRegex.firstMatch(in: relativePath, options: [], range: pathRange) != nil
    }

    private static func makeRegexPattern(
        pattern: String,
        anchoredToRoot: Bool,
        directoryOnly: Bool
    ) -> String {
        let patternHasSlash = pattern.contains("/")
        let escapedPattern = globToRegex(pattern)
        let rootPrefix: String

        if anchoredToRoot {
            rootPrefix = "^"
        } else if patternHasSlash {
            rootPrefix = "^(?:.*/)?"
        } else {
            rootPrefix = "^(?:.*/)?"
        }

        if !patternHasSlash, !anchoredToRoot {
            let componentRegex = globToRegex(pattern)
            if directoryOnly {
                return "^(?:.*/)?\(componentRegex)(?:/.*)?$"
            }
            return "^(?:.*/)?\(componentRegex)$"
        }

        if directoryOnly {
            return "\(rootPrefix)\(escapedPattern)(?:/.*)?$"
        }

        return "\(rootPrefix)\(escapedPattern)$"
    }

    private static func globToRegex(_ pattern: String) -> String {
        var output = ""
        var index = pattern.startIndex

        while index < pattern.endIndex {
            let character = pattern[index]

            if character == "*" {
                let nextIndex = pattern.index(after: index)
                if nextIndex < pattern.endIndex, pattern[nextIndex] == "*" {
                    output.append(".*")
                    index = pattern.index(after: nextIndex)
                    continue
                }
                output.append("[^/]*")
                index = nextIndex
                continue
            }

            if character == "?" {
                output.append("[^/]")
                index = pattern.index(after: index)
                continue
            }

            if "\\.+()|{}[]^$".contains(character) {
                output.append("\\")
            }
            output.append(character)
            index = pattern.index(after: index)
        }

        return output
    }
}
