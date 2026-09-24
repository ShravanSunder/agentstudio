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

package enum BridgeMemberAdditionOutcome: Hashable, Sendable {
    case added(BridgeNavigationRecord)
    case alreadyMember
}

extension BridgeNavigationRules {
    /// Add an already-known worktree to this receiver only. Selections and the
    /// current display are unchanged; duplicate addition has no effect.
    package static func addingMember(
        _ worktreeId: UUID,
        to record: BridgeNavigationRecord
    ) -> BridgeMemberAdditionOutcome {
        guard !record.containsMember(worktreeId) else { return .alreadyMember }
        var updated = record
        updated.memberWorktreeIds.append(worktreeId)
        return .added(updated)
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
        return record.openedDocuments.compactMap { document in
            if hasKnownRoot {
                let grouping = grouping(
                    of: document.location,
                    memberWorktreeIds: record.memberWorktreeIds,
                    memberRootsByWorktreeId: memberRootsByWorktreeId
                )
                return grouping == .member(worktreeId: worktreeId) ? document.location : nil
            }
            // A root that can no longer be resolved falls back to the admitted
            // provenance evidence rather than guessing by path.
            return document.provenance?.worktreeId == worktreeId ? document.location : nil
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
        guard let removedIndex = record.memberWorktreeIds.firstIndex(of: worktreeId) else {
            return .notMember
        }
        if case .explicitCommand(let protectedWorktreeId) = reason, protectedWorktreeId == worktreeId {
            return .refusedProtected
        }

        let removedDocuments = documentsOwned(
            by: worktreeId,
            in: record,
            memberRootsByWorktreeId: memberRootsByWorktreeId
        )
        let removedDocumentSet = Set(removedDocuments)

        var updated = record
        updated.memberWorktreeIds.remove(at: removedIndex)
        updated.openedDocuments.removeAll { removedDocumentSet.contains($0.location) }
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
            if updated.memberWorktreeIds.isEmpty {
                updated.reviewSelection = .unselected
                reviewFallback = .emptied
            } else {
                // Members after the removed one shift down by one, so the
                // same index names the next member; past the end wraps.
                let nextIndex =
                    removedIndex < updated.memberWorktreeIds.count ? removedIndex : 0
                let fallbackWorktreeId = updated.memberWorktreeIds[nextIndex]
                updated.reviewSelection = .member(worktreeId: fallbackWorktreeId)
                reviewFallback = .switched(toWorktreeId: fallbackWorktreeId)
            }
        }

        return .removed(
            updated,
            effect: BridgeMemberRemovalEffect(
                removedDocuments: removedDocuments,
                clearedFilesSelection: clearedFilesSelection,
                resetFilesFilter: resetFilesFilter,
                reviewFallback: reviewFallback
            )
        )
    }
}
