import AgentStudioBridge
import AgentStudioCore
import Foundation

/// Why a navigation command did not change what the receiver shows.
package enum BridgeNavigationCommandFailure: Equatable, Sendable {
    /// The receiver has no navigation record.
    case receiverUnavailable
    /// No mounted Bridge renders the receiver.
    case notMounted
    /// The document is not in the receiver's opened-document inventory.
    case notInInventory
    /// The Files collection does not list the document.
    case notListed
    /// The worktree is not a member of this receiver.
    case notMember
    /// The member's worktree is not currently known to the catalog.
    case worktreeUnavailable
    /// The page selected the document but cannot render it.
    case documentUnavailable
    /// The page, its Files source or its controller went away while waiting.
    case pageUnavailable
}

/// The outcome of one Bridge navigation command. Rendered success and
/// persistence success are separate: `appliedUnsaved` reports a visible effect
/// whose remembered navigation could not be saved yet.
package enum BridgeNavigationCommandOutcome: Equatable, Sendable {
    case applied
    case appliedUnsaved
    /// An active annotation editor could not be flushed; nothing changed.
    case refusedUnsavedDraft
    /// The member is the owner terminal's current worktree; nothing changed.
    case refusedProtected
    /// A newer navigation of the same receiver replaced this one.
    case superseded
    case failed(BridgeNavigationCommandFailure)
}

@MainActor
extension BridgeNavigationCommandHandler {
    // MARK: - Files

    /// Show a document of the receiving collection in Files. The page gates the
    /// change behind its active editors and acknowledges the displayed
    /// document; the displayed receipt records the selection through the same
    /// rules a human tree click uses.
    func activateFile(
        _ location: BridgeDocumentLocation,
        in receiver: BridgeReceiver
    ) async -> BridgeNavigationCommandOutcome {
        guard navigationAtom.record(for: receiver) != nil else {
            return .failed(.receiverUnavailable)
        }
        guard let presentation = presentationPorts?.mountedPresentation(receiver) else {
            return .failed(.notMounted)
        }
        let generation = beginNavigation(for: receiver)
        let arrival = await presentation.activateFileDocument(location)
        guard isCurrentNavigation(generation, for: receiver) else { return .superseded }
        switch arrival {
        case .displayed:
            return await persistedOutcome()
        case .unavailable:
            return .failed(.documentUnavailable)
        case .refused:
            return .refusedUnsavedDraft
        case .superseded:
            return .superseded
        case .notListed:
            return .failed(.notListed)
        case .cancelled:
            return .failed(.pageUnavailable)
        }
    }

    /// Remove an opened document from the receiver's inventory. Closing the
    /// displayed document first flushes the page's active editors; a refused
    /// flush keeps the entry and its editor. Disk content and annotations are
    /// never touched.
    func closeFile(
        _ location: BridgeDocumentLocation,
        in receiver: BridgeReceiver
    ) async -> BridgeNavigationCommandOutcome {
        guard let record = navigationAtom.record(for: receiver) else {
            return .failed(.receiverUnavailable)
        }
        guard record.openedDocument(at: location) != nil else { return .failed(.notInInventory) }
        let generation = beginNavigation(for: receiver)
        if record.selectedFilesDocument == location,
            let presentation = presentationPorts?.mountedPresentation(receiver)
        {
            let preparation = await presentation.prepareActiveEditorsForNavigation()
            guard isCurrentNavigation(generation, for: receiver) else { return .superseded }
            guard preparation.allowsContentToLeave else { return .refusedUnsavedDraft }
        }
        guard let currentRecord = navigationAtom.record(for: receiver) else {
            return .failed(.receiverUnavailable)
        }
        switch BridgeNavigationRules.closingDocument(location, in: currentRecord) {
        case .notOpen:
            return .failed(.notInInventory)
        case .closed(let updated, _):
            navigationAtom.setRecord(updated, for: receiver)
            presentationPorts?.refreshFilesSource(receiver)
            return await persistedOutcome()
        }
    }

    /// Record a Files selection the page displayed. Member files are admitted
    /// with their known-worktree provenance; a member that left the receiver
    /// or an unknown worktree is ignored rather than guessed.
    func recordDisplayedFilesSelection(
        _ selection: BridgeFilesDisplayedSelection,
        for receiver: BridgeReceiver
    ) {
        guard let record = navigationAtom.record(for: receiver) else { return }
        var provenance: BridgeKnownWorktreeProvenance?
        if let worktreeId = selection.memberWorktreeId, let relativePath = selection.memberRelativePath {
            guard record.containsMember(worktreeId),
                let repoId = repositoryTopologyAtom.repositoryId(containing: worktreeId)
            else { return }
            provenance = BridgeKnownWorktreeProvenance(
                repoId: repoId,
                worktreeId: worktreeId,
                relativePath: relativePath
            )
        }
        navigationAtom.setRecord(
            BridgeNavigationRules.recordingDisplayedFilesSelection(
                BridgeOpenedDocument(location: selection.location, provenance: provenance),
                in: record
            ),
            for: receiver
        )
    }

    // MARK: - Review

    /// Show one member worktree's Review with its retained comparison. A
    /// different member replaces the receiver's controller, so the page's
    /// active editors are flushed first; the Files selection never changes.
    func activateReview(
        of worktreeId: UUID,
        in receiver: BridgeReceiver
    ) async -> BridgeNavigationCommandOutcome {
        guard let record = navigationAtom.record(for: receiver) else {
            return .failed(.receiverUnavailable)
        }
        guard record.containsMember(worktreeId) else { return .failed(.notMember) }
        guard knownWorktree(worktreeId) != nil else { return .failed(.worktreeUnavailable) }
        guard let ports = presentationPorts, let presentation = ports.mountedPresentation(receiver) else {
            return .failed(.notMounted)
        }
        let replacesReviewSource = record.reviewSelection != .member(worktreeId: worktreeId)
        let generation = beginNavigation(for: receiver)
        if replacesReviewSource {
            let preparation = await presentation.prepareActiveEditorsForNavigation()
            guard isCurrentNavigation(generation, for: receiver) else { return .superseded }
            guard preparation.allowsContentToLeave else { return .refusedUnsavedDraft }
        }
        guard let currentRecord = navigationAtom.record(for: receiver) else {
            return .failed(.receiverUnavailable)
        }
        switch BridgeNavigationRules.activatingReview(of: worktreeId, comparison: nil, in: currentRecord) {
        case .notMember:
            return .failed(.notMember)
        case .applied(let updated):
            navigationAtom.setRecord(updated, for: receiver)
        }
        let shown =
            replacesReviewSource
            ? ports.replaceReviewSource(receiver, .review)
            : presentation.requestViewerSurface(.review)
        guard shown else { return .failed(.pageUnavailable) }
        return await persistedOutcome()
    }

    /// Return the receiver to Files with its retained document.
    func showFiles(in receiver: BridgeReceiver) async -> BridgeNavigationCommandOutcome {
        guard let record = navigationAtom.record(for: receiver) else {
            return .failed(.receiverUnavailable)
        }
        guard let presentation = presentationPorts?.mountedPresentation(receiver) else {
            return .failed(.notMounted)
        }
        _ = beginNavigation(for: receiver)
        navigationAtom.setRecord(BridgeNavigationRules.showingFiles(in: record), for: receiver)
        guard presentation.requestViewerSurface(.file) else { return .failed(.pageUnavailable) }
        return await persistedOutcome()
    }

    // MARK: - Generations

    /// Start a navigation that awaits the page; any older one still waiting
    /// for the same receiver can no longer publish state.
    func beginNavigation(for receiver: BridgeReceiver) -> Int {
        let generation = (navigationGenerationByReceiver[receiver] ?? 0) + 1
        navigationGenerationByReceiver[receiver] = generation
        return generation
    }

    func isCurrentNavigation(_ generation: Int, for receiver: BridgeReceiver) -> Bool {
        navigationGenerationByReceiver[receiver] == generation
            && navigationAtom.record(for: receiver) != nil
    }

    func persistedOutcome() async -> BridgeNavigationCommandOutcome {
        guard let ports = presentationPorts else { return .appliedUnsaved }
        return await ports.persistNavigation() ? .applied : .appliedUnsaved
    }
}
