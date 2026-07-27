import Foundation

/// Command-bar-specific scoring, filtering, ranking, recency, and tracing.
enum CommandBarSearch {
    /// Score a `CommandBarItem` against a query using weighted multi-field matching.
    /// Returns nil if no field matches above threshold.
    static func scoreItem(
        _ item: CommandBarItem,
        query: String,
        recentIds: [String] = [],
        threshold: Double = FuzzySearch.defaultThreshold
    ) -> Double? {
        guard !query.isEmpty else { return 0.0 }

        var bestScore: Double = 1.0

        if let result = FuzzySearch.fuzzyMatch(pattern: query, in: item.title) {
            bestScore = min(bestScore, result.score)
        }

        for keyword in item.keywords {
            if let result = FuzzySearch.fuzzyMatch(pattern: query, in: keyword) {
                bestScore = min(bestScore, result.score * 0.6 + 0.4)
            }
        }

        if let subtitle = item.subtitle,
            let result = FuzzySearch.fuzzyMatch(pattern: query, in: subtitle)
        {
            bestScore = min(bestScore, result.score * 0.8 + 0.2)
        }

        guard bestScore < threshold else { return nil }

        if let recentIndex = recentIds.firstIndex(of: item.id) {
            let boost = 0.1 * (1.0 - Double(recentIndex) / 8.0)
            bestScore = max(0.0, bestScore - boost)
        }

        return bestScore
    }

    /// Filter and sort items by fuzzy match score against a query.
    /// Returns items that pass the threshold, sorted best-first.
    static func filter(
        items: [CommandBarItem],
        query: String,
        recentIds: [String] = [],
        threshold: Double = FuzzySearch.defaultThreshold,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder? = nil
    ) -> [CommandBarItem] {
        let clock = ContinuousClock()
        let start = clock.now
        let filteredItems: [CommandBarItem]
        if query.isEmpty {
            filteredItems = items
        } else {
            filteredItems =
                items
                .compactMap { item -> (CommandBarItem, Double)? in
                    guard
                        let score = scoreItem(
                            item,
                            query: query,
                            recentIds: recentIds,
                            threshold: threshold
                        )
                    else {
                        return nil
                    }
                    return (item, score)
                }
                .sorted { $0.1 < $1.1 }
                .map(\.0)
        }

        performanceTraceRecorder?.recordDuration(
            .commandBarFilter,
            duration: start.duration(to: clock.now),
            attributes: [
                "agentstudio.performance.commandbar.input.count": .int(items.count),
                "agentstudio.performance.commandbar.result.count": .int(filteredItems.count),
                "agentstudio.performance.commandbar.query_character.count": .int(query.count),
            ]
        )
        return filteredItems
    }
}
