import AgentStudioCore
import Foundation

/// What a Files collection search covers. Narrowing never changes membership.
package enum BridgeFilesSearchScope: Equatable, Sendable {
    case allMembersAndOpenedDocuments
    case member(worktreeId: UUID)
    case openedDocuments
}

/// A search of the receiving Bridge's Files collection, matched by the tree
/// search's own text or regex semantics against collection paths and, for
/// opened documents, their real locations.
package struct BridgeFilesSearchCriteria: Equatable, Sendable {
    package enum Mode: String, Sendable {
        case text
        case regex
    }

    /// The worker's answer bound (`BRIDGE_FILE_COLLECTION_SEARCH_MAXIMUM_LIMIT`).
    package static let maximumLimit = 500

    package let searchText: String
    package let mode: Mode
    package let scope: BridgeFilesSearchScope
    package let limit: Int

    package init(searchText: String, mode: Mode, scope: BridgeFilesSearchScope, limit: Int) {
        self.searchText = searchText
        self.mode = mode
        self.scope = scope
        self.limit = min(max(limit, 1), Self.maximumLimit)
    }
}

/// One listed file matching a search, resolved to the document it names.
package struct BridgeFilesSearchMatch: Equatable, Sendable {
    package let displayPath: String
    package let location: BridgeDocumentLocation
    /// Nil for an opened document outside every member.
    package let memberWorktreeId: UUID?
    package let memberRelativePath: String?
}

package struct BridgeFilesSearchResults: Equatable, Sendable {
    /// Matches in collection order, at most the requested limit.
    package let matches: [BridgeFilesSearchMatch]
    package let totalMatchCount: Int
    package let truncated: Bool
    /// False until the initial tree finished, so a short result is not yet
    /// proof that a file is absent.
    package let complete: Bool
    /// Members whose source failed; their files are not searched.
    package let unavailableMemberWorktreeIds: [UUID]
}

package enum BridgeFilesSearchUnavailability: Equatable, Sendable {
    /// The page has no completed bridge handshake or no accepted Files source.
    case noLivePage
    /// The source or its membership changed while the search ran.
    case sourceChanged
    /// The caller stopped waiting.
    case cancelled
    /// The page did not answer this request, or its worker refused it.
    case failed
}

package enum BridgeFilesSearchOutcome: Equatable, Sendable {
    case results(BridgeFilesSearchResults)
    case invalidPattern(String)
    case unavailable(BridgeFilesSearchUnavailability)
}

private struct BridgeFilesSearchPageRequest: Encodable {
    struct Criteria: Encodable {
        struct Scope: Encodable {
            let kind: String
            let worktreeId: String?
        }

        let limit: Int
        let scope: Scope
        let searchMode: String
        let searchText: String
    }

    let criteria: Criteria
    let requestId: String
}

private struct BridgeFilesSearchProbe: Decodable {
    struct Answer: Decodable {
        struct Match: Decodable {
            let displayPath: String
            let memberWorktreeId: String?
        }

        struct Source: Decodable {
            let sourceGeneration: Int
            let sourceId: String
        }

        let kind: String
        let complete: Bool?
        let matches: [Match]?
        let membershipRevision: Int?
        let searchError: String?
        let source: Source?
        let totalMatchCount: Int?
        let truncated: Bool?
    }

    let answer: Answer?
    let requestId: String
}

/// One search round trip between native and the page's comm worker. The
/// page call is injected so the exchange can be exercised against a real
/// collection source without a WebView; the controller supplies
/// `WebPage.callJavaScript` and its page-session check.
@MainActor
struct BridgeFilesSearchExchange {
    let source: BridgeFileCollectionSource
    let callPage: @MainActor (_ script: String) async throws -> Any?
    /// Whether the same page session and worker instance are still installed.
    let pageSessionIsUnchanged: @MainActor () async -> Bool

    /// The answer counts only while the same page session, worker, source
    /// generation and membership revision stay installed; anything else is
    /// unavailable rather than a guessed result.
    func run(_ criteria: BridgeFilesSearchCriteria, requestId: String) async -> BridgeFilesSearchOutcome {
        guard let fenceBefore = await source.searchFence() else {
            return .unavailable(.noLivePage)
        }
        let result: Any?
        do {
            result = try await callPage(try Self.pageScript(requestId: requestId, criteria: criteria))
        } catch {
            return Task.isCancelled ? .unavailable(.cancelled) : .unavailable(.failed)
        }
        guard !Task.isCancelled else { return .unavailable(.cancelled) }
        guard await pageSessionIsUnchanged() else { return .unavailable(.sourceChanged) }
        guard let json = result as? String,
            let data = json.data(using: .utf8),
            let probe = try? JSONDecoder().decode(BridgeFilesSearchProbe.self, from: data),
            probe.requestId == requestId,
            let answer = probe.answer
        else {
            return .unavailable(.failed)
        }
        return await resolve(answer, fenceBefore: fenceBefore)
    }

    private func resolve(
        _ answer: BridgeFilesSearchProbe.Answer,
        fenceBefore: BridgeFileCollectionSearchFence
    ) async -> BridgeFilesSearchOutcome {
        switch answer.kind {
        case "invalidPattern":
            return .invalidPattern(answer.searchError ?? "Invalid pattern")
        case "noSource":
            return .unavailable(.noLivePage)
        case "matches":
            break
        default:
            return .unavailable(.failed)
        }
        guard let matches = answer.matches, let answerSource = answer.source,
            let totalMatchCount = answer.totalMatchCount, let truncated = answer.truncated,
            let complete = answer.complete
        else {
            return .unavailable(.failed)
        }
        // The worker's rows and groups must be exactly the ones native issued.
        guard answerSource.sourceId == fenceBefore.source.sourceId,
            answerSource.sourceGeneration == fenceBefore.source.subscriptionGeneration,
            answer.membershipRevision == fenceBefore.membershipRevision,
            await source.searchFence() == fenceBefore
        else {
            return .unavailable(.sourceChanged)
        }
        var resolvedMatches: [BridgeFilesSearchMatch] = []
        for match in matches {
            guard
                let document = await source.displayedDocument(
                    displayPath: match.displayPath,
                    sourceId: answerSource.sourceId,
                    subscriptionGeneration: answerSource.sourceGeneration
                ),
                let resolved = Self.resolvedMatch(match, document: document)
            else {
                return .unavailable(.sourceChanged)
            }
            resolvedMatches.append(resolved)
        }
        return .results(
            BridgeFilesSearchResults(
                matches: resolvedMatches,
                totalMatchCount: totalMatchCount,
                truncated: truncated,
                complete: complete,
                unavailableMemberWorktreeIds: fenceBefore.unavailableMemberWorktreeIds
            )
        )
    }

    /// A match whose worker attribution disagrees with native resolution was
    /// computed against another layout.
    private static func resolvedMatch(
        _ match: BridgeFilesSearchProbe.Answer.Match,
        document: BridgeFileCollectionDisplayedDocument
    ) -> BridgeFilesSearchMatch? {
        switch document {
        case .memberFile(let worktreeId, let relativePath, let location):
            guard let attributed = match.memberWorktreeId.flatMap(UUID.init(uuidString:)),
                attributed == worktreeId
            else { return nil }
            return BridgeFilesSearchMatch(
                displayPath: match.displayPath,
                location: location,
                memberWorktreeId: worktreeId,
                memberRelativePath: relativePath
            )
        case .openedDocument(let location):
            guard match.memberWorktreeId == nil else { return nil }
            return BridgeFilesSearchMatch(
                displayPath: match.displayPath,
                location: location,
                memberWorktreeId: nil,
                memberRelativePath: nil
            )
        }
    }

    /// The request travels as a JSON literal so search text is never spliced
    /// into script source.
    static func pageScript(
        requestId: String,
        criteria: BridgeFilesSearchCriteria
    ) throws -> String {
        let scope: BridgeFilesSearchPageRequest.Criteria.Scope =
            switch criteria.scope {
            case .allMembersAndOpenedDocuments: .init(kind: "all", worktreeId: nil)
            case .member(let worktreeId): .init(kind: "member", worktreeId: worktreeId.uuidString.lowercased())
            case .openedDocuments: .init(kind: "openedDocuments", worktreeId: nil)
            }
        let request = BridgeFilesSearchPageRequest(
            criteria: .init(
                limit: criteria.limit,
                scope: scope,
                searchMode: criteria.mode.rawValue,
                searchText: criteria.searchText
            ),
            requestId: requestId
        )
        guard let requestLiteral = String(bytes: try JSONEncoder().encode(request), encoding: .utf8) else {
            throw EncodingError.invalidValue(
                request,
                .init(codingPath: [], debugDescription: "Files search request is not UTF-8")
            )
        }
        return """
            window.bridgeFilesSearchProbe = undefined;
            window.dispatchEvent(new CustomEvent('__bridge_files_search', { detail: \(requestLiteral) }));
            const pendingSearch = window.bridgeFilesSearchProbe;
            window.bridgeFilesSearchProbe = undefined;
            if (!pendingSearch) {
              return JSON.stringify({ requestId: '\(requestId)', answer: null });
            }
            return JSON.stringify(await pendingSearch);
            """
    }
}
