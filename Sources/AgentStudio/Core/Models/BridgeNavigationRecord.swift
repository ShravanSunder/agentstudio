import Foundation

/// The surface a receiving Bridge retains between presentations.
package enum BridgeNavigationSurface: String, Hashable, Sendable, CaseIterable {
    case files
    case review
}

/// Optional narrowing of the Files collection. Filtering never redefines
/// membership; the default shows every member tree plus loose documents.
package enum BridgeFilesFilter: Hashable, Sendable {
    case allMembers
    case member(worktreeId: UUID)
    case openedDocuments
}

/// A legacy Review source that could not resolve to an eligible known
/// worktree at conversion. It keeps its original payload so data is never
/// silently discarded or converted into a fake worktree; it is always
/// presented as unavailable.
package struct BridgeImportedReviewQuery: Hashable, Sendable {
    package enum Variant: String, Hashable, Sendable, CaseIterable {
        case workspace
        case commit
        case branchDiff
        case agentSnapshot
    }

    package let variant: Variant
    package let originalPayloadJSON: String

    package init(variant: Variant, originalPayloadJSON: String) {
        self.variant = variant
        self.originalPayloadJSON = originalPayloadJSON
    }
}

/// The Review selection, independent of the Files selection.
package enum BridgeReviewSelection: Hashable, Sendable {
    case unselected
    case member(worktreeId: UUID)
    case importedUnavailable(BridgeImportedReviewQuery)

    package var memberWorktreeId: UUID? {
        guard case .member(let worktreeId) = self else { return nil }
        return worktreeId
    }
}

/// The persistent navigation record of one receiving Bridge.
///
/// It survives companion replacement, hide/show, Zoom exit, restart and
/// close/undo. Runtime facts — availability, loading generations, descriptors
/// and the displayed native instance — never live here. The protected member is
/// derived from the owner's current terminal association, not stored.
package struct BridgeNavigationRecord: Hashable, Sendable {
    /// Ordered opened-document inventory; one entry per canonical location.
    package var openedDocuments: [BridgeOpenedDocument]
    /// Ordered known-worktree browsing membership; no duplicates.
    package var memberWorktreeIds: [UUID]
    package var filesFilter: BridgeFilesFilter
    /// Last successfully activated Files document; always an inventory entry.
    package var selectedFilesDocument: BridgeDocumentLocation?
    package var reviewSelection: BridgeReviewSelection
    package var surface: BridgeNavigationSurface
    /// Per-member retained Review comparison. A missing entry means the
    /// existing first-time comparison designation still applies.
    package var reviewComparisonsByWorktreeId: [UUID: WorkspaceBaseline]

    package init(
        openedDocuments: [BridgeOpenedDocument] = [],
        memberWorktreeIds: [UUID] = [],
        filesFilter: BridgeFilesFilter = .allMembers,
        selectedFilesDocument: BridgeDocumentLocation? = nil,
        reviewSelection: BridgeReviewSelection = .unselected,
        surface: BridgeNavigationSurface = .files,
        reviewComparisonsByWorktreeId: [UUID: WorkspaceBaseline] = [:]
    ) {
        self.openedDocuments = openedDocuments
        self.memberWorktreeIds = memberWorktreeIds
        self.filesFilter = filesFilter
        self.selectedFilesDocument = selectedFilesDocument
        self.reviewSelection = reviewSelection
        self.surface = surface
        self.reviewComparisonsByWorktreeId = reviewComparisonsByWorktreeId
    }

    package static let empty = Self()

    package func openedDocument(at location: BridgeDocumentLocation) -> BridgeOpenedDocument? {
        openedDocuments.first { $0.location == location }
    }

    package func containsMember(_ worktreeId: UUID) -> Bool {
        memberWorktreeIds.contains(worktreeId)
    }

    /// The comparison Review uses for the selected member, if any.
    package var selectedReviewComparison: WorkspaceBaseline? {
        guard let worktreeId = reviewSelection.memberWorktreeId else { return nil }
        return reviewComparisonsByWorktreeId[worktreeId]
    }
}
