import Foundation
import os

private let commandBarPaneKeywordLogger = Logger(subsystem: "com.agentstudio", category: "CommandBarPaneKeywords")

extension CommandBarDataSource {
    static func keywordsForTab(
        _ tab: Tab,
        store: WorkspaceStore,
        repoCache: RepoCacheAtom
    ) -> [String] {
        var keywords = ["tab", "switch", tab.name]
        keywords.append(contentsOf: tab.arrangements.filter { !$0.isDefault }.map(\.name))

        for paneId in tab.activePaneIds {
            guard let pane = store.paneAtom.pane(paneId) else {
                commandBarPaneKeywordLogger.warning(
                    "Tab keyword indexing skipped missing pane \(paneId.uuidString, privacy: .public)"
                )
                continue
            }
            keywords.append(contentsOf: keywordsForPane(pane, store: store, repoCache: repoCache))
            keywords.append(pane.title)
        }

        return stableUniqueKeywords(keywords)
    }

    static func stableUniqueKeywords(_ keywords: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for keyword in keywords {
            let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.localizedLowercase
            if seen.insert(key).inserted {
                result.append(trimmed)
            }
        }

        return result
    }
}
