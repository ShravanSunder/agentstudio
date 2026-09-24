import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioBridge

/// The native half of a Files collection search against a real collection
/// source: the page call is scripted, the fence and document resolution are
/// the production ones.
@MainActor
@Suite("Bridge Files collection search exchange")
struct BridgeFilesSearchExchangeTests {
    private let criteria = BridgeFilesSearchCriteria(
        searchText: "app",
        mode: .text,
        scope: .allMembersAndOpenedDocuments,
        limit: 20
    )

    @Test("an answer from the live source resolves every match to its document")
    func liveAnswerResolvesMatches() async throws {
        // Arrange
        let (fixture, collection) = try await openCollection()
        defer { fixture.remove() }
        let fence = try #require(await collection.searchFence())
        let exchange = scriptedExchange(collection) { requestId in
            try pageAnswer(
                requestId: requestId,
                fence: fence,
                matches: [
                    .init(displayPath: "alpha/src/app.ts", memberWorktreeId: fixture.alpha.worktreeId),
                    .init(displayPath: "Open Files/notes.md", memberWorktreeId: nil),
                ]
            )
        }

        // Act
        let outcome = await exchange.run(criteria, requestId: "search-1")

        // Assert
        let alphaRoot = DarwinFSEventPathCanonicalizer.canonicalURL(fixture.alphaRoot).path
        let alphaApp = try #require(BridgeDocumentLocation(canonicalPath: "\(alphaRoot)/src/app.ts"))
        #expect(
            outcome
                == .results(
                    BridgeFilesSearchResults(
                        matches: [
                            BridgeFilesSearchMatch(
                                displayPath: "alpha/src/app.ts",
                                location: alphaApp,
                                memberWorktreeId: fixture.alpha.worktreeId,
                                memberRelativePath: "src/app.ts"
                            ),
                            BridgeFilesSearchMatch(
                                displayPath: "Open Files/notes.md",
                                location: fixture.notesLocation,
                                memberWorktreeId: nil,
                                memberRelativePath: nil
                            ),
                        ],
                        totalMatchCount: 2,
                        truncated: false,
                        complete: true,
                        unavailableMemberWorktreeIds: []
                    )
                )
        )
    }

    @Test("a membership change while the page searches makes the answer stale")
    func membershipChangeDuringSearchIsStale() async throws {
        // Arrange
        let (fixture, collection) = try await openCollection()
        defer { fixture.remove() }
        let fence = try #require(await collection.searchFence())
        let exchange = scriptedExchange(collection) { requestId in
            try await collection.applyMembership(members: [fixture.alpha], openedDocuments: [])
            return try pageAnswer(
                requestId: requestId,
                fence: fence,
                matches: [.init(displayPath: "alpha/src/app.ts", memberWorktreeId: fixture.alpha.worktreeId)]
            )
        }

        // Act
        let outcome = await exchange.run(criteria, requestId: "search-1")

        // Assert
        #expect(outcome == .unavailable(.sourceChanged))
    }

    @Test("an answer attributed with an older member layout is stale even when native did not move")
    func lateWorkerLayoutIsStale() async throws {
        // Arrange
        let (fixture, collection) = try await openCollection()
        defer { fixture.remove() }
        let olderFence = try #require(await collection.searchFence())
        try await collection.applyMembership(
            members: [fixture.alpha],
            openedDocuments: [fixture.notesLocation]
        )
        let exchange = scriptedExchange(collection) { requestId in
            try pageAnswer(
                requestId: requestId,
                fence: olderFence,
                matches: [.init(displayPath: "alpha/src/app.ts", memberWorktreeId: fixture.alpha.worktreeId)]
            )
        }

        // Act
        let outcome = await exchange.run(criteria, requestId: "search-1")

        // Assert
        #expect(outcome == .unavailable(.sourceChanged))
    }

    @Test("a match the worker attributes to another member is refused, not relabeled")
    func misattributedMatchIsStale() async throws {
        // Arrange
        let (fixture, collection) = try await openCollection()
        defer { fixture.remove() }
        let fence = try #require(await collection.searchFence())
        let exchange = scriptedExchange(collection) { requestId in
            try pageAnswer(
                requestId: requestId,
                fence: fence,
                matches: [.init(displayPath: "alpha/src/app.ts", memberWorktreeId: fixture.beta.worktreeId)]
            )
        }

        // Act
        let outcome = await exchange.run(criteria, requestId: "search-1")

        // Assert
        #expect(outcome == .unavailable(.sourceChanged))
    }

    @Test("cancelling while the page searches reports cancelled")
    func cancelledSearchReportsCancelled() async throws {
        // Arrange
        let (fixture, collection) = try await openCollection()
        defer { fixture.remove() }
        let (pageEntered, pageEnteredContinuation) = AsyncStream.makeStream(of: Void.self)
        let exchange = BridgeFilesSearchExchange(
            source: collection,
            callPage: { _ in
                pageEnteredContinuation.yield()
                let (unanswered, unansweredContinuation) = AsyncStream.makeStream(of: Void.self)
                for await _ in unanswered {}
                unansweredContinuation.finish()
                throw CancellationError()
            },
            pageSessionIsUnchanged: { true }
        )
        let search = Task { @MainActor in await exchange.run(criteria, requestId: "search-1") }
        for await _ in pageEntered { break }

        // Act
        search.cancel()

        // Assert
        #expect(await search.value == .unavailable(.cancelled))
    }

    @Test("a page without a handler, or answering another request, fails instead of waiting")
    func unansweredPageFails() async throws {
        // Arrange
        let (fixture, collection) = try await openCollection()
        defer { fixture.remove() }
        let fence = try #require(await collection.searchFence())
        let noHandler = scriptedExchange(collection) { requestId in
            #"{"requestId":"\#(requestId)","answer":null}"#
        }
        let otherRequest = scriptedExchange(collection) { _ in
            try pageAnswer(requestId: "another-request", fence: fence, matches: [])
        }

        // Act
        let missingHandler = await noHandler.run(criteria, requestId: "search-1")
        let misrouted = await otherRequest.run(criteria, requestId: "search-2")

        // Assert
        #expect(missingHandler == .unavailable(.failed))
        #expect(misrouted == .unavailable(.failed))
    }

    @Test("a collection without an accepted source is not searched")
    func unopenedCollectionHasNoLivePage() async throws {
        // Arrange
        let fixture = try await BridgeFileCollectionTestFixture()
        defer { fixture.remove() }
        let collection = fixture.makeCollection(members: [fixture.alpha], openedDocuments: [])
        let pageCalls = PageCallRecorder()
        let exchange = BridgeFilesSearchExchange(
            source: collection,
            callPage: { script in
                pageCalls.scripts.append(script)
                return nil
            },
            pageSessionIsUnchanged: { true }
        )

        // Act
        let outcome = await exchange.run(criteria, requestId: "search-1")

        // Assert
        #expect(outcome == .unavailable(.noLivePage))
        #expect(pageCalls.scripts.isEmpty)
    }

    @Test("search text travels as data, never as script source")
    func searchTextIsNotSplicedIntoScript() throws {
        // Arrange
        let hostile = BridgeFilesSearchCriteria(
            searchText: "'); window.hacked = true; ('",
            mode: .regex,
            scope: .member(worktreeId: UUIDv7.generate()),
            limit: 10_000
        )

        // Act
        let script = try BridgeFilesSearchExchange.pageScript(requestId: "search-1", criteria: hostile)

        // Assert
        #expect(script.contains(#""searchText":"'); window.hacked = true; ('""#))
        #expect(script.contains(#""limit":500"#), "the limit is clamped to the worker's bound")
    }

    // MARK: - Helpers

    private func openCollection() async throws -> (BridgeFileCollectionTestFixture, BridgeFileCollectionSource) {
        let fixture = try await BridgeFileCollectionTestFixture()
        let collection = fixture.makeCollection(
            members: [fixture.alpha, fixture.beta],
            openedDocuments: [fixture.notesLocation]
        )
        let collector = ProductFileMetadataEventCollector()
        try await collection.open(
            subscription: fixture.snapshot(revision: 0, foregroundPaths: []),
            productAdmission: fixture.productAdmission.context,
            foregroundWorkAdmission: fixture.foregroundWorkAdmission
        ) { event in await collector.append(event) }
        return (fixture, collection)
    }

    private func scriptedExchange(
        _ collection: BridgeFileCollectionSource,
        answer: @escaping @MainActor (_ requestId: String) async throws -> String
    ) -> BridgeFilesSearchExchange {
        BridgeFilesSearchExchange(
            source: collection,
            callPage: { script in try await answer(try requestId(in: script)) },
            pageSessionIsUnchanged: { true }
        )
    }
}

private struct PageAnswerMatch: Encodable {
    let displayPath: String
    let documentLocation: String? = nil
    let fileId = "file-id"
    let memberWorktreeId: String?

    init(displayPath: String, memberWorktreeId: UUID?) {
        self.displayPath = displayPath
        self.memberWorktreeId = memberWorktreeId?.uuidString.lowercased()
    }
}

private struct PageAnswer: Encodable {
    struct Answer: Encodable {
        struct Source: Encodable {
            let sourceGeneration: Int
            let sourceId: String
        }

        let complete = true
        let kind = "matches"
        let matches: [PageAnswerMatch]
        let membershipRevision: Int
        let source: Source
        let totalMatchCount: Int
        let truncated = false
    }

    let answer: Answer
    let requestId: String
}

private func pageAnswer(
    requestId: String,
    fence: BridgeFileCollectionSearchFence,
    matches: [PageAnswerMatch]
) throws -> String {
    let answer = PageAnswer(
        answer: .init(
            matches: matches,
            membershipRevision: fence.membershipRevision,
            source: .init(
                sourceGeneration: fence.source.subscriptionGeneration,
                sourceId: fence.source.sourceId
            ),
            totalMatchCount: matches.count
        ),
        requestId: requestId
    )
    guard let json = String(bytes: try JSONEncoder().encode(answer), encoding: .utf8) else {
        throw PageScriptWithoutRequestId()
    }
    return json
}

@MainActor
private final class PageCallRecorder {
    var scripts: [String] = []
}

private struct PageScriptWithoutRequestId: Error {}

/// The page request is a JSON literal inside the script; read its id back.
private func requestId(in script: String) throws -> String {
    guard let start = script.range(of: #""requestId":""#)?.upperBound,
        let end = script[start...].firstIndex(of: "\"")
    else { throw PageScriptWithoutRequestId() }
    return String(script[start..<end])
}
