import Foundation

/// Which part of the receiving Bridge's Files collection a search covers.
public enum IPCBridgeFilesSearchScope: String, CaseIterable, Codable, Equatable, Sendable {
    /// Every member worktree and every individually opened document.
    case all
    /// One member worktree, named by `worktreeId`.
    case member
    /// Only the individually opened documents outside every member.
    case openedDocuments
}

/// Search the Files collection of the Bridge a pane handle names.
public struct IPCBridgeFilesSearchParams: Codable, Equatable, Sendable {
    public static let maximumSearchTextUTF16Length = 4096
    /// The collection worker's answer bound.
    public static let maximumLimit = 500
    public static let defaultLimit = 100

    public let handle: String
    public let searchText: String
    public let searchMode: IPCBridgeReviewSearchMode
    public let scope: IPCBridgeFilesSearchScope
    /// Required exactly when `scope` is `member`.
    public let worktreeId: UUID?
    public let limit: Int

    public init(
        handle: String,
        searchText: String,
        searchMode: IPCBridgeReviewSearchMode = .text,
        scope: IPCBridgeFilesSearchScope = .all,
        worktreeId: UUID? = nil,
        limit: Int = defaultLimit
    ) {
        self.handle = handle
        self.searchText = searchText
        self.searchMode = searchMode
        self.scope = scope
        self.worktreeId = worktreeId
        self.limit = limit
    }

    private enum CodingKeys: String, CodingKey {
        case handle
        case searchText
        case searchMode
        case scope
        case worktreeId
        case limit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        handle = try container.decode(String.self, forKey: .handle)
        searchText = try container.decode(String.self, forKey: .searchText)
        guard searchText.utf16.count <= Self.maximumSearchTextUTF16Length else {
            throw DecodingError.dataCorruptedError(
                forKey: .searchText,
                in: container,
                debugDescription: "Bridge Files search text exceeds the supported length"
            )
        }
        searchMode =
            try container.decodeIfPresent(IPCBridgeReviewSearchMode.self, forKey: .searchMode) ?? .text
        scope = try container.decodeIfPresent(IPCBridgeFilesSearchScope.self, forKey: .scope) ?? .all
        worktreeId = try container.decodeIfPresent(UUID.self, forKey: .worktreeId)
        guard (scope == .member) == (worktreeId != nil) else {
            throw DecodingError.dataCorruptedError(
                forKey: .worktreeId,
                in: container,
                debugDescription: "worktreeId is required for the member scope and rejected otherwise"
            )
        }
        limit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? Self.defaultLimit
        guard (1...Self.maximumLimit).contains(limit) else {
            throw DecodingError.dataCorruptedError(
                forKey: .limit,
                in: container,
                debugDescription: "limit must be between 1 and \(Self.maximumLimit)"
            )
        }
    }
}

public enum IPCBridgeFilesSearchStatus: String, CaseIterable, Codable, Equatable, Sendable {
    case results
    case invalidPattern
    case unavailable
}

/// Why a Files search produced no results.
public enum IPCBridgeFilesSearchUnavailableReason: String, CaseIterable, Codable, Equatable, Sendable {
    /// The pane is not a receiving Bridge with navigation state.
    case receiverUnavailable
    /// No mounted Bridge renders the receiver; search never mounts one.
    case notMounted
    /// The narrowed worktree is not a member of this Bridge.
    case notMember
    /// The page has no completed handshake or no Files source yet.
    case noLivePage
    /// The collection's source or membership changed while searching.
    case sourceChanged
    /// The search was cancelled.
    case cancelled
    /// The page did not answer or its worker refused the search.
    case failed
}

public struct IPCBridgeFilesSearchMatch: Codable, Equatable, Sendable {
    /// The key the Files tree lists the document under.
    public let displayPath: String
    /// The document's canonical absolute path.
    public let path: String
    /// The member worktree listing the file; absent for an opened document.
    public let memberWorktreeId: UUID?
    public let memberRelativePath: String?

    public init(displayPath: String, path: String, memberWorktreeId: UUID?, memberRelativePath: String?) {
        self.displayPath = displayPath
        self.path = path
        self.memberWorktreeId = memberWorktreeId
        self.memberRelativePath = memberRelativePath
    }
}

public struct IPCBridgeFilesSearchResult: Codable, Equatable, Sendable {
    public let paneId: UUID
    public let status: IPCBridgeFilesSearchStatus
    public let reason: IPCBridgeFilesSearchUnavailableReason?
    public let searchError: String?
    /// Matches in collection order, at most the requested limit.
    public let matches: [IPCBridgeFilesSearchMatch]
    public let totalMatchCount: Int
    public let truncated: Bool
    /// False until the collection's initial tree finished, so a short result
    /// is not yet proof that a file is absent.
    public let complete: Bool
    /// Members whose source failed; their files were not searched.
    public let unavailableMemberWorktreeIds: [UUID]

    public init(
        paneId: UUID,
        status: IPCBridgeFilesSearchStatus,
        reason: IPCBridgeFilesSearchUnavailableReason? = nil,
        searchError: String? = nil,
        matches: [IPCBridgeFilesSearchMatch] = [],
        totalMatchCount: Int = 0,
        truncated: Bool = false,
        complete: Bool = false,
        unavailableMemberWorktreeIds: [UUID] = []
    ) {
        self.paneId = paneId
        self.status = status
        self.reason = reason
        self.searchError = searchError
        self.matches = matches
        self.totalMatchCount = totalMatchCount
        self.truncated = truncated
        self.complete = complete
        self.unavailableMemberWorktreeIds = unavailableMemberWorktreeIds
    }
}
