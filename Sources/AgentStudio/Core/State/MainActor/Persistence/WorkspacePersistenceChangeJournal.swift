import Foundation

enum WorkspacePersistenceChange: Equatable, Sendable {
    case insert(WorkspacePersistenceSnapshotItem, estimatedByteCount: Int)
    case replace(WorkspacePersistenceSnapshotItem, estimatedByteCount: Int)
    case tombstone(WorkspacePersistenceSnapshotItemID)

    var itemID: WorkspacePersistenceSnapshotItemID {
        switch self {
        case .insert(let item, _), .replace(let item, _): item.itemID
        case .tombstone(let itemID): itemID
        }
    }

    var estimatedByteCount: Int {
        switch self {
        case .insert(_, let estimatedByteCount), .replace(_, let estimatedByteCount):
            estimatedByteCount
        case .tombstone:
            32
        }
    }
}

enum WorkspacePersistenceChangeSetValidationRejection: Equatable, Sendable {
    case empty
    case duplicateItemID(WorkspacePersistenceSnapshotItemID)
    case nonPositiveEstimatedByteCount(WorkspacePersistenceSnapshotItemID)
    case estimatedByteCountOverflow
}

enum WorkspacePersistenceChangeSetValidationResult: Equatable, Sendable {
    case valid(WorkspacePersistenceChangeSet)
    case rejected(WorkspacePersistenceChangeSetValidationRejection)
}

struct WorkspacePersistenceChangeSet: Equatable, Sendable {
    let revision: WorkspacePersistenceRevision
    let changes: [WorkspacePersistenceChange]
    let estimatedByteCount: Int

    private init(
        revision: WorkspacePersistenceRevision,
        changes: [WorkspacePersistenceChange],
        estimatedByteCount: Int
    ) {
        self.revision = revision
        self.changes = changes
        self.estimatedByteCount = estimatedByteCount
    }

    static func validated(
        revision: WorkspacePersistenceRevision,
        changes: [WorkspacePersistenceChange]
    ) -> WorkspacePersistenceChangeSetValidationResult {
        guard !changes.isEmpty else { return .rejected(.empty) }
        var itemIDs = Set<WorkspacePersistenceSnapshotItemID>()
        var totalEstimatedByteCount = 0
        for change in changes {
            guard itemIDs.insert(change.itemID).inserted else {
                return .rejected(.duplicateItemID(change.itemID))
            }
            guard change.estimatedByteCount > 0 else {
                return .rejected(.nonPositiveEstimatedByteCount(change.itemID))
            }
            let addition = totalEstimatedByteCount.addingReportingOverflow(change.estimatedByteCount)
            guard !addition.overflow else { return .rejected(.estimatedByteCountOverflow) }
            totalEstimatedByteCount = addition.partialValue
        }
        return .valid(
            Self(
                revision: revision,
                changes: changes,
                estimatedByteCount: totalEstimatedByteCount
            )
        )
    }
}

enum WorkspacePersistenceChangeJournalLimitKind: Equatable, Sendable {
    case changeSetCount
    case estimatedByteCount
}

enum WorkspacePersistenceJournalLimitsValidation: Equatable, Sendable {
    case valid(WorkspacePersistenceChangeJournalLimits)
    case rejectedNonPositive(WorkspacePersistenceChangeJournalLimitKind)
}

struct WorkspacePersistenceChangeJournalLimits: Equatable, Sendable {
    let maximumChangeSetCount: Int
    let maximumEstimatedBytes: Int

    private init(maximumChangeSetCount: Int, maximumEstimatedBytes: Int) {
        self.maximumChangeSetCount = maximumChangeSetCount
        self.maximumEstimatedBytes = maximumEstimatedBytes
    }

    static func validated(
        maximumChangeSetCount: Int,
        maximumEstimatedBytes: Int
    ) -> WorkspacePersistenceJournalLimitsValidation {
        guard maximumChangeSetCount > 0 else { return .rejectedNonPositive(.changeSetCount) }
        guard maximumEstimatedBytes > 0 else { return .rejectedNonPositive(.estimatedByteCount) }
        return .valid(
            Self(
                maximumChangeSetCount: maximumChangeSetCount,
                maximumEstimatedBytes: maximumEstimatedBytes
            )
        )
    }
}

enum WorkspacePersistenceChangeJournalAppendRejection: Equatable, Sendable {
    case stale(
        newestRevision: WorkspacePersistenceRevision,
        submittedRevision: WorkspacePersistenceRevision
    )
    case gap(
        newestRevision: WorkspacePersistenceRevision,
        submittedRevision: WorkspacePersistenceRevision
    )
    case changeSetExceedsByteLimit(
        revision: WorkspacePersistenceRevision,
        estimatedByteCount: Int,
        maximumEstimatedBytes: Int
    )
    case retainedEstimatedByteCountOverflow(
        retainedEstimatedByteCount: Int,
        appendingEstimatedByteCount: Int
    )
}

struct WorkspacePersistenceChangeJournalAppendReceipt: Equatable, Sendable {
    let appendedRevision: WorkspacePersistenceRevision
    let evictedRevisions: [WorkspacePersistenceRevision]
    let oldestRevision: WorkspacePersistenceRevision
    let newestRevision: WorkspacePersistenceRevision
    let retainedChangeSetCount: Int
    let retainedEstimatedByteCount: Int
}

enum WorkspacePersistenceChangeJournalAppendResult: Equatable, Sendable {
    case appended(WorkspacePersistenceChangeJournalAppendReceipt)
    case rejected(WorkspacePersistenceChangeJournalAppendRejection)
}

enum WorkspacePersistenceChangeJournalReplayRejection: Equatable, Sendable {
    case emptyJournal
    case invalidRange(
        fromRevision: WorkspacePersistenceRevision,
        throughRevision: WorkspacePersistenceRevision
    )
    case stale(
        requestedThroughRevision: WorkspacePersistenceRevision,
        oldestRetainedRevision: WorkspacePersistenceRevision
    )
    case evicted(
        requestedFromRevision: WorkspacePersistenceRevision,
        oldestRetainedRevision: WorkspacePersistenceRevision
    )
    case future(
        requestedThroughRevision: WorkspacePersistenceRevision,
        newestRetainedRevision: WorkspacePersistenceRevision
    )
    case retainedRangeGap(
        requestedFromRevision: WorkspacePersistenceRevision,
        requestedThroughRevision: WorkspacePersistenceRevision
    )
}

enum WorkspacePersistenceChangeJournalReplayResult: Equatable, Sendable {
    case replayed([WorkspacePersistenceChangeSet])
    case rejected(WorkspacePersistenceChangeJournalReplayRejection)
}

@MainActor
final class WorkspacePersistenceChangeJournal {
    private static let minimumCompactionPrefixCount = 64

    let limits: WorkspacePersistenceChangeJournalLimits
    private(set) var retainedEstimatedByteCount = 0
    private var retainedChangeSets: [WorkspacePersistenceChangeSet] = []
    private var retainedHeadIndex = 0

    var oldestRevision: WorkspacePersistenceRevision? {
        guard retainedHeadIndex < retainedChangeSets.count else { return nil }
        return retainedChangeSets[retainedHeadIndex].revision
    }

    var newestRevision: WorkspacePersistenceRevision? {
        retainedChangeSets.last?.revision
    }

    var retainedChangeSetCount: Int {
        retainedChangeSets.count - retainedHeadIndex
    }

    init(limits: WorkspacePersistenceChangeJournalLimits) {
        self.limits = limits
    }

    func append(
        _ changeSet: WorkspacePersistenceChangeSet
    ) -> WorkspacePersistenceChangeJournalAppendResult {
        guard changeSet.estimatedByteCount <= limits.maximumEstimatedBytes else {
            return .rejected(
                .changeSetExceedsByteLimit(
                    revision: changeSet.revision,
                    estimatedByteCount: changeSet.estimatedByteCount,
                    maximumEstimatedBytes: limits.maximumEstimatedBytes
                )
            )
        }
        let newestRevision = self.newestRevision ?? .zero
        guard changeSet.revision > newestRevision else {
            return .rejected(
                .stale(
                    newestRevision: newestRevision,
                    submittedRevision: changeSet.revision
                )
            )
        }
        let nextRawValue = newestRevision.rawValue.addingReportingOverflow(1)
        guard !nextRawValue.overflow, changeSet.revision.rawValue == nextRawValue.partialValue else {
            return .rejected(
                .gap(
                    newestRevision: newestRevision,
                    submittedRevision: changeSet.revision
                )
            )
        }

        let nextRetainedEstimatedByteCount = retainedEstimatedByteCount.addingReportingOverflow(
            changeSet.estimatedByteCount
        )
        guard !nextRetainedEstimatedByteCount.overflow else {
            return .rejected(
                .retainedEstimatedByteCountOverflow(
                    retainedEstimatedByteCount: retainedEstimatedByteCount,
                    appendingEstimatedByteCount: changeSet.estimatedByteCount
                )
            )
        }

        retainedChangeSets.append(changeSet)
        retainedEstimatedByteCount = nextRetainedEstimatedByteCount.partialValue
        var evictedRevisions: [WorkspacePersistenceRevision] = []
        while retainedChangeSetCount > limits.maximumChangeSetCount
            || retainedEstimatedByteCount > limits.maximumEstimatedBytes
        {
            let evicted = retainedChangeSets[retainedHeadIndex]
            retainedHeadIndex += 1
            retainedEstimatedByteCount -= evicted.estimatedByteCount
            evictedRevisions.append(evicted.revision)
        }
        compactEvictedPrefixIfNeeded()
        guard let oldestRevision = self.oldestRevision, let newestRevision = self.newestRevision else {
            preconditionFailure("accepted journal append must retain its change set")
        }
        return .appended(
            WorkspacePersistenceChangeJournalAppendReceipt(
                appendedRevision: changeSet.revision,
                evictedRevisions: evictedRevisions,
                oldestRevision: oldestRevision,
                newestRevision: newestRevision,
                retainedChangeSetCount: retainedChangeSetCount,
                retainedEstimatedByteCount: retainedEstimatedByteCount
            )
        )
    }

    func replay(
        from fromRevision: WorkspacePersistenceRevision,
        through throughRevision: WorkspacePersistenceRevision
    ) -> WorkspacePersistenceChangeJournalReplayResult {
        guard fromRevision <= throughRevision else {
            return .rejected(
                .invalidRange(fromRevision: fromRevision, throughRevision: throughRevision)
            )
        }
        guard let oldestRevision, let newestRevision else { return .rejected(.emptyJournal) }
        guard throughRevision >= oldestRevision else {
            return .rejected(
                .stale(
                    requestedThroughRevision: throughRevision,
                    oldestRetainedRevision: oldestRevision
                )
            )
        }
        guard fromRevision >= oldestRevision else {
            return .rejected(
                .evicted(
                    requestedFromRevision: fromRevision,
                    oldestRetainedRevision: oldestRevision
                )
            )
        }
        guard throughRevision <= newestRevision else {
            return .rejected(
                .future(
                    requestedThroughRevision: throughRevision,
                    newestRetainedRevision: newestRevision
                )
            )
        }
        let replayed = retainedChangeSets[retainedHeadIndex...].filter { changeSet in
            changeSet.revision >= fromRevision && changeSet.revision <= throughRevision
        }
        guard replayed.first?.revision == fromRevision, replayed.last?.revision == throughRevision else {
            return .rejected(
                .retainedRangeGap(
                    requestedFromRevision: fromRevision,
                    requestedThroughRevision: throughRevision
                )
            )
        }
        return .replayed(replayed)
    }

    private func compactEvictedPrefixIfNeeded() {
        guard retainedHeadIndex >= Self.minimumCompactionPrefixCount else { return }
        guard retainedHeadIndex >= retainedChangeSets.count / 2 else { return }
        retainedChangeSets = Array(retainedChangeSets[retainedHeadIndex...])
        retainedHeadIndex = 0
    }
}
