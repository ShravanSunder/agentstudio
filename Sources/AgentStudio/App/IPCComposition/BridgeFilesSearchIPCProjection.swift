import AgentStudioBridge
import AgentStudioProgrammaticControl
import Foundation

/// Maps `bridge.files.search` parameters onto the collection search and its
/// outcome back onto the wire result.
enum BridgeFilesSearchIPCProjection {
    static func criteria(_ params: IPCBridgeFilesSearchParams) -> BridgeFilesSearchCriteria {
        let scope: BridgeFilesSearchScope =
            switch params.scope {
            case .all: .allMembersAndOpenedDocuments
            // The parameter decoder requires a worktree for the member scope.
            case .member: params.worktreeId.map { .member(worktreeId: $0) } ?? .allMembersAndOpenedDocuments
            case .openedDocuments: .openedDocuments
            }
        return BridgeFilesSearchCriteria(
            searchText: params.searchText,
            mode: params.searchMode.kind == .regex ? .regex : .text,
            scope: scope,
            limit: params.limit
        )
    }

    static func result(_ outcome: BridgeFilesSearchRequestOutcome, paneId: UUID) -> IPCBridgeFilesSearchResult {
        switch outcome {
        case .receiverUnavailable:
            return unavailable(.receiverUnavailable, paneId: paneId)
        case .notMounted:
            return unavailable(.notMounted, paneId: paneId)
        case .notMember:
            return unavailable(.notMember, paneId: paneId)
        case .answered(.invalidPattern(let searchError)):
            return IPCBridgeFilesSearchResult(paneId: paneId, status: .invalidPattern, searchError: searchError)
        case .answered(.unavailable(let unavailability)):
            return unavailable(reason(unavailability), paneId: paneId)
        case .answered(.results(let results)):
            return IPCBridgeFilesSearchResult(
                paneId: paneId,
                status: .results,
                matches: results.matches.map { match in
                    IPCBridgeFilesSearchMatch(
                        displayPath: match.displayPath,
                        path: match.location.canonicalPath,
                        memberWorktreeId: match.memberWorktreeId,
                        memberRelativePath: match.memberRelativePath
                    )
                },
                totalMatchCount: results.totalMatchCount,
                truncated: results.truncated,
                complete: results.complete,
                unavailableMemberWorktreeIds: results.unavailableMemberWorktreeIds
            )
        }
    }

    private static func unavailable(
        _ reason: IPCBridgeFilesSearchUnavailableReason,
        paneId: UUID
    ) -> IPCBridgeFilesSearchResult {
        IPCBridgeFilesSearchResult(paneId: paneId, status: .unavailable, reason: reason)
    }

    private static func reason(
        _ unavailability: BridgeFilesSearchUnavailability
    ) -> IPCBridgeFilesSearchUnavailableReason {
        switch unavailability {
        case .noLivePage: .noLivePage
        case .sourceChanged: .sourceChanged
        case .cancelled: .cancelled
        case .failed: .failed
        }
    }
}
