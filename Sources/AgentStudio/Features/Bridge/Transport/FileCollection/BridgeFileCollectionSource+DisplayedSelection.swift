import AgentStudioCore
import Foundation

/// Whether the live Files source lists a display key as a row.
enum BridgeFileCollectionListing: Equatable, Sendable {
    case listed
    /// The initial enumeration finished without this row.
    case notListed
    /// No live source, or its initial enumeration is still running.
    case undetermined
}

/// A Files display key resolved back to the document it names.
enum BridgeFileCollectionDisplayedDocument: Equatable, Sendable {
    /// A file in a member worktree's tree, with its canonical location.
    case memberFile(worktreeId: UUID, relativePath: String, location: BridgeDocumentLocation)
    /// An opened document outside every member.
    case openedDocument(BridgeDocumentLocation)

    var location: BridgeDocumentLocation {
        switch self {
        case .memberFile(_, _, let location), .openedDocument(let location): location
        }
    }
}

extension BridgeFileCollectionSource {
    /// The Files source the page must have accepted before a native file
    /// navigation can apply: the live subscription whose collection source was
    /// announced.
    func currentNavigationSource() -> BridgeProductNavigationFileSource? {
        guard
            let context = contextBySubscriptionId.values.first(where: \.collectionSourceAccepted)
        else { return nil }
        return BridgeProductNavigationFileSource(
            sourceId: context.productSource.sourceId,
            subscriptionGeneration: context.productSource.subscriptionGeneration
        )
    }

    /// The display key the collection lists `location` under: the deepest
    /// member tree containing it, else its opened-document entry. Nil when the
    /// collection does not list the document.
    func displayPath(for location: BridgeDocumentLocation) -> String? {
        ensureInitialLayout()
        let rootsById = Dictionary(
            uniqueKeysWithValues: layout.memberGroups.map { ($0.worktreeId, $0.canonicalRootPath) }
        )
        switch BridgeNavigationRules.grouping(
            of: location,
            memberWorktreeIds: layout.memberGroups.map(\.worktreeId),
            memberRootsByWorktreeId: rootsById
        ) {
        case .member(let worktreeId):
            guard let root = rootsById[worktreeId],
                let relativePath = location.relativePath(inCanonicalRoot: root)
            else { return nil }
            return layout.displayPath(worktreeId: worktreeId, relativePath: relativePath)
        case .loose, .ambiguous:
            return layout.openedDocuments.first { $0.location == location }?.displayPath
        }
    }

    /// Whether the live source emitted `displayPath` as a row. Only a finished
    /// initial enumeration can prove a row absent, for example a file the
    /// member's tree policy excludes.
    func listing(displayPath: String) -> BridgeFileCollectionListing {
        guard
            let context = contextBySubscriptionId.values.first(where: \.collectionSourceAccepted)
        else { return .undetermined }
        if context.emittedPathsBySource.values.contains(where: { $0.contains(displayPath) }) {
            return .listed
        }
        return context.enumerationIndex == nil ? .notListed : .undetermined
    }

    /// Resolve a displayed-selection receipt. Only a key the collection issued
    /// under a live subscription at the receipt's exact source generation
    /// resolves; group rows, unknown keys and receipts from an older source do
    /// not.
    func displayedDocument(
        displayPath: String,
        sourceId: String,
        subscriptionGeneration: Int
    ) -> BridgeFileCollectionDisplayedDocument? {
        let isLiveSource = contextBySubscriptionId.values.contains {
            $0.productSource.sourceId == sourceId
                && $0.productSource.subscriptionGeneration == subscriptionGeneration
        }
        guard isLiveSource else { return nil }
        switch layout.resolve(displayPath: displayPath) {
        case .memberPath(let worktreeId, let relativePath):
            guard let root = layout.memberGroup(for: worktreeId)?.canonicalRootPath,
                let location = BridgeDocumentLocation(
                    canonicalPath: root == "/" ? "/\(relativePath)" : "\(root)/\(relativePath)"
                )
            else { return nil }
            return .memberFile(worktreeId: worktreeId, relativePath: relativePath, location: location)
        case .openedDocument(let location):
            return .openedDocument(location)
        case .memberGroup, .openedDocumentsGroup, nil:
            return nil
        }
    }
}
