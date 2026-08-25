import Foundation

struct WorktreeAnnotationMarkdownPresentationContext: Equatable, Sendable {
    let worktreeLabel: String
    let comparisonLabel: String?
}

enum WorktreeAnnotationMarkdownProjector {
    static func project(
        _ snapshot: WorktreeAnnotationBatchSnapshotV2,
        presentation: WorktreeAnnotationMarkdownPresentationContext
    ) -> Data {
        var markdown = "# Worktree annotation batch\n\n"
        markdown += "Session: \(snapshot.session.label)\n"
        markdown += "Worktree: \(inlineCode(presentation.worktreeLabel))\n"
        if let comparisonLabel = presentation.comparisonLabel {
            markdown += "Comparison: \(inlineCode(comparisonLabel))\n"
        }
        for entry in snapshot.entries {
            markdown += "\n---\n\n"
            markdown += context(for: entry)
            markdown += "\nAuthor: \(authorLabel(entry.message.author.kind))\n"
            markdown += "\nMessage:\n\n"
            markdown += entry.bodyMarkdown
            markdown += "\n"
        }
        return Data(markdown.utf8)
    }

    private static func context(for entry: WorktreeAnnotationBatchSnapshotV2.Entry) -> String {
        let currentCoordinate: WorktreeAnnotationBatchSnapshot.Coordinate? =
            switch entry.placement {
            case .exact(let coordinate), .relocated(let coordinate): coordinate
            case .outdated, .unavailable: nil
            }
        var lines = ["File: \(inlineCode(currentCoordinate?.path ?? entry.origin.path))"]
        if let currentCoordinate, currentCoordinate.path != entry.origin.path {
            lines.append("Original file: \(inlineCode(entry.origin.path))")
        }
        if let currentCoordinate {
            lines.append(
                "Location: \(lineRange(start: currentCoordinate.startLine, end: currentCoordinate.endLine))"
            )
            if currentCoordinate.startLine != entry.origin.startLine
                || currentCoordinate.endLine != entry.origin.endLine
            {
                lines.append(
                    "Original location: \(lineRange(start: entry.origin.startLine, end: entry.origin.endLine))"
                )
            }
        } else {
            lines.append(
                "Original location: \(lineRange(start: entry.origin.startLine, end: entry.origin.endLine))"
            )
        }
        switch entry.origin.source {
        case .file:
            break
        case .diff(let side, _, _):
            lines.append("Side: \(side.rawValue)")
        }
        let placementLabel: String =
            switch entry.placement {
            case .exact: "exact"
            case .relocated: "relocated"
            case .outdated: "outdated — verify current location"
            case .unavailable: "unavailable — verify current location"
            }
        lines.append("Placement: \(placementLabel)")
        lines.append("Thread: \(entry.resolution.rawValue)")
        lines.append("")
        lines.append("Source:")
        lines.append("")
        lines.append(sourceFence(excerpt: entry.origin.excerpt, path: entry.origin.path))
        return lines.joined(separator: "\n") + "\n"
    }

    private static func authorLabel(_ kind: WorktreeAnnotationBatchSnapshotV2.MessageContext.Author.Kind) -> String {
        switch kind {
        case .human: "Human"
        case .agent: "Agent"
        }
    }

    private static func sourceFence(
        excerpt: [WorktreeAnnotationBatchSnapshot.ExcerptLine],
        path: String
    ) -> String {
        let sourceText = excerpt.map(\.text).joined(separator: "\n")
        let fence = String(repeating: "`", count: max(3, longestBacktickRun(in: sourceText) + 1))
        let language = sourceLanguage(for: path)
        let lineNumberWidth = String(excerpt.map(\.lineNumber).max() ?? 1).count
        let numberedSource = excerpt.map { excerptLine -> String in
            let lineNumber = String(excerptLine.lineNumber)
            let padding = String(repeating: " ", count: max(0, lineNumberWidth - lineNumber.count))
            return "\(padding)\(lineNumber) │ \(excerptLine.text)"
        }.joined(separator: "\n")
        return "\(fence)\(language)\n\(numberedSource)\n\(fence)"
    }

    private static func longestBacktickRun(in value: String) -> Int {
        var longest = 0
        var current = 0
        for character in value {
            if character == "`" {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }
        return longest
    }

    private static func sourceLanguage(for path: String) -> String {
        let suffix = URL(fileURLWithPath: path).pathExtension.lowercased()
        guard !suffix.isEmpty, suffix.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            return ""
        }
        return suffix
    }

    private static func inlineCode(_ value: String) -> String {
        let fence = String(repeating: "`", count: max(1, longestBacktickRun(in: value) + 1))
        return "\(fence)\(value)\(fence)"
    }

    private static func lineRange(start: Int, end: Int) -> String {
        start == end ? "line \(start)" : "lines \(start)–\(end)"
    }
}
