import AgentStudioBridge
import AgentStudioCore
import Foundation

/// App owner of receiver navigation: sequences admission, pure navigation
/// transitions and their effects for every receiving Bridge.
///
/// It holds no second copy of navigation state — `BridgeNavigationAtom` is the
/// only live owner and `BridgeNavigationRules` decides every transition. The
/// handler resolves known-worktree facts from the repository topology and
/// derives each controller's explicit source inputs from the record.
@MainActor
final class BridgeNavigationCommandHandler {
    let navigationAtom: BridgeNavigationAtom
    let repositoryTopologyAtom: RepositoryTopologyAtom
    /// Supplied by the App composition once mounted Bridges can be reached.
    var presentationPorts: BridgeReceiverPresentationPorts?
    /// Advances per receiver for every navigation that awaits the page, so a
    /// late result of an older request never publishes state.
    var navigationGenerationByReceiver: [BridgeReceiver: Int] = [:]
    /// Unregistered worktrees whose removal still waits on an unsaved draft in
    /// some receiver, with the canonical root captured from the catalog delta.
    var pendingCatalogUnregistrationRootsById: [UUID: String] = [:]

    init(navigationAtom: BridgeNavigationAtom, repositoryTopologyAtom: RepositoryTopologyAtom) {
        self.navigationAtom = navigationAtom
        self.repositoryTopologyAtom = repositoryTopologyAtom
    }

    func record(for receiver: BridgeReceiver) -> BridgeNavigationRecord? {
        navigationAtom.record(for: receiver)
    }

    /// Whether a standalone Bridge pane's legacy source failed to import this
    /// launch. Such a pane presents unavailable and must never be reseeded,
    /// because a new local row would let the next start discard its legacy data.
    func isConversionUnavailable(_ receiver: BridgeReceiver) -> Bool {
        receiver.kind == .standaloneBridge
            && navigationAtom.conversionUnavailablePaneIds.contains(receiver.paneId)
    }

    /// The receiver's record, seeding the first record from the owner's known
    /// worktree when none exists yet.
    @discardableResult
    func ensureRecord(
        for receiver: BridgeReceiver,
        seedingKnownWorktreeId knownWorktreeId: UUID?,
        surface: BridgeNavigationSurface = .files
    ) -> BridgeNavigationRecord? {
        if let existing = navigationAtom.record(for: receiver) {
            return existing
        }
        guard !isConversionUnavailable(receiver) else { return nil }
        let seeded = BridgeNavigationRules.seededRecord(
            knownTerminalWorktreeId: knownWorktreeId.flatMap(knownWorktree)?.id,
            surface: surface
        )
        navigationAtom.setRecord(seeded, for: receiver)
        return seeded
    }

    /// Admitted CWD fact for a terminal receiver: inject the current known
    /// worktree as a member when absent. Selections never change and previous
    /// members stay listed; protection follows the current association.
    func applyKnownCWDAssociation(_ knownWorktreeId: UUID?, forTerminalPane paneId: UUID) {
        let receiver = BridgeReceiver.terminal(paneId)
        guard let record = navigationAtom.record(for: receiver) else { return }
        let known = knownWorktreeId.flatMap(knownWorktree)?.id
        navigationAtom.setRecord(
            BridgeNavigationRules.injectingKnownCWDWorktree(known, into: record),
            for: receiver
        )
    }

    /// The controller's Review input: the record's selected known member and
    /// its retained comparison, or `nil` when Review has no known target.
    func reviewBinding(for receiver: BridgeReceiver) -> BridgeReviewSourceBinding? {
        guard
            let record = navigationAtom.record(for: receiver),
            let worktreeId = record.reviewSelection.memberWorktreeId,
            let worktree = knownWorktree(worktreeId)
        else {
            return nil
        }
        return BridgeReviewSourceBinding(
            worktreeId: worktree.id,
            worktreeRootPath: worktree.path.path,
            comparison: record.reviewComparisonsByWorktreeId[worktree.id]
        )
    }

    /// The controller's Files input: the record's known members in collection
    /// order plus its opened documents. A member that is temporarily unknown is
    /// left out without being removed from the record.
    func filesBinding(for receiver: BridgeReceiver) -> BridgeFilesSourceBinding? {
        guard let record = navigationAtom.record(for: receiver) else { return nil }
        return BridgeFilesSourceBinding(
            collectionToken: BridgeFilesSourceBinding.collectionToken(forReceiverPaneId: receiver.paneId),
            members: record.memberWorktreeIds.compactMap(knownWorktree),
            openedDocuments: record.openedDocuments.map(\.location)
        )
    }

    /// Commit a comparison choice for one member of one receiver. The initial
    /// designation only applies when the member has no retained comparison.
    func commitReviewComparison(
        _ target: WorkspaceReviewContributionTarget,
        for receiver: BridgeReceiver,
        worktreeId: UUID,
        onlyIfAbsent: Bool
    ) -> BridgeReviewComparisonCommitResult {
        guard let record = navigationAtom.record(for: receiver), record.containsMember(worktreeId) else {
            return .receiverUnavailable
        }
        if onlyIfAbsent, let retained = record.reviewComparisonsByWorktreeId[worktreeId] {
            return .unchanged(retained)
        }
        let comparison = WorkspaceBaseline(contributionTarget: target)
        guard record.reviewComparisonsByWorktreeId[worktreeId] != comparison else {
            return .unchanged(comparison)
        }
        switch BridgeNavigationRules.recordingReviewComparison(comparison, for: worktreeId, in: record) {
        case .applied(let updated):
            navigationAtom.setRecord(updated, for: receiver)
            return .applied(comparison)
        case .notMember:
            return .receiverUnavailable
        }
    }

    /// A commit closure bound to the controller's receiver and Review member.
    func reviewComparisonCommit(
        for receiver: BridgeReceiver,
        binding: BridgeReviewSourceBinding?,
        onlyIfAbsent: Bool
    ) -> BridgeReviewComparisonCommit {
        { [weak self] target in
            guard let self, let binding else { return .receiverUnavailable }
            return self.commitReviewComparison(
                target,
                for: receiver,
                worktreeId: binding.worktreeId,
                onlyIfAbsent: onlyIfAbsent
            )
        }
    }

    func knownWorktree(_ worktreeId: UUID) -> Worktree? {
        guard let repoId = repositoryTopologyAtom.repositoryId(containing: worktreeId) else { return nil }
        return repositoryTopologyAtom.validatedAssociation(repoId: repoId, worktreeId: worktreeId)?.worktree
    }
}
