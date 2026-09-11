import Foundation

enum WorktreeAnnotationMessagePolicyError: Error, Equatable, Sendable {
    case emptyBody
    case bodyTooLarge(actualUTF8Bytes: Int)
    case levelOneHeading
    case rawHTML
    case unsafeLinkDestination(String)
}

enum WorktreeAnnotationMessagePolicy {
    static let maximumBodyUTF8Bytes = 16 * 1024

    static func validate(_ body: String) throws -> String {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorktreeAnnotationMessagePolicyError.emptyBody
        }

        let bodyUTF8Bytes = body.utf8.count
        guard bodyUTF8Bytes <= maximumBodyUTF8Bytes else {
            throw WorktreeAnnotationMessagePolicyError.bodyTooLarge(actualUTF8Bytes: bodyUTF8Bytes)
        }

        let visibleMarkdown = markdownOutsideFencedCode(body)
        try rejectLevelOneHeadings(in: visibleMarkdown)
        try rejectRawHTML(in: visibleMarkdown)
        try rejectUnsafeLinkDestinations(in: visibleMarkdown)
        return body
    }

    private static func markdownOutsideFencedCode(_ body: String) -> String {
        var activeFence: (marker: Character, length: Int)?
        return body.split(separator: "\n", omittingEmptySubsequences: false)
            .map { lineSubstring -> String in
                let line = String(lineSubstring)
                guard let fence = fenceRun(in: line) else {
                    return activeFence == nil ? stripInlineCode(from: line) : ""
                }

                if let currentFence = activeFence {
                    if fence.marker == currentFence.marker, fence.length >= currentFence.length {
                        activeFence = nil
                    }
                    return ""
                }

                activeFence = fence
                return ""
            }
            .joined(separator: "\n")
    }

    private static func fenceRun(in line: String) -> (marker: Character, length: Int)? {
        let trimmedLeading = line.drop(while: { $0 == " " })
        let indentation = line.count - trimmedLeading.count
        guard indentation <= 3, let marker = trimmedLeading.first, marker == "`" || marker == "~" else {
            return nil
        }
        let length = trimmedLeading.prefix(while: { $0 == marker }).count
        return length >= 3 ? (marker, length) : nil
    }

    private static func stripInlineCode(from line: String) -> String {
        var result = ""
        var index = line.startIndex
        while index < line.endIndex {
            guard line[index] == "`" else {
                result.append(line[index])
                index = line.index(after: index)
                continue
            }

            let runStart = index
            while index < line.endIndex, line[index] == "`" {
                index = line.index(after: index)
            }
            let delimiter = String(line[runStart..<index])
            guard let closingRange = line.range(of: delimiter, range: index..<line.endIndex) else {
                result.append(contentsOf: delimiter)
                continue
            }
            result.append(
                contentsOf: String(repeating: " ", count: line.distance(from: runStart, to: closingRange.upperBound)))
            index = closingRange.upperBound
        }
        return result
    }

    private static func rejectLevelOneHeadings(in markdown: String) throws {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let atxHeading = try NSRegularExpression(pattern: #"^[ ]{0,3}#(?:[\t ]+|$)"#)
        let setextUnderline = try NSRegularExpression(pattern: #"^[ ]{0,3}=+[\t ]*$"#)

        for (index, line) in lines.enumerated() {
            if atxHeading.hasMatch(in: line) {
                throw WorktreeAnnotationMessagePolicyError.levelOneHeading
            }
            if index > 0,
                !lines[index - 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                setextUnderline.hasMatch(in: line)
            {
                throw WorktreeAnnotationMessagePolicyError.levelOneHeading
            }
        }
    }

    private static func rejectRawHTML(in markdown: String) throws {
        let rawHTML = try NSRegularExpression(
            pattern: #"(?is)<!--.*?-->|<\/?[A-Za-z][A-Za-z0-9-]*(?:\s[^>]*)?\s*\/?>|<\?.*?\?>|<![A-Z]+[^>]*>"#
        )
        guard !rawHTML.hasMatch(in: markdown) else {
            throw WorktreeAnnotationMessagePolicyError.rawHTML
        }
    }

    private static func rejectUnsafeLinkDestinations(in markdown: String) throws {
        let link = try NSRegularExpression(pattern: #"\]\(\s*<?([^\s>)]+)"#)
        for destination in link.captureGroupValues(in: markdown, group: 1) {
            guard let url = URL(string: destination),
                let scheme = url.scheme?.lowercased(),
                scheme == "http" || scheme == "https",
                url.host != nil
            else {
                throw WorktreeAnnotationMessagePolicyError.unsafeLinkDestination(destination)
            }
        }
    }
}

extension NSRegularExpression {
    fileprivate func hasMatch(in value: String) -> Bool {
        firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }

    fileprivate func captureGroupValues(in value: String, group: Int) -> [String] {
        matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap { match in
            guard let range = Range(match.range(at: group), in: value) else { return nil }
            return String(value[range])
        }
    }
}
