import AgentStudioInfrastructure
import Dispatch
import Foundation
import GRDB

/// Answers searches on its own actor executor from one replaceable in-memory index.
package actor SearchService: SearchServicing {
    private var index: SearchIndex?
    private var installedGeneration: SearchDocumentGeneration?
    private let makeDatabaseQueue: @Sendable () throws -> DatabaseQueue
    private let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?

    package init(performanceTraceRecorder: AgentStudioPerformanceTraceRecorder? = nil) {
        makeDatabaseQueue = { try DatabaseQueue() }
        self.performanceTraceRecorder = performanceTraceRecorder
    }

    init(
        makeDatabaseQueue: @escaping @Sendable () throws -> DatabaseQueue,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder? = nil
    ) {
        self.makeDatabaseQueue = makeDatabaseQueue
        self.performanceTraceRecorder = performanceTraceRecorder
    }

    package func search(_ request: SearchRequest) -> SearchResultSet {
        let actorStarted = DispatchTime.now().uptimeNanoseconds
        if let submittedAt = request.submittedAtNanoseconds {
            recordStage(
                "queue_wait",
                durationNanoseconds: actorStarted >= submittedAt ? actorStarted - submittedAt : 0,
                request: request
            )
        }
        let answer = searchResult(request)
        let actorFinished = DispatchTime.now().uptimeNanoseconds
        recordStage(
            "actor_work",
            durationNanoseconds: actorFinished >= actorStarted ? actorFinished - actorStarted : 0,
            request: request
        )
        return SearchResultSet(
            sequence: answer.sequence,
            generation: answer.generation,
            groups: answer.groups,
            outcome: answer.outcome,
            actorFinishedAtNanoseconds: actorFinished
        )
    }

    package func install(_ documentSet: SearchDocumentSet) {
        guard installedGeneration == nil || documentSet.generation > installedGeneration! else { return }
        do {
            try installGeneration(documentSet)
        } catch {
            index = nil
            installedGeneration = nil
            do {
                try installGeneration(documentSet)
            } catch {
                index = nil
                installedGeneration = nil
            }
        }
    }

    private func installGeneration(_ documentSet: SearchDocumentSet) throws {
        if index == nil {
            index = try SearchIndex(databaseQueue: makeDatabaseQueue())
        }
        try index?.install(documentSet)
        installedGeneration = documentSet.generation
    }

    private func searchResult(_ request: SearchRequest) -> SearchResultSet {
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

    private func recordStage(
        _ stage: String,
        durationNanoseconds: UInt64,
        request: SearchRequest
    ) {
        performanceTraceRecorder?.recordDuration(
            .commandBarSearch,
            duration: .nanoseconds(Int64(clamping: durationNanoseconds)),
            attributes: [
                "agentstudio.performance.commandbar.search.stage": .string(stage),
                "agentstudio.performance.commandbar.search.sequence": .int(Int(clamping: request.sequence.value)),
                "agentstudio.performance.commandbar.search.generation": .int(
                    Int(clamping: request.documentSet.generation.value)),
                "agentstudio.performance.commandbar.item.count": .int(request.documentSet.documents.count),
                "agentstudio.performance.commandbar.query_character.count": .int(request.text.count),
            ]
        )
    }

    private func answer(_ request: SearchRequest) throws -> SearchResultSet {
        if installedGeneration != request.documentSet.generation {
            try installGeneration(request.documentSet)
        }
        guard let index else {
            return result(for: request, groups: [], outcome: .degraded(.databaseUnavailable))
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
    private var installedDocuments: [SearchItemId: SearchDocument] = [:]

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
        var nextDocuments: [SearchItemId: SearchDocument] = [:]
        for document in documentSet.documents where nextDocuments[document.itemId] == nil {
            nextDocuments[document.itemId] = document
        }
        let removedOrChangedIds = installedDocuments.compactMap { itemId, old -> SearchItemId? in
            guard let new = nextDocuments[itemId], Self.sameContent(old, new) else { return itemId }
            return nil
        }
        try databaseQueue.write { database in
            for itemId in removedOrChangedIds {
                guard
                    let row = try Row.fetchOne(
                        database,
                        sql: "SELECT rowid, folded_title, folded_fields FROM search_document WHERE item_id = ?",
                        arguments: [itemId.rawValue]
                    )
                else { continue }
                try database.execute(
                    sql: """
                        INSERT INTO search_document_fts
                            (search_document_fts, rowid, folded_title, folded_fields)
                        VALUES ('delete', ?, ?, ?)
                        """,
                    arguments: [row["rowid"], row["folded_title"], row["folded_fields"]]
                )
                try database.execute(sql: "DELETE FROM search_document WHERE rowid = ?", arguments: [row["rowid"]])
            }

            for document in nextDocuments.values {
                if let old = installedDocuments[document.itemId], Self.sameContent(old, document) {
                    continue
                }
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
        installedDocuments = nextDocuments
    }

    private static func sameContent(_ lhs: SearchDocument, _ rhs: SearchDocument) -> Bool {
        lhs.kind == rhs.kind && lhs.groupId == rhs.groupId && lhs.title == rhs.title && lhs.fields == rhs.fields
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
