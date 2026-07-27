import Foundation

// MARK: - FuzzyMatch Result

/// Result of a fuzzy match: score (lower is better) and matched character ranges.
package struct FuzzyMatchResult {
    /// Score from 0.0 (perfect match) to 1.0 (no match). Below `threshold` is a match.
    package let score: Double
    /// Ranges of matched characters in the haystack (for highlighting).
    package let matchedRanges: [Range<String.Index>]
}

// MARK: - FuzzySearch

/// Lightweight fuzzy matching shared by product search surfaces.
package enum FuzzySearch {

    /// Default score threshold — items scoring above this are rejected.
    package static let defaultThreshold: Double = 0.7

    // MARK: - Fuzzy Match (core algorithm)

    /// Fuzzy-match `pattern` against `text`. Returns nil if no match.
    /// Score: 0.0 = perfect, 1.0 = worst. Consecutive and word-start matches score better.
    package static func fuzzyMatch(pattern: String, in text: String) -> FuzzyMatchResult? {
        let patternLower = pattern.lowercased()
        let textLower = text.lowercased()

        guard !patternLower.isEmpty else {
            return FuzzyMatchResult(score: 0.0, matchedRanges: [])
        }
        guard !textLower.isEmpty else { return nil }

        var patternIdx = patternLower.startIndex
        var textIdx = textLower.startIndex
        var matchedIndices: [String.Index] = []
        var textOffset = 0

        // First pass: find all matching character positions (greedy left-to-right)
        while patternIdx < patternLower.endIndex, textIdx < textLower.endIndex {
            if patternLower[patternIdx] == textLower[textIdx] {
                matchedIndices.append(text.index(text.startIndex, offsetBy: textOffset))
                patternIdx = patternLower.index(after: patternIdx)
            }
            textIdx = textLower.index(after: textIdx)
            textOffset += 1
        }

        // All pattern characters must be found
        guard patternIdx == patternLower.endIndex else { return nil }

        // Score calculation
        let score = calculateScore(
            matchedIndices: matchedIndices,
            text: text,
            patternLength: patternLower.count
        )

        // Build ranges from matched indices
        let ranges = buildRanges(from: matchedIndices, in: text)

        return FuzzyMatchResult(score: score, matchedRanges: ranges)
    }

    // MARK: - Scoring

    private static func calculateScore(
        matchedIndices: [String.Index],
        text: String,
        patternLength: Int
    ) -> Double {
        guard !matchedIndices.isEmpty else { return 1.0 }

        let textLength = Double(text.count)
        var totalScore: Double = 0
        var consecutiveBonus: Double = 0

        for (i, idx) in matchedIndices.enumerated() {
            let offset = text.distance(from: text.startIndex, to: idx)
            var charScore: Double = 0.1

            // Consecutive match bonus
            if i > 0 {
                let prevIdx = matchedIndices[i - 1]
                let nextOfPrev = text.index(after: prevIdx)
                if idx == nextOfPrev {
                    consecutiveBonus += 0.2
                    charScore += 0.2 + consecutiveBonus
                } else {
                    consecutiveBonus = 0
                }
            }

            // Word start bonus (first char or after separator)
            if offset == 0 {
                charScore += 0.6
            } else {
                let prevCharIdx = text.index(before: idx)
                let prevChar = text[prevCharIdx]
                if prevChar == " " || prevChar == "-" || prevChar == "_" || prevChar == "/" || prevChar == "." {
                    charScore += 0.4
                } else if prevChar.isLowercase && text[idx].isUppercase {
                    // camelCase boundary
                    charScore += 0.3
                }
            }

            totalScore += charScore
        }

        // Normalize: higher raw score is better → invert to 0.0 = best
        let maxPossible = Double(patternLength) * 1.0
        let normalizedScore = totalScore / max(maxPossible, 1.0)

        // Length penalty: prefer shorter strings (closer match)
        let lengthPenalty = 1.0 - (Double(patternLength) / textLength)

        // Final score: 0.0 = perfect, 1.0 = worst
        return max(0.0, min(1.0, 1.0 - normalizedScore * 0.7 - (1.0 - lengthPenalty) * 0.3))
    }

    // MARK: - Range Building

    /// Coalesce consecutive matched indices into contiguous ranges.
    private static func buildRanges(from indices: [String.Index], in text: String) -> [Range<String.Index>] {
        guard let first = indices.first else { return [] }

        var ranges: [Range<String.Index>] = []
        var rangeStart = first
        var rangeEnd = text.index(after: first)

        for i in 1..<indices.count {
            let idx = indices[i]
            if idx == rangeEnd {
                // Extend current range
                rangeEnd = text.index(after: idx)
            } else {
                // Close current range, start new
                ranges.append(rangeStart..<rangeEnd)
                rangeStart = idx
                rangeEnd = text.index(after: idx)
            }
        }
        ranges.append(rangeStart..<rangeEnd)
        return ranges
    }

}
