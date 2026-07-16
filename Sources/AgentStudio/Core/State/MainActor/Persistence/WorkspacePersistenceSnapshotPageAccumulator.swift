struct WorkspacePersistenceSnapshotPageSequence: Equatable, Sendable {
    let rawValue: UInt64
}

enum WorkspaceSnapshotPageAccumulationRejection: Equatable, Sendable {
    case alreadyFinished
    case foreignLease
    case staleLease
    case duplicatePageID(WorkspaceStateSnapshotPageID)
    case pageSequenceMismatch(
        expected: WorkspacePersistenceSnapshotPageSequence,
        actual: WorkspacePersistenceSnapshotPageSequence
    )
    case participantRegression(
        previous: WorkspacePersistenceSnapshotParticipantID,
        submitted: WorkspacePersistenceSnapshotParticipantID
    )
    case foreignItem(
        declaredParticipant: WorkspacePersistenceSnapshotParticipantID,
        actualParticipant: WorkspacePersistenceSnapshotParticipantID,
        itemID: WorkspacePersistenceSnapshotItemID
    )
    case invalidPageItemCount(declared: Int, actual: Int)
    case invalidItemByteCount(itemID: WorkspacePersistenceSnapshotItemID, byteCount: Int)
    case invalidPageByteCount(declared: Int, actual: UInt64)
    case pageCountOverflow
    case itemCountOverflow
    case byteCountOverflow
    case pageSequenceOverflow
    case pageCountMismatch(expected: UInt64, actual: UInt64)
    case itemCountMismatch(expected: UInt64, actual: UInt64)
    case byteCountMismatch(expected: UInt64, actual: UInt64)
}

enum WorkspacePersistenceSnapshotPageAppendResult: Equatable, Sendable {
    case accepted(pageID: WorkspaceStateSnapshotPageID)
    case rejected(WorkspaceSnapshotPageAccumulationRejection)
}

enum WorkspacePersistenceSnapshotPageFinishResult: Equatable, Sendable {
    case finished([WorkspacePersistenceSnapshotParticipantItems])
    case rejected(WorkspaceSnapshotPageAccumulationRejection)
}

/// Owns the mutable, off-main grouping of fixed-revision persistence pages.
///
/// Page UUIDs establish identity only. `WorkspacePersistenceSnapshotPageSequence`
/// is the sole page-ordering authority, while participant order is defined by
/// `WorkspacePersistenceSnapshotParticipantID.allCases`.
actor WorkspacePersistenceSnapshotPageAccumulator {
    typealias Page = WorkspaceStateSnapshotPage<
        WorkspacePersistenceSnapshotParticipantID,
        WorkspacePersistenceSnapshotItem
    >

    private enum ParticipantProgress: Sendable {
        case noPagesAccepted
        case accepted(index: Int, participantID: WorkspacePersistenceSnapshotParticipantID)
    }

    private struct Accumulation: Sendable {
        var itemsByParticipantIndex: [[WorkspacePersistenceSnapshotItem]]
        var acceptedPageIDs: Set<WorkspaceStateSnapshotPageID>
        var nextSequence: WorkspacePersistenceSnapshotPageSequence
        var participantProgress: ParticipantProgress
        var pageCount: UInt64
        var itemCount: UInt64
        var byteCount: UInt64
    }

    private enum State: Sendable {
        case accumulating(Accumulation)
        case finished([WorkspacePersistenceSnapshotParticipantItems])
    }

    private let lease: WorkspaceStateSnapshotLease
    private var state: State

    init(lease: WorkspaceStateSnapshotLease) {
        self.lease = lease
        state = .accumulating(
            Accumulation(
                itemsByParticipantIndex: Array(
                    repeating: [],
                    count: WorkspacePersistenceSnapshotParticipantID.allCases.count
                ),
                acceptedPageIDs: [],
                nextSequence: WorkspacePersistenceSnapshotPageSequence(rawValue: 0),
                participantProgress: .noPagesAccepted,
                pageCount: 0,
                itemCount: 0,
                byteCount: 0
            ))
    }

    func append(
        _ page: Page,
        sequence: WorkspacePersistenceSnapshotPageSequence
    ) -> WorkspacePersistenceSnapshotPageAppendResult {
        guard case .accumulating(var accumulation) = state else {
            return .rejected(.alreadyFinished)
        }
        if let rejection = validate(submittedLease: page.lease) {
            return .rejected(rejection)
        }
        guard !accumulation.acceptedPageIDs.contains(page.pageID) else {
            return .rejected(.duplicatePageID(page.pageID))
        }
        guard sequence == accumulation.nextSequence else {
            return .rejected(
                .pageSequenceMismatch(expected: accumulation.nextSequence, actual: sequence)
            )
        }

        let participantIDs = WorkspacePersistenceSnapshotParticipantID.allCases
        guard let participantIndex = participantIDs.firstIndex(of: page.participantID) else {
            preconditionFailure("CaseIterable participant inventory omitted a live participant")
        }
        switch accumulation.participantProgress {
        case .noPagesAccepted:
            break
        case .accepted(let previousIndex, let previousParticipantID):
            guard participantIndex >= previousIndex else {
                return .rejected(
                    .participantRegression(
                        previous: previousParticipantID,
                        submitted: page.participantID
                    )
                )
            }
        }

        guard page.itemCount == page.items.count else {
            return .rejected(
                .invalidPageItemCount(declared: page.itemCount, actual: page.items.count)
            )
        }

        var checkedPageByteCount: UInt64 = 0
        for pageItem in page.items {
            let item = pageItem.item
            guard item.participantID == page.participantID else {
                return .rejected(
                    .foreignItem(
                        declaredParticipant: page.participantID,
                        actualParticipant: item.participantID,
                        itemID: item.itemID
                    )
                )
            }
            guard pageItem.byteCount > 0 else {
                return .rejected(
                    .invalidItemByteCount(itemID: item.itemID, byteCount: pageItem.byteCount)
                )
            }
            let byteCountAddition = checkedPageByteCount.addingReportingOverflow(
                UInt64(pageItem.byteCount)
            )
            guard !byteCountAddition.overflow else { return .rejected(.byteCountOverflow) }
            checkedPageByteCount = byteCountAddition.partialValue
        }
        guard page.byteCount >= 0, UInt64(page.byteCount) == checkedPageByteCount else {
            return .rejected(
                .invalidPageByteCount(declared: page.byteCount, actual: checkedPageByteCount)
            )
        }

        let nextPageCount = accumulation.pageCount.addingReportingOverflow(1)
        guard !nextPageCount.overflow else { return .rejected(.pageCountOverflow) }
        let nextItemCount = accumulation.itemCount.addingReportingOverflow(UInt64(page.items.count))
        guard !nextItemCount.overflow else { return .rejected(.itemCountOverflow) }
        let nextByteCount = accumulation.byteCount.addingReportingOverflow(checkedPageByteCount)
        guard !nextByteCount.overflow else { return .rejected(.byteCountOverflow) }
        let nextSequenceRawValue = sequence.rawValue.addingReportingOverflow(1)
        guard !nextSequenceRawValue.overflow else { return .rejected(.pageSequenceOverflow) }

        accumulation.itemsByParticipantIndex[participantIndex].append(
            contentsOf: page.items.map(\.item)
        )
        accumulation.acceptedPageIDs.insert(page.pageID)
        accumulation.nextSequence = WorkspacePersistenceSnapshotPageSequence(
            rawValue: nextSequenceRawValue.partialValue
        )
        accumulation.participantProgress = .accepted(
            index: participantIndex,
            participantID: page.participantID
        )
        accumulation.pageCount = nextPageCount.partialValue
        accumulation.itemCount = nextItemCount.partialValue
        accumulation.byteCount = nextByteCount.partialValue
        state = .accumulating(accumulation)
        return .accepted(pageID: page.pageID)
    }

    func finish(
        _ receipt: WorkspaceStateSnapshotExhaustionReceipt
    ) -> WorkspacePersistenceSnapshotPageFinishResult {
        guard case .accumulating(let accumulation) = state else {
            return .rejected(.alreadyFinished)
        }
        if let rejection = validate(submittedLease: receipt.lease) {
            return .rejected(rejection)
        }
        guard receipt.pageCount == accumulation.pageCount else {
            return .rejected(
                .pageCountMismatch(
                    expected: accumulation.pageCount,
                    actual: receipt.pageCount
                )
            )
        }
        guard receipt.itemCount == accumulation.itemCount else {
            return .rejected(
                .itemCountMismatch(
                    expected: accumulation.itemCount,
                    actual: receipt.itemCount
                )
            )
        }
        guard receipt.byteCount == accumulation.byteCount else {
            return .rejected(
                .byteCountMismatch(
                    expected: accumulation.byteCount,
                    actual: receipt.byteCount
                )
            )
        }

        let participantIDs = WorkspacePersistenceSnapshotParticipantID.allCases
        let participantItems = participantIDs.enumerated().map { participantIndex, participantID in
            WorkspacePersistenceSnapshotParticipantItems(
                participantID: participantID,
                items: accumulation.itemsByParticipantIndex[participantIndex]
            )
        }
        state = .finished(participantItems)
        return .finished(participantItems)
    }

    private func validate(
        submittedLease: WorkspaceStateSnapshotLease
    ) -> WorkspaceSnapshotPageAccumulationRejection? {
        guard submittedLease.pagerIdentity == lease.pagerIdentity else { return .foreignLease }
        guard submittedLease == lease else { return .staleLease }
        return nil
    }
}
