import Testing
import Foundation

@testable import AgentStudio

@Suite(.serialized)
struct CommandBarSearchTests {

    @Test
    func test_fuzzyMatch_exactMatch_returnsLowScore() {
        // Act
        let result = CommandBarSearch.fuzzyMatch(pattern: "Close Tab", in: "Close Tab")

        // Assert
        #expect(result != nil)
        #expect(#require(result).score < 0.3)
    }

    @Test
    func test_fuzzyMatch_prefixMatch_returnsLowScore() {
        // Act
        let result = CommandBarSearch.fuzzyMatch(pattern: "clo", in: "Close Tab")

        // Assert
        #expect(result != nil)
        #expect(#require(result).score < 0.5)
    }

    @Test
    func test_fuzzyMatch_caseInsensitive_matches() {
        // Act
        let result = CommandBarSearch.fuzzyMatch(pattern: "close", in: "Close Tab")

        // Assert
        #expect(result != nil)
    }

    @Test
    func test_fuzzyMatch_noMatch_returnsNil() {
        // Act
        let result = CommandBarSearch.fuzzyMatch(pattern: "xyz", in: "Close Tab")

        // Assert
        #expect(result == nil)
    }

    @Test
    func test_fuzzyMatch_emptyPattern_returnsZeroScore() {
        // Act
        let result = CommandBarSearch.fuzzyMatch(pattern: "", in: "Close Tab")

        // Assert
        #expect(result != nil)
        #expect(#require(result).score == 0.0)
        #expect(#require(result).matchedRanges.isEmpty)
    }

    @Test
    func test_fuzzyMatch_emptyText_returnsNil() {
        // Act
        let result = CommandBarSearch.fuzzyMatch(pattern: "a", in: "")

        // Assert
        #expect(result == nil)
    }

    // MARK: - Fuzzy Match — Scoring Quality

    @Test
    func test_fuzzyMatch_consecutiveChars_scoreBetterThanScattered() {
        // Act
        let consecutive = CommandBarSearch.fuzzyMatch(pattern: "sp", in: "Split Right")
        let scattered = CommandBarSearch.fuzzyMatch(pattern: "st", in: "Split Right")

        // Assert — both match, but consecutive should score better (lower)
        #expect(consecutive != nil)
        #expect(scattered != nil)
        #expect(#require(consecutive).score < #require(scattered).score)
    }

    @Test
    func test_fuzzyMatch_wordStartMatch_scoresBetter() {
        // Act
        let wordStart = CommandBarSearch.fuzzyMatch(pattern: "sr", in: "Split Right")
        let midWord = CommandBarSearch.fuzzyMatch(pattern: "pi", in: "Split Right")

        // Assert — word start (S + R) should score better
        #expect(wordStart != nil)
        #expect(midWord != nil)
        #expect(#require(wordStart).score < #require(midWord).score)
    }

    // MARK: - Fuzzy Match — Ranges

    @Test
    func test_fuzzyMatch_returnsMatchedRanges() {
        // Act
        let result = CommandBarSearch.fuzzyMatch(pattern: "ct", in: "Close Tab")

        // Assert
        #expect(result != nil)
        #expect(#require(result).matchedRanges.isEmpty == false)
    }

    @Test
    func test_fuzzyMatch_consecutiveChars_coalesceIntoSingleRange() {
        // Act
        let result = CommandBarSearch.fuzzyMatch(pattern: "Clo", in: "Close Tab")

        // Assert — "Clo" should produce 1 contiguous range
        #expect(result != nil)
        #expect(#require(result).matchedRanges.count == 1)
    }

    @Test
    func test_fuzzyMatch_scatteredChars_produceMultipleRanges() {
        // Act
        let result = CommandBarSearch.fuzzyMatch(pattern: "ct", in: "Close Tab")

        // Assert — "C" and "T" are non-contiguous → 2 ranges
        #expect(result != nil)
        #expect(#require(result).matchedRanges.count == 2)
    }

    // MARK: - Score Item

    @Test
    func test_scoreItem_emptyQuery_returnsZero() {
        // Arrange
        let item = makeCommandBarItem(title: "Close Tab")

        // Act
        let score = CommandBarSearch.scoreItem(item, query: "")

        // Assert — empty query matches everything with best score
        #expect(score == 0.0)
    }

    @Test
    func test_scoreItem_matchingTitle_returnsScore() {
        // Arrange
        let item = makeCommandBarItem(title: "Close Tab")

        // Act
        let score = CommandBarSearch.scoreItem(item, query: "close")

        // Assert
        #expect(score != nil)
        #expect(#require(score) < 0.7)
    }

    @Test
    func test_scoreItem_noMatch_returnsNil() {
        // Arrange
        let item = makeCommandBarItem(title: "Close Tab")

        // Act
        let score = CommandBarSearch.scoreItem(item, query: "xyzzy")

        // Assert
        #expect(score == nil)
    }

    @Test
    func test_scoreItem_matchingKeyword_returnsScore() {
        // Arrange
        let item = makeCommandBarItem(title: "Close Tab", keywords: ["shutdown", "remove"])

        // Act
        let score = CommandBarSearch.scoreItem(item, query: "shut")

        // Assert
        #expect(score != nil)
    }

    @Test
    func test_scoreItem_matchingSubtitle_returnsScore() {
        // Arrange
        let item = makeCommandBarItem(title: "Terminal", subtitle: "main-feature")

        // Act
        let score = CommandBarSearch.scoreItem(item, query: "main")

        // Assert
        #expect(score != nil)
    }

    @Test
    func test_scoreItem_recentBoost_improvedScore() {
        // Arrange
        let item = makeCommandBarItem(id: "recent-item", title: "Close Tab")

        // Act
        let scoreWithoutRecent = CommandBarSearch.scoreItem(item, query: "close", recentIds: [])
        let scoreWithRecent = CommandBarSearch.scoreItem(item, query: "close", recentIds: ["recent-item"])

        // Assert — recent item should score better (lower)
        #expect(scoreWithoutRecent != nil)
        #expect(scoreWithRecent != nil)
        #expect(#require(scoreWithRecent) < #require(scoreWithoutRecent))
    }

    // MARK: - Filter

    @Test
    func test_filter_emptyQuery_returnsAllItems() {
        // Arrange
        let items = [
            makeCommandBarItem(id: "a", title: "Close Tab"),
            makeCommandBarItem(id: "b", title: "Split Right"),
        ]

        // Act
        let filtered = CommandBarSearch.filter(items: items, query: "")

        // Assert
        #expect(filtered.count == 2)
    }

    @Test
    func test_filter_matchingQuery_returnsMatchedItemsSorted() {
        // Arrange
        let items = [
            makeCommandBarItem(id: "a", title: "Add Repo"),
            makeCommandBarItem(id: "b", title: "Close Tab"),
            makeCommandBarItem(id: "c", title: "Close Pane"),
        ]

        // Act
        let filtered = CommandBarSearch.filter(items: items, query: "close")

        // Assert — only "Close Tab" and "Close Pane" match
        #expect(filtered.count == 2)
        #expect(filtered.allSatisfy { $0.title.lowercased().contains("close") })
    }

    @Test
    func test_filter_noMatches_returnsEmpty() {
        // Arrange
        let items = [
            makeCommandBarItem(id: "a", title: "Close Tab")
        ]

        // Act
        let filtered = CommandBarSearch.filter(items: items, query: "xyzzy")

        // Assert
        #expect(filtered.isEmpty)
    }
}
