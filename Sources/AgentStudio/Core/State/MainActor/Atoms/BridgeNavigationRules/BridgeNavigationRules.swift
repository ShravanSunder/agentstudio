import Foundation

/// Pure navigation transitions for one receiving Bridge.
///
/// Every function maps a record plus explicit inputs to a new record and a
/// typed outcome. Nothing here performs I/O, reads atoms or consults focus:
/// the navigation handler supplies canonical member roots, the current known
/// CWD association and admitted documents. Files and Review selections are
/// independent — a Files transition never rewrites the Review selection or
/// comparison memory, and a Review transition never rewrites the Files
/// selection.
package enum BridgeNavigationRules {
    // MARK: - Seeding and CWD association

    /// The first record of a receiver: seeded from the owner terminal's known
    /// worktree when one exists, otherwise empty.
    package static func seededRecord(knownTerminalWorktreeId: UUID?) -> BridgeNavigationRecord {
        guard let knownTerminalWorktreeId else { return .empty }
        return BridgeNavigationRecord(
            memberWorktreeIds: [knownTerminalWorktreeId],
            reviewSelection: .member(worktreeId: knownTerminalWorktreeId)
        )
    }

    /// Inject the current known CWD worktree as a member when absent. Neither
    /// selection changes and previous members stay listed.
    package static func injectingKnownCWDWorktree(
        _ knownCWDWorktreeId: UUID?,
        into record: BridgeNavigationRecord
    ) -> BridgeNavigationRecord {
        guard let knownCWDWorktreeId, !record.containsMember(knownCWDWorktreeId) else {
            return record
        }
        var updated = record
        updated.memberWorktreeIds.append(knownCWDWorktreeId)
        return updated
    }

    /// Protection is derived from the owner's current known CWD association:
    /// only that member is protected, and nothing is protected without one.
    package static func protectedWorktreeId(
        in record: BridgeNavigationRecord,
        currentKnownCWDWorktreeId: UUID?
    ) -> UUID? {
        guard let currentKnownCWDWorktreeId, record.containsMember(currentKnownCWDWorktreeId) else {
            return nil
        }
        return currentKnownCWDWorktreeId
    }

    // MARK: - Grouping

    /// Classify a document by canonical containment in the receiver's member
    /// roots. The deepest containing root wins; equal deepest roots are
    /// ambiguous rather than guessed.
    package static func grouping(
        of location: BridgeDocumentLocation,
        memberWorktreeIds: [UUID],
        memberRootsByWorktreeId: [UUID: String]
    ) -> BridgeDocumentGrouping {
        var deepestRootLength = -1
        var deepestMembers: [UUID] = []
        for worktreeId in memberWorktreeIds {
            guard let root = memberRootsByWorktreeId[worktreeId],
                location.isContained(inCanonicalRoot: root)
            else {
                continue
            }
            if root.count > deepestRootLength {
                deepestRootLength = root.count
                deepestMembers = [worktreeId]
            } else if root.count == deepestRootLength {
                deepestMembers.append(worktreeId)
            }
        }
        switch deepestMembers.count {
        case 0:
            return .loose
        case 1:
            return .member(worktreeId: deepestMembers[0])
        default:
            return .ambiguous(worktreeIds: deepestMembers)
        }
    }

    // MARK: - Opened-document inventory

    /// Add a document to the inventory, or reuse the existing entry for the
    /// same canonical location. The displayed selection never changes here.
    package static func admitting(
        _ document: BridgeOpenedDocument,
        into record: BridgeNavigationRecord
    ) -> BridgeDocumentAdmissionTransition {
        if let existing = record.openedDocument(at: document.location) {
            return BridgeDocumentAdmissionTransition(record: record, disposition: .reused(existing))
        }
        var updated = record
        updated.openedDocuments.append(document)
        return BridgeDocumentAdmissionTransition(record: updated, disposition: .appended)
    }

    /// Select an inventory document in Files and display Files. The Review
    /// selection and comparison memory are untouched.
    package static func activatingFilesDocument(
        _ location: BridgeDocumentLocation,
        in record: BridgeNavigationRecord
    ) -> BridgeFilesActivationOutcome {
        guard record.openedDocument(at: location) != nil else { return .notInInventory }
        var updated = record
        updated.selectedFilesDocument = location
        updated.surface = .files
        return .activated(updated)
    }

    /// Return to Files with its retained document.
    package static func showingFiles(in record: BridgeNavigationRecord) -> BridgeNavigationRecord {
        var updated = record
        updated.surface = .files
        return updated
    }

    /// Remove an inventory entry. Disk content and annotations are untouched.
    package static func closingDocument(
        _ location: BridgeDocumentLocation,
        in record: BridgeNavigationRecord
    ) -> BridgeDocumentCloseOutcome {
        guard record.openedDocument(at: location) != nil else { return .notOpen }
        var updated = record
        updated.openedDocuments.removeAll { $0.location == location }
        let clearedSelection = updated.selectedFilesDocument == location
        if clearedSelection {
            updated.selectedFilesDocument = nil
        }
        return .closed(updated, clearedFilesSelection: clearedSelection)
    }

    /// Narrow (or widen) the Files filter. Membership is unchanged.
    package static func applyingFilesFilter(
        _ filter: BridgeFilesFilter,
        in record: BridgeNavigationRecord
    ) -> BridgeMemberScopedOutcome {
        if case .member(let worktreeId) = filter, !record.containsMember(worktreeId) {
            return .notMember
        }
        var updated = record
        updated.filesFilter = filter
        return .applied(updated)
    }

    // MARK: - Review

    /// Select a member for Review without changing the displayed surface.
    package static func selectingReviewWorktree(
        _ worktreeId: UUID,
        in record: BridgeNavigationRecord
    ) -> BridgeMemberScopedOutcome {
        guard record.containsMember(worktreeId) else { return .notMember }
        var updated = record
        updated.reviewSelection = .member(worktreeId: worktreeId)
        return .applied(updated)
    }

    /// Review one member with an explicit comparison, or with its retained
    /// comparison when none is requested, and display Review.
    package static func activatingReview(
        of worktreeId: UUID,
        comparison: WorkspaceBaseline?,
        in record: BridgeNavigationRecord
    ) -> BridgeMemberScopedOutcome {
        guard record.containsMember(worktreeId) else { return .notMember }
        var updated = record
        updated.reviewSelection = .member(worktreeId: worktreeId)
        if let comparison {
            updated.reviewComparisonsByWorktreeId[worktreeId] = comparison
        }
        updated.surface = .review
        return .applied(updated)
    }

    /// Remember a member's comparison choice (for example from the existing
    /// contribution-target designation) without changing either selection.
    package static func recordingReviewComparison(
        _ comparison: WorkspaceBaseline,
        for worktreeId: UUID,
        in record: BridgeNavigationRecord
    ) -> BridgeMemberScopedOutcome {
        guard record.containsMember(worktreeId) else { return .notMember }
        var updated = record
        updated.reviewComparisonsByWorktreeId[worktreeId] = comparison
        return .applied(updated)
    }
}

// MARK: - Outcomes

package struct BridgeDocumentAdmissionTransition: Hashable, Sendable {
    package enum Disposition: Hashable, Sendable {
        case appended
        case reused(BridgeOpenedDocument)
    }

    package let record: BridgeNavigationRecord
    package let disposition: Disposition
}

package enum BridgeFilesActivationOutcome: Hashable, Sendable {
    case activated(BridgeNavigationRecord)
    case notInInventory
}

package enum BridgeDocumentCloseOutcome: Hashable, Sendable {
    case closed(BridgeNavigationRecord, clearedFilesSelection: Bool)
    case notOpen
}

package enum BridgeMemberScopedOutcome: Hashable, Sendable {
    case applied(BridgeNavigationRecord)
    case notMember
}
