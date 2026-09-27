import GRDB
import Synchronization
import Testing

@testable import AgentStudioCore

@Suite("SearchService")
struct SearchServiceTests {
    @Test("in-memory GRDB supports quoted FTS5 trigram substrings")
    func inMemoryTrigramPlatformGuard() throws {
        let databaseQueue = try DatabaseQueue()
        try databaseQueue.write { database in
            try database.execute(
                sql: "CREATE VIRTUAL TABLE search_guard USING fts5(title, tokenize='trigram')"
            )
            try database.execute(sql: "INSERT INTO search_guard (title) VALUES (?)", arguments: ["agent-vm.oauth"])
        }

        let matches = try databaseQueue.read { database in
            try Int.fetchOne(
                database, sql: "SELECT count(*) FROM search_guard WHERE search_guard MATCH ?", arguments: ["\"vm.oa\""])
        }
        #expect(matches == 1)
    }

    @Test("short and indexed queries share case-insensitive substring semantics")
    func literalSubstringQueries() async {
        let service = SearchService()
        let documents = [
            document("oauth", title: "agent-vm.oauth"),
            document("branch", title: "Branch", fields: ["feature/oauth"]),
            document("school", title: "École"),
            document("percent", title: "percent%_\\path"),
            document("quote", title: "quoted\"name"),
        ]
        let documentSet = set(1, documents: documents)

        for (query, expectedIds) in [
            ("vm.oa", ["oauth"]),
            ("feature/o", ["branch"]),
            ("agvmoa", []),
            ("é", ["school"]),
            ("ÉC", ["school"]),
            ("ÉCO", ["school"]),
            ("%", ["percent"]),
            ("_", ["percent"]),
            ("\\", ["percent"]),
            ("\"", ["quote"]),
            ("OAUTH", ["oauth", "branch"]),
        ] {
            let result = await service.search(request(1, text: query, set: documentSet))
            #expect(result.outcome == .answered)
            #expect(ids(in: result) == expectedIds, "query: \(query)")
        }
    }

    @Test("short query recency leads, indexed query tiers lead")
    func rankingTable() async {
        let service = SearchService()
        let documentSet = set(
            1,
            documents: [
                document("prefix", title: "oauth docs"),
                document("word", title: "new oauth docs"),
                document("contains", title: "neoauth docs"),
                document("field", title: "unrelated", fields: ["oauth"]),
            ])
        let recents = [SearchItemId("field")!, SearchItemId("contains")!]

        let shortResult = await service.search(request(1, text: "oa", set: documentSet, recents: recents))
        #expect(ids(in: shortResult) == ["field", "contains", "prefix", "word"])

        let indexedResult = await service.search(request(2, text: "oauth", set: documentSet, recents: recents))
        #expect(ids(in: indexedResult) == ["prefix", "word", "contains", "field"])
    }

    @Test("generation install, duplicate ids and reverse admission keep the newest set")
    func generationCurrentness() async {
        let service = SearchService()
        let firstSet = set(1, documents: [document("old", title: "oauth old")])
        let secondSet = set(
            2,
            documents: [
                document("new", title: "oauth new"),
                document("new", title: "oauth duplicate"),
            ])

        let original = await service.search(request(1, text: "oauth", set: firstSet))
        #expect(ids(in: original) == ["old"])

        let newer = await service.search(request(2, text: "oauth", set: secondSet))
        #expect(ids(in: newer) == ["new"])

        let obsolete = await service.search(request(1, text: "oauth", set: firstSet))
        #expect(obsolete.outcome == .obsolete)
        #expect(obsolete.groups.isEmpty)

        let again = await service.search(request(3, text: "oauth", set: secondSet))
        #expect(ids(in: again) == ["new"])
    }

    @Test("a cancelled first request for a generation cannot poison its next request")
    func cancelledRequestKeepsGenerationAvailable() async {
        let service = SearchService()
        let firstSet = set(1, documents: [document("first", title: "first")])
        let secondSet = set(2, documents: [document("second", title: "second")])
        _ = await service.search(request(1, text: "first", set: firstSet))

        let cancelledRequest = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await service.search(request(2, text: "second", set: secondSet))
        }
        let cancelledAnswer = await cancelledRequest.value
        #expect(cancelledAnswer.outcome == .obsolete)

        let laterRequest = await service.search(request(3, text: "second", set: secondSet))
        #expect(laterRequest.outcome == .answered)
        #expect(ids(in: laterRequest) == ["second"])
    }

    @Test("groups follow declarations, omit empty groups and accept another kind")
    func declaredGroupsAndKinds() async {
        let service = SearchService()
        let documentSet = SearchDocumentSet(
            generation: SearchDocumentGeneration(1),
            groups: [
                SearchGroup(id: "Repos", priority: 1),
                SearchGroup(id: "Worktrees", priority: 2),
                SearchGroup(id: "Panes", priority: 3),
                SearchGroup(id: "Other", priority: 4),
            ],
            documents: [
                document("worktree", kind: .worktree, group: "Worktrees", title: "oauth checkout"),
                document("repo", kind: .repo, group: "Repos", title: "oauth repo"),
                document("future", kind: .other, group: "Other", title: "oauth future"),
            ]
        )

        let result = await service.search(request(1, text: "oauth", set: documentSet))
        #expect(result.groups.map(\.groupId) == ["Repos", "Worktrees", "Other"])
        #expect(ids(in: result) == ["repo", "worktree", "future"])
    }

    @Test("a failed index is recreated from the carried document set")
    func databaseFailureRecreatesIndex() async throws {
        let firstQueue = try DatabaseQueue()
        let creationCount = Mutex(0)
        let service = SearchService(makeDatabaseQueue: {
            let call = creationCount.withLock { count -> Int in
                count += 1
                return count
            }
            return call == 1 ? firstQueue : try DatabaseQueue()
        })
        let documentSet = set(1, documents: [document("oauth", title: "oauth")])

        let first = await service.search(request(1, text: "oauth", set: documentSet))
        #expect(ids(in: first) == ["oauth"])
        try firstQueue.close()

        let recovered = await service.search(request(2, text: "oauth", set: documentSet))
        #expect(recovered.outcome == .answered)
        #expect(ids(in: recovered) == ["oauth"])
        #expect(creationCount.withLock { $0 } == 2)
    }

    @Test("a second database failure returns a degraded empty answer")
    func repeatedDatabaseFailureDegrades() async {
        let service = SearchService(makeDatabaseQueue: { throw SearchFixtureError.unavailable })
        let result = await service.search(
            request(
                1, text: "oauth",
                set: set(
                    1,
                    documents: [
                        document("oauth", title: "oauth")
                    ])))

        #expect(result.outcome == .degraded(.databaseUnavailable))
        #expect(result.groups.isEmpty)
    }

    @Test("an unknown stored kind is dropped and marked degraded")
    func unknownKindFailsClosed() async throws {
        let queue = try DatabaseQueue()
        let service = SearchService(makeDatabaseQueue: { queue })
        let documentSet = set(1, documents: [document("oauth", title: "oauth")])
        let first = await service.search(request(1, text: "oauth", set: documentSet))
        #expect(first.outcome == .answered)
        try await queue.write { database in
            try database.execute(sql: "UPDATE search_document SET kind = 'unexpected' WHERE item_id = 'oauth'")
        }

        let result = await service.search(request(2, text: "oauth", set: documentSet))
        #expect(result.outcome == .degraded(.unreadableRow))
        #expect(result.groups.isEmpty)
    }

    @Test("title match ranges use character offsets in the displayed title")
    func titleRanges() async {
        let service = SearchService()
        let result = await service.search(
            request(
                1, text: "vm.oa",
                set: set(
                    1,
                    documents: [
                        document("oauth", title: "agent-vm.oauth")
                    ])))

        #expect(result.groups.first?.matches.first?.titleMatch == 6..<11)
    }

    private enum SearchFixtureError: Error {
        case unavailable
    }

    private func document(
        _ id: String,
        kind: SearchKind = .repo,
        group: String = "Repos",
        title: String,
        fields: [String] = []
    ) -> SearchDocument {
        SearchDocument(itemId: SearchItemId(id)!, kind: kind, groupId: group, title: title, fields: fields)
    }

    private func set(_ generation: UInt64, documents: [SearchDocument]) -> SearchDocumentSet {
        SearchDocumentSet(
            generation: SearchDocumentGeneration(generation),
            groups: [SearchGroup(id: "Repos", priority: 1)],
            documents: documents
        )
    }

    private func request(
        _ sequence: UInt64,
        text: String,
        set: SearchDocumentSet,
        recents: [SearchItemId] = []
    ) -> SearchRequest {
        SearchRequest(
            sequence: SearchRequestSequence(sequence),
            text: text,
            recentItemIds: recents,
            documentSet: set
        )
    }

    private func ids(in result: SearchResultSet) -> [String] {
        result.groups.flatMap(\.matches).map { $0.itemId.rawValue }
    }
}
