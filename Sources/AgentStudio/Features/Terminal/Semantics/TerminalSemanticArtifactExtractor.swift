import Foundation

enum TerminalSemanticArtifact: Equatable, Sendable {
    case fileReference(TerminalFileReference)
    case urlReference(TerminalURLReference)
}

struct TerminalFileReference: Equatable, Sendable {
    let path: String
    let line: Int?
    let column: Int?
    let sourceText: String
}

struct TerminalURLReference: Equatable, Sendable {
    let url: String
    let sourceText: String
}

struct TerminalSemanticArtifactExtractor: Sendable {
    private static let trailingPunctuation = CharacterSet(charactersIn: ".,;)]}>\"'")

    private static let urlExpression = makeExpression(
        pattern: #"https?://[^\s\)\]\}>"']+"#
    )

    private static let fileReferenceExpression = makeExpression(
        pattern: #"(?<![\w:/])((?:\.{1,2}/|/|[A-Za-z0-9_.-]+/)[^\s:]+)(?::([0-9]+))?(?::([0-9]+))?"#
    )

    func artifacts(in text: String) -> [TerminalSemanticArtifact] {
        text.split(whereSeparator: \.isNewline)
            .flatMap { artifacts(inLine: String($0)) }
    }

    private func artifacts(inLine line: String) -> [TerminalSemanticArtifact] {
        let sourceText = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else { return [] }

        var artifacts: [(location: Int, artifact: TerminalSemanticArtifact)] = []
        var urlRanges: [NSRange] = []
        let searchRange = NSRange(sourceText.startIndex..<sourceText.endIndex, in: sourceText)

        for match in Self.urlExpression.matches(in: sourceText, range: searchRange) {
            guard let urlRange = Range(match.range, in: sourceText) else { continue }
            let url = Self.trimTrailingPunctuation(String(sourceText[urlRange]))
            guard !url.isEmpty else { continue }
            urlRanges.append(match.range)
            artifacts.append(
                (
                    location: match.range.location,
                    artifact: .urlReference(
                        TerminalURLReference(
                            url: url,
                            sourceText: sourceText
                        )
                    )
                ))
        }

        for match in Self.fileReferenceExpression.matches(in: sourceText, range: searchRange) {
            guard !urlRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else {
                continue
            }
            guard let pathRange = Range(match.range(at: 1), in: sourceText) else { continue }
            let path = Self.trimTrailingPunctuation(String(sourceText[pathRange]))
            guard Self.isUsefulFileReference(path) else { continue }
            artifacts.append(
                (
                    location: match.range.location,
                    artifact: .fileReference(
                        TerminalFileReference(
                            path: path,
                            line: Self.integerCapture(at: 2, in: match, sourceText: sourceText),
                            column: Self.integerCapture(at: 3, in: match, sourceText: sourceText),
                            sourceText: sourceText
                        )
                    )
                ))
        }

        return
            artifacts
            .sorted { lhs, rhs in lhs.location < rhs.location }
            .map(\.artifact)
    }

    private static func integerCapture(
        at index: Int,
        in match: NSTextCheckingResult,
        sourceText: String
    ) -> Int? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: sourceText) else {
            return nil
        }
        return Int(sourceText[swiftRange])
    }

    private static func trimTrailingPunctuation(_ value: String) -> String {
        value.trimmingCharacters(in: trailingPunctuation)
    }

    private static func makeExpression(pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            preconditionFailure("Invalid terminal semantic artifact expression: \(error)")
        }
    }

    private static func isUsefulFileReference(_ path: String) -> Bool {
        guard path.contains("/") else { return false }
        guard !path.contains("://") else { return false }
        guard let lastComponent = path.split(separator: "/").last else { return false }
        return lastComponent.contains(".")
    }
}
