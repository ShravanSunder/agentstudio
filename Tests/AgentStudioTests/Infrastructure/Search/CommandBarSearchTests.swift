import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct FuzzySearchTests {

    @Test
    func test_fuzzyMatch_exactMatch_returnsLowScore() {
        // Act
        let result = FuzzySearch.fuzzyMatch(pattern: "Close Tab", in: "Close Tab")

        // Assert
        guard let result else {
            Issue.record("Expected fuzzy match result")
            return
        }
        #expect(result.score < 0.3)
    }

    @Test
    func test_fuzzyMatch_prefixMatch_returnsLowScore() {
        // Act
        let result = FuzzySearch.fuzzyMatch(pattern: "clo", in: "Close Tab")

        // Assert
        guard let result else {
            Issue.record("Expected fuzzy match result")
            return
        }
        #expect(result.score < 0.5)
    }

    @Test
    func test_fuzzyMatch_caseInsensitive_matches() {
        // Act
        let result = FuzzySearch.fuzzyMatch(pattern: "close", in: "Close Tab")

        // Assert
        #expect(result != nil)
    }

    @Test
    func test_fuzzyMatch_noMatch_returnsNil() {
        // Act
        let result = FuzzySearch.fuzzyMatch(pattern: "xyz", in: "Close Tab")

        // Assert
        #expect(result == nil)
    }

    @Test
    func test_fuzzyMatch_emptyPattern_returnsZeroScore() {
        // Act
        let result = FuzzySearch.fuzzyMatch(pattern: "", in: "Close Tab")

        // Assert
        guard let result else {
            Issue.record("Expected fuzzy match result")
            return
        }
        #expect(result.score == 0.0)
        #expect(result.matchedRanges.isEmpty)
    }

    @Test
    func test_fuzzyMatch_emptyText_returnsNil() {
        // Act
        let result = FuzzySearch.fuzzyMatch(pattern: "a", in: "")

        // Assert
        #expect(result == nil)
    }

    // MARK: - Fuzzy Match — Scoring Quality

    @Test
    func test_fuzzyMatch_consecutiveChars_scoreBetterThanScattered() {
        // Act
        let consecutive = FuzzySearch.fuzzyMatch(pattern: "sp", in: "Split Right")
        let scattered = FuzzySearch.fuzzyMatch(pattern: "st", in: "Split Right")

        // Assert — both match, but consecutive should score better (lower)
        guard let consecutive else {
            Issue.record("Expected consecutive match")
            return
        }
        guard let scattered else {
            Issue.record("Expected scattered match")
            return
        }
        #expect(consecutive.score < scattered.score)
    }

    @Test
    func test_fuzzyMatch_wordStartMatch_scoresBetter() {
        // Act
        let wordStart = FuzzySearch.fuzzyMatch(pattern: "sr", in: "Split Right")
        let midWord = FuzzySearch.fuzzyMatch(pattern: "pi", in: "Split Right")

        // Assert — word start (S + R) should score better
        guard let wordStart else {
            Issue.record("Expected word-start match")
            return
        }
        guard let midWord else {
            Issue.record("Expected mid-word match")
            return
        }
        #expect(wordStart.score < midWord.score)
    }

    // MARK: - Fuzzy Match — Ranges

    @Test
    func test_fuzzyMatch_returnsMatchedRanges() {
        // Act
        let result = FuzzySearch.fuzzyMatch(pattern: "ct", in: "Close Tab")

        // Assert
        guard let result else {
            Issue.record("Expected fuzzy match result")
            return
        }
        #expect(result.matchedRanges.isEmpty == false)
    }

    @Test
    func test_fuzzyMatch_consecutiveChars_coalesceIntoSingleRange() {
        // Act
        let result = FuzzySearch.fuzzyMatch(pattern: "Clo", in: "Close Tab")

        // Assert — "Clo" should produce 1 contiguous range
        guard let result else {
            Issue.record("Expected fuzzy match result")
            return
        }
        #expect(result.matchedRanges.count == 1)
    }

    @Test
    func test_fuzzyMatch_scatteredChars_produceMultipleRanges() {
        // Act
        let result = FuzzySearch.fuzzyMatch(pattern: "ct", in: "Close Tab")

        // Assert — "C" and "T" are non-contiguous → 2 ranges
        guard let result else {
            Issue.record("Expected fuzzy match result")
            return
        }
        #expect(result.matchedRanges.count == 2)
    }

}
