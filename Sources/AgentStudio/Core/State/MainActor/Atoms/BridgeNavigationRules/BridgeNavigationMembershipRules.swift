import Foundation

/// Why a member is leaving a receiver's collection.
package enum BridgeMemberRemovalReason: Hashable, Sendable {
    /// An explicit removal command. The member protected by the owner's
    /// current known CWD association is refused.
    case explicitCommand(protectedWorktreeId: UUID?)
    /// Agent Studio unregistered the worktree from its catalog. The same
    /// removal transition applies in every receiver containing it; protection
    /// has already been cleared with the pane association.
    case catalogUnregistration
}

/// How Review changed when a member was removed.
package enum BridgeReviewFallback: Hashable, Sendable {
    case unchanged
    /// The next remaining member in collection order (wrapping) with its own
    /// retained comparison, or first-time designation when it has none.
    case switched(toWorktreeId: UUID)
    /// No members remain; Review has no target.
    case emptied
}

package struct BridgeMemberRemovalEffect: Hashable, Sendable {
    /// Retained open entries that belonged to the removed member; they leave
    /// the inventory so they never reappear as loose files.
    package let removedDocuments: [BridgeDocumentLocation]
    package let clearedFilesSelection: Bool
    package let resetFilesFilter: Bool
    package let reviewFallback: BridgeReviewFallback
}

package enum BridgeMemberRemovalOutcome: Hashable, Sendable {
    case removed(BridgeNavigationRecord, effect: BridgeMemberRemovalEffect)
    case refusedProtected
    case notMember
}

package enum BridgeMemberContributionRemoval: Hashable, Sendable {
    case removed(
        BridgeNavigationRecord, effect: BridgeMemberRemovalEffect?, removedContributions: [BridgeLinkContributor])
    case alreadyAbsent
    case refusedProtectedCurrentDirectory
    case refusedNotAuthor
    case staleOwner
    case staleReceiver
}

extension BridgeMemberContributionRemoval {
    package var removesEffectiveMember: Bool {
        guard case .removed(_, let effect, _) = self else { return false }
        return effect != nil
    }
}

package enum BridgePullRequestContributionRemoval: Hashable, Sendable {
    case removed(BridgeNavigationRecord, removedContributions: [BridgeLinkContributor])
    case alreadyAbsent
    case refusedNotAuthor
    case staleOwner
    case staleReceiver
}

extension BridgeNavigationRules {
    /// After a durable link commit, install its membership into the newest UI
    /// projection. A UI action with a later generation keeps its independent
    /// choice, provided that choice is still valid against committed links.
    package static func reconcilingCommittedLinks(
        _ committed: BridgeNavigationRecord,
        with latest: BridgeNavigationRecord,
        removedWorktreeId: UUID?,
        memberRootsByWorktreeId: [UUID: String]
    ) -> BridgeNavigationRecord {
        var merged = committed
        merged.derivedCurrentCWDWorktreeId = latest.derivedCurrentCWDWorktreeId
        let removedLocations: Set<BridgeDocumentLocation>
        if let removedWorktreeId {
            removedLocations = Set(
                documentsOwned(
                    by: removedWorktreeId,
                    in: latest,
                    memberRootsByWorktreeId: memberRootsByWorktreeId
                ))
        } else {
            removedLocations = []
        }
        merged.openedDocuments = latest.openedDocuments.filter { !removedLocations.contains($0.key) }
        let validMembers = Set(merged.effectiveMemberWorktreeIds)
        switch latest.filesFilter {
        case .member(let worktreeId) where !validMembers.contains(worktreeId):
            merged.filesFilter = committed.filesFilter
        default:
            merged.filesFilter = latest.filesFilter
        }
        if let selected = latest.selectedFilesDocument,
            merged.openedDocuments[selected] != nil
        {
            merged.selectedFilesDocument = selected
        } else {
            merged.selectedFilesDocument = nil
        }
        switch latest.reviewSelection {
        case .member(let worktreeId) where !validMembers.contains(worktreeId):
            merged.reviewSelection = committed.reviewSelection
        default:
            merged.reviewSelection = latest.reviewSelection
        }
        merged.reviewComparisonsByWorktreeId = latest.reviewComparisonsByWorktreeId.filter {
            validMembers.contains($0.key)
        }
        merged.surface = latest.surface
        return merged
    }

    /// Revalidate immediately before the effect. Callers may not treat an
    /// earlier observation as permission to remove a contribution.
    package static func addingMemberContribution(
        _ worktreeId: UUID,
        contributor: BridgeLinkContributor,
        addedAt: Date,
        to record: BridgeNavigationRecord
    ) -> (BridgeNavigationRecord, BridgeMemberAddResult) {
        var updated = record
        let contribution = BridgeLinkContribution(addedBy: contributor, addedAt: addedAt)
        guard let index = updated.committedMemberLinks.firstIndex(where: { $0.worktreeId == worktreeId }) else {
            updated.committedMemberLinks.append(BridgeMemberLink(worktreeId: worktreeId, contributions: [contribution]))
            return (updated, .added(effect: .newItem))
        }
        guard !updated.committedMemberLinks[index].contributions.contains(where: { $0.addedBy == contributor }) else {
            return (record, .alreadyPresent)
        }
        updated.committedMemberLinks[index].contributions.append(contribution)
        return (updated, .added(effect: .newContribution))
    }

    package static func removingMemberContribution(
        _ worktreeId: UUID,
        contributor: BridgeLinkContributor,
        from record: BridgeNavigationRecord,
        protectedWorktreeId: UUID?,
        memberRootsByWorktreeId: [UUID: String]
    ) -> BridgeMemberContributionRemoval {
        guard let index = record.committedMemberLinks.firstIndex(where: { $0.worktreeId == worktreeId }) else {
            return .alreadyAbsent
        }
        guard protectedWorktreeId != worktreeId else { return .refusedProtectedCurrentDirectory }
        if contributor == .person {
            let removedContributions = record.committedMemberLinks[index].contributions.map(\.addedBy)
            switch removingMember(
                worktreeId, from: record,
                reason: .explicitCommand(protectedWorktreeId: protectedWorktreeId),
                memberRootsByWorktreeId: memberRootsByWorktreeId
            ) {
            case .removed(let updated, let effect):
                return .removed(updated, effect: effect, removedContributions: removedContributions)
            case .refusedProtected: return .refusedProtectedCurrentDirectory
            case .notMember: return .alreadyAbsent
            }
        }
        var updated = record
        let before = updated.committedMemberLinks[index].contributions.count
        updated.committedMemberLinks[index].contributions.removeAll { $0.addedBy == contributor }
        guard updated.committedMemberLinks[index].contributions.count != before else {
            if case .agent = contributor { return .refusedNotAuthor }
            return .alreadyAbsent
        }
        guard updated.committedMemberLinks[index].contributions.isEmpty else {
            return .removed(updated, effect: nil, removedContributions: [contributor])
        }
        switch removingMember(
            worktreeId, from: record,
            reason: .explicitCommand(protectedWorktreeId: protectedWorktreeId),
            memberRootsByWorktreeId: memberRootsByWorktreeId
        ) {
        case .removed(let removed, let effect):
            return .removed(removed, effect: effect, removedContributions: [contributor])
        case .refusedProtected: return .refusedProtectedCurrentDirectory
        case .notMember: return .alreadyAbsent
        }
    }

    package static func addingPullRequestContribution(
        _ identity: ForgePullRequestIdentity,
        contributor: BridgeLinkContributor,
        addedAt: Date,
        to record: BridgeNavigationRecord
    ) -> (BridgeNavigationRecord, BridgePullRequestReferenceAddResult) {
        var updated = record
        let contribution = BridgeLinkContribution(addedBy: contributor, addedAt: addedAt)
        guard let index = updated.pullRequestLinks.firstIndex(where: { $0.identity == identity }) else {
            updated.pullRequestLinks.append(BridgePullRequestLink(identity: identity, contributions: [contribution]))
            return (updated, .added(effect: .newItem))
        }
        guard !updated.pullRequestLinks[index].contributions.contains(where: { $0.addedBy == contributor }) else {
            return (record, .alreadyPresent)
        }
        updated.pullRequestLinks[index].contributions.append(contribution)
        return (updated, .added(effect: .newContribution))
    }

    package static func removingPullRequestContribution(
        _ identity: ForgePullRequestIdentity,
        contributor: BridgeLinkContributor,
        from record: BridgeNavigationRecord
    ) -> BridgePullRequestContributionRemoval {
        guard let index = record.pullRequestLinks.firstIndex(where: { $0.identity == identity }) else {
            return .alreadyAbsent
        }
        var updated = record
        if contributor == .person {
            let removedContributions = record.pullRequestLinks[index].contributions.map(\.addedBy)
            updated.pullRequestLinks.remove(at: index)
            return .removed(updated, removedContributions: removedContributions)
        }
        let before = updated.pullRequestLinks[index].contributions.count
        updated.pullRequestLinks[index].contributions.removeAll { $0.addedBy == contributor }
        guard updated.pullRequestLinks[index].contributions.count != before else {
            if case .agent = contributor { return .refusedNotAuthor }
            return .alreadyAbsent
        }
        if updated.pullRequestLinks[index].contributions.isEmpty {
            updated.pullRequestLinks.remove(at: index)
        }
        return .removed(updated, removedContributions: [contributor])
    }

    /// The retained open entries owned by `worktreeId` under the current
    /// membership, derived before removal so late classification cannot
    /// reinterpret them as loose files.
    package static func documentsOwned(
        by worktreeId: UUID,
        in record: BridgeNavigationRecord,
        memberRootsByWorktreeId: [UUID: String]
    ) -> [BridgeDocumentLocation] {
        let hasKnownRoot = memberRootsByWorktreeId[worktreeId] != nil
        return record.openedDocuments.compactMap { location, entry in
            if hasKnownRoot {
                let grouping = grouping(
                    of: location,
                    effectiveMemberWorktreeIds: record.effectiveMemberWorktreeIds,
                    memberRootsByWorktreeId: memberRootsByWorktreeId
                )
                return grouping == .member(worktreeId: worktreeId) ? location : nil
            }
            // A root that can no longer be resolved falls back to the admitted
            // provenance evidence rather than guessing by path.
            return entry.provenance?.worktreeId == worktreeId ? location : nil
        }
    }

    /// Remove a member: drop its tree and its retained open entries, clear an
    /// affected Files selection and filter, and apply ordered Review fallback.
    /// Annotation storage, disk content and the repository catalog are outside
    /// this record and are never touched.
    package static func removingMember(
        _ worktreeId: UUID,
        from record: BridgeNavigationRecord,
        reason: BridgeMemberRemovalReason,
        memberRootsByWorktreeId: [UUID: String]
    ) -> BridgeMemberRemovalOutcome {
        guard let removedIndex = record.committedMemberWorktreeIds.firstIndex(of: worktreeId) else {
            return .notMember
        }
        if case .explicitCommand(let protectedWorktreeId) = reason, protectedWorktreeId == worktreeId {
            return .refusedProtected
        }

        var updated = record
        updated.committedMemberLinks.remove(at: removedIndex)
        let (reconciled, effect) = applyingRemovedMemberEffects(
            worktreeId, removedIndex: removedIndex, before: record, after: updated,
            memberRootsByWorktreeId: memberRootsByWorktreeId
        )
        return .removed(reconciled, effect: effect)
    }

    /// A failed app contribution never creates a committed link. When its CWD
    /// moves away, apply the same removal effects to the departed derived
    /// member that a committed member removal would apply.
    package static func reconcilingDepartedDerivedCWD(
        previousDerivedWorktreeID: WorktreeId?,
        in record: BridgeNavigationRecord,
        memberRootsByWorktreeId: [UUID: String]
    ) -> BridgeNavigationRecord {
        guard let previousDerivedWorktreeID,
            previousDerivedWorktreeID != record.derivedCurrentCWDWorktreeId,
            !record.committedMemberWorktreeIds.contains(previousDerivedWorktreeID)
        else { return record }
        var before = record
        before.derivedCurrentCWDWorktreeId = previousDerivedWorktreeID
        guard let removedIndex = before.effectiveMemberWorktreeIds.firstIndex(of: previousDerivedWorktreeID)
        else { return record }
        return applyingRemovedMemberEffects(
            previousDerivedWorktreeID, removedIndex: removedIndex, before: before, after: record,
            memberRootsByWorktreeId: memberRootsByWorktreeId
        ).0
    }

    private static func applyingRemovedMemberEffects(
        _ worktreeId: UUID,
        removedIndex: Int,
        before: BridgeNavigationRecord,
        after: BridgeNavigationRecord,
        memberRootsByWorktreeId: [UUID: String]
    ) -> (BridgeNavigationRecord, BridgeMemberRemovalEffect) {
        let removedDocuments = documentsOwned(
            by: worktreeId, in: before, memberRootsByWorktreeId: memberRootsByWorktreeId
        )
        let removedDocumentSet = Set(removedDocuments)
        var updated = after
        updated.openedDocuments = updated.openedDocuments.filter { !removedDocumentSet.contains($0.key) }
        updated.reviewComparisonsByWorktreeId.removeValue(forKey: worktreeId)

        var clearedFilesSelection = false
        if let selected = updated.selectedFilesDocument, removedDocumentSet.contains(selected) {
            updated.selectedFilesDocument = nil
            clearedFilesSelection = true
        }

        var resetFilesFilter = false
        if updated.filesFilter == .member(worktreeId: worktreeId) {
            updated.filesFilter = .allMembers
            resetFilesFilter = true
        }

        var reviewFallback = BridgeReviewFallback.unchanged
        if updated.reviewSelection == .member(worktreeId: worktreeId) {
            if updated.effectiveMemberWorktreeIds.isEmpty {
                updated.reviewSelection = .unselected
                reviewFallback = .emptied
            } else {
                // Members after the removed one shift down by one, so the
                // same index names the next member; past the end wraps.
                let nextIndex =
                    removedIndex < updated.effectiveMemberWorktreeIds.count ? removedIndex : 0
                let fallbackWorktreeId = updated.effectiveMemberWorktreeIds[nextIndex]
                updated.reviewSelection = .member(worktreeId: fallbackWorktreeId)
                reviewFallback = .switched(toWorktreeId: fallbackWorktreeId)
            }
        }

        return (
            updated,
            BridgeMemberRemovalEffect(
                removedDocuments: removedDocuments,
                clearedFilesSelection: clearedFilesSelection,
                resetFilesFilter: resetFilesFilter,
                reviewFallback: reviewFallback
            )
        )
    }
}
