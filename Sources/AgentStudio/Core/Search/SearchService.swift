import Foundation
import GRDB

/// Answers searches on its own actor executor from one replaceable in-memory index.
package actor SearchService: SearchServicing {
    private var index: SearchIndex?
    private var installedGeneration: SearchDocumentGeneration?
    private let makeDatabaseQueue: @Sendable () throws -> DatabaseQueue

    package init() {
        makeDatabaseQueue = { try DatabaseQueue() }
    }

    init(makeDatabaseQueue: @escaping @Sendable () throws -> DatabaseQueue) {
        self.makeDatabaseQueue = makeDatabaseQueue
    }

    package func search(_ request: SearchRequest) -> SearchResultSet {
        if Task.isCancelled {
            return result(for: request, groups: [], outcome: .obsolete)
        }
        if let installedGeneration, request.documentSet.generation < installedGeneration {
            return result(for: request, groups: [], outcome: .obsolete)
        }

        do {
            return try answer(request)
        } catch {
            index = nil
            installedGeneration = nil
            do {
                return try answer(request)
            } catch {
                index = nil
                installedGeneration = nil
                return result(for: request, groups: [], outcome: .degraded(.databaseUnavailable))
            }
        }
    }

    private func answer(_ request: SearchRequest) throws -> SearchResultSet {
        if index == nil {
            index = try SearchIndex(databaseQueue: makeDatabaseQueue())
        }
        guard let index else {
            return result(for: request, groups: [], outcome: .degraded(.databaseUnavailable))
        }

        if installedGeneration != request.documentSet.generation {
            try index.install(request.documentSet)
            installedGeneration = request.documentSet.generation
        }

        let foldedQuery = Self.fold(request.text)
        let rows = try index.matchingRows(query: foldedQuery)
        var recentRanks: [String: Int] = [:]
        for (position, itemId) in request.recentItemIds.enumerated() where recentRanks[itemId.rawValue] == nil {
            recentRanks[itemId.rawValue] = position
        }
        var matchesByGroup: [String: [SearchRankedMatch]] = [:]
        var unreadableRow = false

        for row in rows {
            guard let itemId = SearchItemId(row.itemId), SearchKind(rawValue: row.kind) != nil else {
                unreadableRow = true
                continue
            }
            let match = SearchMatch(
                itemId: itemId,
                titleMatch: Self.titleMatch(query: request.text, title: row.title)
            )
            matchesByGroup[row.groupId, default: []].append(
                SearchRankedMatch(
                    match: match,
                    tier: Self.rankTier(query: foldedQuery, title: row.foldedTitle),
                    recentRank: recentRanks[row.itemId] ?? Int.max,
                    id: row.itemId
                ))
        }

        let shortQuery = request.text.count < 3
        let groups = request.documentSet.groups
            .sorted { $0.priority < $1.priority }
            .compactMap { group -> SearchResultGroup? in
                guard var entries = matchesByGroup[group.id], !entries.isEmpty else { return nil }
                entries.sort { lhs, rhs in
                    if shortQuery, lhs.recentRank != rhs.recentRank {
                        return lhs.recentRank < rhs.recentRank
                    }
                    if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
                    if lhs.recentRank != rhs.recentRank { return lhs.recentRank < rhs.recentRank }
                    return lhs.id < rhs.id
                }
                return SearchResultGroup(groupId: group.id, matches: entries.map(\.match))
            }
        return result(
            for: request,
            groups: groups,
            outcome: unreadableRow ? .degraded(.unreadableRow) : .answered
        )
    }

    private func result(
        for request: SearchRequest,
        groups: [SearchResultGroup],
        outcome: SearchResultOutcome
    ) -> SearchResultSet {
        SearchResultSet(
            sequence: request.sequence,
            generation: request.documentSet.generation,
            groups: groups,
            outcome: outcome
        )
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
    }

    private static func rankTier(query: String, title: String) -> Int {
        if title.hasPrefix(query) { return 0 }
        guard let range = title.range(of: query) else { return 3 }
        if range.lowerBound == title.startIndex { return 0 }
        let precedingIndex = title.index(before: range.lowerBound)
        return title[precedingIndex].isLetter || title[precedingIndex].isNumber ? 2 : 1
    }

    private static func titleMatch(query: String, title: String) -> Range<Int>? {
        guard let range = title.range(of: query, options: [.caseInsensitive, .widthInsensitive]) else { return nil }
        let start = title.distance(from: title.startIndex, to: range.lowerBound)
        let end = title.distance(from: title.startIndex, to: range.upperBound)
        return start..<end
    }
}

private struct SearchIndexedRow {
    let itemId: String
    let kind: String
    let groupId: String
    let title: String
    let foldedTitle: String
}

private struct SearchRankedMatch {
    let match: SearchMatch
    let tier: Int
    let recentRank: Int
    let id: String
}

/// The sole SQLite writer. It is reachable only within the service actor.
private final class SearchIndex {
    private let databaseQueue: DatabaseQueue

    init(databaseQueue: DatabaseQueue) throws {
        self.databaseQueue = databaseQueue
        try databaseQueue.write { database in
            try database.execute(
                sql: """
                    CREATE TABLE search_document (
                        item_id TEXT, kind TEXT, group_id TEXT, title TEXT,
                        folded_title TEXT, folded_fields TEXT
                    )
                    """)
            try database.execute(sql: "CREATE INDEX search_document_item_id ON search_document(item_id)")
            try database.execute(
                sql: """
                    CREATE VIRTUAL TABLE search_document_fts USING fts5(
                        folded_title, folded_fields,
                        content='search_document', content_rowid='rowid', tokenize='trigram'
                    )
                    """)
        }
    }

    func install(_ documentSet: SearchDocumentSet) throws {
        try databaseQueue.write { database in
            let existingRows = try Row.fetchAll(
                database,
                sql: "SELECT rowid, folded_title, folded_fields FROM search_document"
            )
            for row in existingRows {
                try database.execute(
                    sql: """
                        INSERT INTO search_document_fts
                            (search_document_fts, rowid, folded_title, folded_fields)
                        VALUES ('delete', ?, ?, ?)
                        """,
                    arguments: [row["rowid"], row["folded_title"], row["folded_fields"]]
                )
            }
            try database.execute(sql: "DELETE FROM search_document")

            var installedIds: Set<SearchItemId> = []
            for document in documentSet.documents where installedIds.insert(document.itemId).inserted {
                let foldedTitle = Self.fold(document.title)
                let foldedFields = document.fields.map(Self.fold).joined(separator: "\n")
                try database.execute(
                    sql: """
                        INSERT INTO search_document
                            (item_id, kind, group_id, title, folded_title, folded_fields)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        document.itemId.rawValue, document.kind.rawValue, document.groupId,
                        document.title, foldedTitle, foldedFields,
                    ]
                )
                let rowId = database.lastInsertedRowID
                try database.execute(
                    sql: """
                        INSERT INTO search_document_fts (rowid, folded_title, folded_fields)
                        VALUES (?, ?, ?)
                        """,
                    arguments: [rowId, foldedTitle, foldedFields]
                )
            }
        }
    }

    func matchingRows(query: String) throws -> [SearchIndexedRow] {
        try databaseQueue.read { database in
            let rows: [Row]
            if query.count < 3 {
                let escapedQuery = Self.escapeLike(query)
                let pattern = "%\(escapedQuery)%"
                rows = try Row.fetchAll(
                    database,
                    sql: """
                        SELECT item_id, kind, group_id, title, folded_title
                        FROM search_document
                        WHERE folded_title LIKE ? ESCAPE '\\'
                            OR folded_fields LIKE ? ESCAPE '\\'
                        """,
                    arguments: [pattern, pattern]
                )
            } else {
                let quotedQuery = "\"\(query.replacingOccurrences(of: "\"", with: "\"\""))\""
                rows = try Row.fetchAll(
                    database,
                    sql: """
                        SELECT d.item_id, d.kind, d.group_id, d.title, d.folded_title
                        FROM search_document AS d
                        JOIN search_document_fts AS f ON f.rowid = d.rowid
                        WHERE search_document_fts MATCH ?
                        """,
                    arguments: [quotedQuery]
                )
            }
            return rows.map { row in
                SearchIndexedRow(
                    itemId: row["item_id"],
                    kind: row["kind"],
                    groupId: row["group_id"],
                    title: row["title"],
                    foldedTitle: row["folded_title"]
                )
            }
        }
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
    }

    private static func escapeLike(_ query: String) -> String {
        query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
