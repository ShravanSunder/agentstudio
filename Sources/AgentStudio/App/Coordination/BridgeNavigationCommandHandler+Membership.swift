import AgentStudioBridge
import AgentStudioCore
import Foundation
import os

private let bridgeNavigationMembershipLogger = Logger(
    subsystem: "com.agentstudio",
    category: "BridgeNavigationMembership"
)

@MainActor
extension BridgeNavigationCommandHandler {
    // MARK: - Add

    /// Add an already-known worktree to this receiver only. Unknown worktrees
    /// are refused without discovery or registration; a duplicate addition has
    /// no effect. Neither selection changes.
    func addWorktree(_ worktreeId: UUID, to receiver: BridgeReceiver) async -> BridgeNavigationCommandOutcome {
        guard let record = navigationAtom.record(for: receiver) else {
            return .failed(.receiverUnavailable)
        }
        guard knownWorktree(worktreeId) != nil else { return .failed(.worktreeUnavailable) }
        switch BridgeNavigationRules.addingMember(worktreeId, to: record) {
        case .alreadyMember:
            return .applied
        case .added(let updated):
            navigationAtom.setRecord(updated, for: receiver)
            presentationPorts?.refreshFilesSource(receiver)
            return await persistedOutcome()
        }
    }

    // MARK: - Select

    /// Select which member Review reads, without changing the displayed
    /// surface or the Files selection. A mounted Bridge is rebuilt for the new
    /// member after its active editors are flushed.
    func selectReviewWorktree(
        _ worktreeId: UUID,
        in receiver: BridgeReceiver
    ) async -> BridgeNavigationCommandOutcome {
        guard let record = navigationAtom.record(for: receiver) else {
            return .failed(.receiverUnavailable)
        }
        guard record.containsMember(worktreeId) else { return .failed(.notMember) }
        guard knownWorktree(worktreeId) != nil else { return .failed(.worktreeUnavailable) }
        guard record.reviewSelection != .member(worktreeId: worktreeId) else { return .applied }
        let generation = beginNavigation(for: receiver)
        let presentation = presentationPorts?.mountedPresentation(receiver)
        if let presentation {
            let preparation = await presentation.prepareActiveEditorsForNavigation()
            guard isCurrentNavigation(generation, for: receiver) else { return .superseded }
            guard preparation.allowsContentToLeave else { return .refusedUnsavedDraft }
        }
        guard let currentRecord = navigationAtom.record(for: receiver) else {
            return .failed(.receiverUnavailable)
        }
        guard case .applied(let updated) = BridgeNavigationRules.selectingReviewWorktree(worktreeId, in: currentRecord)
        else { return .failed(.notMember) }
        navigationAtom.setRecord(updated, for: receiver)
        if presentation != nil {
            _ = presentationPorts?.replaceReviewSource(receiver, Self.productSurface(for: updated.surface))
        }
        return await persistedOutcome()
    }

    // MARK: - Remove

    /// Remove a member that is not the owner terminal's current worktree: its
    /// tree and retained open entries leave, an affected Files selection and
    /// filter clear, and Review falls back to the next member. Displayed
    /// content only leaves after the page's editors are flushed; protection
    /// and membership are checked again after that wait. Disk content,
    /// annotations and the repository catalog are untouched.
    func removeWorktree(
        _ worktreeId: UUID,
        from receiver: BridgeReceiver
    ) async -> BridgeNavigationCommandOutcome {
        guard let record = navigationAtom.record(for: receiver) else {
            return .failed(.receiverUnavailable)
        }
        let planned = plannedExplicitRemoval(of: worktreeId, from: record, receiver: receiver)
        let effect: BridgeMemberRemovalEffect
        switch planned {
        case .refusedProtected: return .refusedProtected
        case .notMember: return .failed(.notMember)
        case .removed(_, let plannedEffect): effect = plannedEffect
        }
        let generation = beginNavigation(for: receiver)
        if Self.removalReplacesDisplayedContent(effect),
            let presentation = presentationPorts?.mountedPresentation(receiver)
        {
            let preparation = await presentation.prepareActiveEditorsForNavigation()
            guard isCurrentNavigation(generation, for: receiver) else { return .superseded }
            guard preparation.allowsContentToLeave else { return .refusedUnsavedDraft }
        }
        // The CWD and the membership may have changed while the page flushed.
        guard let currentRecord = navigationAtom.record(for: receiver) else {
            return .failed(.receiverUnavailable)
        }
        switch plannedExplicitRemoval(of: worktreeId, from: currentRecord, receiver: receiver) {
        case .refusedProtected:
            return .refusedProtected
        case .notMember:
            return .failed(.notMember)
        case .removed(let updated, let committedEffect):
            commitRemoval(updated, effect: committedEffect, for: receiver)
            return await persistedOutcome()
        }
    }

    // MARK: - Catalog unregistration

    /// Propagate the catalog's unregistration of worktrees to every receiver
    /// that lists them, through the same removal rules. The removed roots come
    /// from the topology delta, captured before the catalog lost them. A
    /// receiver whose page cannot flush its editors keeps the entry for now:
    /// the unregistered member is already unknown, so it is no longer listed
    /// or reviewed, and the cleanup is retried on the next unregistration.
    func applyCatalogUnregistration(of removedWorktrees: [RemovedWorktreeEntry]) async {
        for removed in removedWorktrees {
            pendingCatalogUnregistrationRootsById[removed.id] =
                DarwinFSEventPathCanonicalizer.canonicalURL(removed.path).path
        }
        for (worktreeId, removedRoot) in pendingCatalogUnregistrationRootsById {
            var settled = true
            for (receiver, record) in navigationAtom.recordsSnapshot() where record.containsMember(worktreeId) {
                let removedEverywhere = await removeUnregisteredMember(
                    worktreeId,
                    removedRoot: removedRoot,
                    from: receiver
                )
                settled = settled && removedEverywhere
            }
            if settled {
                pendingCatalogUnregistrationRootsById.removeValue(forKey: worktreeId)
            }
        }
    }

    private func removeUnregisteredMember(
        _ worktreeId: UUID,
        removedRoot: String,
        from receiver: BridgeReceiver
    ) async -> Bool {
        guard let record = navigationAtom.record(for: receiver) else { return true }
        var roots = memberRoots(of: record)
        roots[worktreeId] = removedRoot
        guard
            case .removed(_, let effect) = BridgeNavigationRules.removingMember(
                worktreeId,
                from: record,
                reason: .catalogUnregistration,
                memberRootsByWorktreeId: roots
            )
        else { return true }
        let generation = beginNavigation(for: receiver)
        if Self.removalReplacesDisplayedContent(effect),
            let presentation = presentationPorts?.mountedPresentation(receiver)
        {
            let preparation = await presentation.prepareActiveEditorsForNavigation()
            guard isCurrentNavigation(generation, for: receiver), preparation.allowsContentToLeave else {
                bridgeNavigationMembershipLogger.info(
                    "Unregistered worktree cleanup pending an unsaved draft in receiver \(receiver.paneId)"
                )
                return false
            }
        }
        guard let currentRecord = navigationAtom.record(for: receiver) else { return true }
        var currentRoots = memberRoots(of: currentRecord)
        currentRoots[worktreeId] = removedRoot
        guard
            case .removed(let updated, let committedEffect) = BridgeNavigationRules.removingMember(
                worktreeId,
                from: currentRecord,
                reason: .catalogUnregistration,
                memberRootsByWorktreeId: currentRoots
            )
        else { return true }
        commitRemoval(updated, effect: committedEffect, for: receiver)
        _ = await persistedOutcome()
        return true
    }

    // MARK: - CWD

    /// An admitted CWD change of a terminal: inject its known worktree into the
    /// terminal's receiver and push the new Files input to the mounted Bridge.
    /// Protection follows the association itself; selections never change.
    func applyAdmittedCWDAssociation(_ knownWorktreeId: UUID?, forTerminalPane paneId: UUID) {
        let receiver = BridgeReceiver.terminal(paneId)
        let before = navigationAtom.record(for: receiver)
        applyKnownCWDAssociation(knownWorktreeId, forTerminalPane: paneId)
        guard navigationAtom.record(for: receiver) != before else { return }
        presentationPorts?.refreshFilesSource(receiver)
    }

    // MARK: - Shared

    private func plannedExplicitRemoval(
        of worktreeId: UUID,
        from record: BridgeNavigationRecord,
        receiver: BridgeReceiver
    ) -> BridgeMemberRemovalOutcome {
        BridgeNavigationRules.removingMember(
            worktreeId,
            from: record,
            reason: .explicitCommand(
                protectedWorktreeId: BridgeNavigationRules.protectedWorktreeId(
                    in: record,
                    currentKnownCWDWorktreeId: presentationPorts?.knownCWDWorktreeId(receiver)
                )
            ),
            memberRootsByWorktreeId: memberRoots(of: record)
        )
    }

    private func commitRemoval(
        _ updated: BridgeNavigationRecord,
        effect: BridgeMemberRemovalEffect,
        for receiver: BridgeReceiver
    ) {
        navigationAtom.setRecord(updated, for: receiver)
        presentationPorts?.refreshFilesSource(receiver)
        if effect.reviewFallback != .unchanged {
            _ = presentationPorts?.replaceReviewSource(receiver, Self.productSurface(for: updated.surface))
        }
    }

    /// Canonical roots of the record's currently known members, the same
    /// roots the Files collection groups by.
    private func memberRoots(of record: BridgeNavigationRecord) -> [UUID: String] {
        Dictionary(
            uniqueKeysWithValues: record.memberWorktreeIds.compactMap { worktreeId in
                knownWorktree(worktreeId).map {
                    (worktreeId, DarwinFSEventPathCanonicalizer.canonicalURL($0.path).path)
                }
            }
        )
    }

    private static func removalReplacesDisplayedContent(_ effect: BridgeMemberRemovalEffect) -> Bool {
        effect.clearedFilesSelection || effect.reviewFallback != .unchanged
    }

    static func productSurface(for surface: BridgeNavigationSurface) -> BridgeProductSurface {
        switch surface {
        case .files: .file
        case .review: .review
        }
    }
}
