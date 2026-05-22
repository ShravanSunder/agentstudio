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
    let sourceRange: Range<String.Index>

    private init(
        path: String,
        line: Int?,
        column: Int?,
        sourceText: String,
        sourceRange: Range<String.Index>
    ) {
        self.path = path
        self.line = line
        self.column = column
        self.sourceText = sourceText
        self.sourceRange = sourceRange
    }

    static func make(
        path: String,
        line: Int?,
        column: Int?,
        sourceText: String,
        sourceRange: Range<String.Index>
    ) -> Self? {
        guard !path.isEmpty else { return nil }
        guard path.contains("/") else { return nil }
        guard !path.contains("://") else { return nil }
        guard line.map({ $0 >= 0 }) ?? true else { return nil }
        guard column.map({ $0 >= 0 }) ?? true else { return nil }
        guard sourceRange.lowerBound >= sourceText.startIndex,
            sourceRange.upperBound <= sourceText.endIndex
        else {
            return nil
        }
        return Self(
            path: path,
            line: line,
            column: column,
            sourceText: sourceText,
            sourceRange: sourceRange
        )
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.path == rhs.path
            && lhs.line == rhs.line
            && lhs.column == rhs.column
    }
}

struct TerminalURLReference: Equatable, Sendable {
    let url: URL
    let sourceText: String
    let sourceRange: Range<String.Index>

    private init(url: URL, sourceText: String, sourceRange: Range<String.Index>) {
        self.url = url
        self.sourceText = sourceText
        self.sourceRange = sourceRange
    }

    static func make(
        urlString: String,
        sourceText: String,
        sourceRange: Range<String.Index>? = nil
    ) -> Self? {
        guard let url = URL(string: urlString), url.scheme == "http" || url.scheme == "https" else {
            return nil
        }
        let resolvedSourceRange = sourceRange ?? sourceText.startIndex..<sourceText.endIndex
        guard resolvedSourceRange.lowerBound >= sourceText.startIndex,
            resolvedSourceRange.upperBound <= sourceText.endIndex
        else {
            return nil
        }
        return Self(url: url, sourceText: sourceText, sourceRange: resolvedSourceRange)
    }
}

struct TerminalSemanticArtifactExtractor: Sendable {
    private static let trailingPunctuation = CharacterSet(charactersIn: ".,;)]}>\"'")

    private static let urlExpression = makeExpression(
        pattern: #"https?://[^\s\)\]\}>"']+"#
    )

    private static let fileReferenceExpression = makeExpression(
        pattern: #"(?<![\w:/])((?:\.{1,2}/|/|[A-Za-z0-9_.-]+/)[^\s:,\]\)\}>\"']+)(?::([0-9]+))?(?::([0-9]+))?"#
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
            let trimmedURLRange = Self.trimTrailingPunctuation(in: urlRange, sourceText: sourceText)
            let url = String(sourceText[trimmedURLRange])
            guard !url.isEmpty else { continue }
            guard
                let reference = TerminalURLReference.make(
                    urlString: url,
                    sourceText: sourceText,
                    sourceRange: trimmedURLRange
                )
            else {
                continue
            }
            urlRanges.append(match.range)
            artifacts.append(
                (
                    location: match.range.location,
                    artifact: .urlReference(reference)
                ))
        }

        for match in Self.fileReferenceExpression.matches(in: sourceText, range: searchRange) {
            guard !urlRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else {
                continue
            }
            guard let pathRange = Range(match.range(at: 1), in: sourceText) else { continue }
            let trimmedPathRange = Self.trimTrailingPunctuation(in: pathRange, sourceText: sourceText)
            let path = String(sourceText[trimmedPathRange])
            guard Self.isUsefulFileReference(path) else { continue }
            guard
                let reference = TerminalFileReference.make(
                    path: path,
                    line: Self.integerCapture(at: 2, in: match, sourceText: sourceText),
                    column: Self.integerCapture(at: 3, in: match, sourceText: sourceText),
                    sourceText: sourceText,
                    sourceRange: trimmedPathRange
                )
            else {
                continue
            }
            artifacts.append(
                (
                    location: match.range.location,
                    artifact: .fileReference(reference)
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

    private static func trimTrailingPunctuation(
        in range: Range<String.Index>,
        sourceText: String
    ) -> Range<String.Index> {
        var upperBound = range.upperBound
        while upperBound > range.lowerBound {
            let previousIndex = sourceText.index(before: upperBound)
            let scalar = sourceText[previousIndex].unicodeScalars.first
            guard let scalar, trailingPunctuation.contains(scalar) else {
                break
            }
            upperBound = previousIndex
        }
        return range.lowerBound..<upperBound
    }

    private static func makeExpression(pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            preconditionFailure("Invalid terminal semantic artifact expression: \(error)")
        }
    }

    private static func isUsefulFileReference(_ path: String) -> Bool {
        // Known limitation: extensionless files and root-level paths without "/" are not extracted.
        guard path.contains("/") else { return false }
        guard !path.contains("://") else { return false }
        guard let lastComponent = path.split(separator: "/").last else { return false }
        return lastComponent.contains(".")
    }
}
