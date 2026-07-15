import Foundation

@MainActor
struct WorkspaceStateSnapshotPageCaptureEngine<
    ParticipantID: Hashable & Sendable,
    Item: WorkspaceStateSnapshotIdentifiedItem
> where Item.SnapshotParticipantID == ParticipantID {
    enum CaptureResult {
        case page(
            WorkspaceStateSnapshotPage<ParticipantID, Item>,
            participantInspectionCount: Int,
            scannedItemCount: Int
        )
        case exhausted(participantInspectionCount: Int, scannedItemCount: Int)
        case yielded(
            participantIndex: Int,
            slotCursor: Int,
            participantInspectionCount: Int,
            scannedItemCount: Int
        )
        case rejected(
            WorkspaceStateSnapshotPageTakeRejection<ParticipantID, Item.SnapshotItemID>,
            participantInspectionCount: Int,
            scannedItemCount: Int
        )

        var measuredWork: MainActorMeasuredWork<Self> {
            switch self {
            case .page(let page, let participantInspectionCount, let scannedItemCount):
                MainActorMeasuredWork(
                    value: self,
                    outcome: .succeeded,
                    counts: .init(
                        input: measuredInputCount(
                            participantInspectionCount: participantInspectionCount,
                            scannedItemCount: scannedItemCount
                        ),
                        changedKey: UInt64(page.itemCount)
                    )
                )
            case .exhausted(let participantInspectionCount, let scannedItemCount):
                MainActorMeasuredWork(
                    value: self,
                    outcome: .succeeded,
                    counts: .init(
                        input: measuredInputCount(
                            participantInspectionCount: participantInspectionCount,
                            scannedItemCount: scannedItemCount
                        ),
                        changedKey: 0
                    )
                )
            case .yielded(_, _, let participantInspectionCount, let scannedItemCount):
                MainActorMeasuredWork(
                    value: self,
                    outcome: .succeeded,
                    counts: .init(
                        input: measuredInputCount(
                            participantInspectionCount: participantInspectionCount,
                            scannedItemCount: scannedItemCount
                        ),
                        changedKey: 0
                    )
                )
            case .rejected(_, let participantInspectionCount, let scannedItemCount):
                MainActorMeasuredWork(
                    value: self,
                    outcome: .failed,
                    counts: .init(
                        input: measuredInputCount(
                            participantInspectionCount: participantInspectionCount,
                            scannedItemCount: scannedItemCount
                        ),
                        changedKey: 0
                    )
                )
            }
        }

        private func measuredInputCount(
            participantInspectionCount: Int,
            scannedItemCount: Int
        ) -> UInt64 {
            precondition(participantInspectionCount >= 0 && scannedItemCount >= 0)
            let sum = UInt64(participantInspectionCount).addingReportingOverflow(
                UInt64(scannedItemCount)
            )
            precondition(!sum.overflow, "bounded snapshot work count must be representable")
            return sum.partialValue
        }
    }

    private enum ParticipantCaptureResult {
        case captured(ParticipantCapturePayload)
        case rejected(
            WorkspaceStateSnapshotPageTakeRejection<ParticipantID, Item.SnapshotItemID>,
            scannedItemCount: Int
        )
    }

    private struct ParticipantCapturePayload {
        let items: [CapturedItem]
        let byteCount: Int
        let scannedItemCount: Int
        let nextSlotCursor: Int
        let exhaustedParticipant: Bool
    }

    private struct ParticipantCaptureContext {
        let participant: WorkspaceStateSnapshotPagerParticipant<ParticipantID, Item>
        let slotUpperBound: Int
        let slotCursor: Int
        let lease: WorkspaceStateSnapshotLease
        let limits: WorkspaceStateSnapshotPageLimits
        let maximumScannedItems: Int
        let startedAt: PerformanceMonotonicInstant
    }

    private enum ItemByteValidationResult {
        case accepted(nextPageByteCount: Int)
        case pageFull
        case rejected(
            WorkspaceStateSnapshotPageTakeRejection<ParticipantID, Item.SnapshotItemID>
        )
    }

    private struct CapturedItem {
        let pageItem: WorkspaceStateSnapshotPageItem<ParticipantID, Item>
        let copyToken: WorkspaceStateSnapshotBaseCopyToken
    }

    private let participants: [WorkspaceStateSnapshotPagerParticipant<ParticipantID, Item>]
    private let serviceClock: any PerformanceMonotonicClock

    init(
        participants: [WorkspaceStateSnapshotPagerParticipant<ParticipantID, Item>],
        serviceClock: any PerformanceMonotonicClock
    ) {
        self.participants = participants
        self.serviceClock = serviceClock
    }

    func capturePage(
        participantIndex initialParticipantIndex: Int,
        membershipOffset initialMembershipOffset: Int,
        lease: WorkspaceStateSnapshotLease,
        limits: WorkspaceStateSnapshotPageLimits
    ) -> CaptureResult {
        let startedAt = serviceClock.now()
        var participantIndex = initialParticipantIndex
        var membershipOffset = initialMembershipOffset
        var scannedItemCount = 0
        var participantInspectionCount = 0

        while participantIndex < participants.count {
            if let boundaryResult = captureBoundaryResult(
                participantIndex: participantIndex,
                slotCursor: membershipOffset,
                participantInspectionCount: participantInspectionCount,
                scannedItemCount: scannedItemCount,
                startedAt: startedAt,
                limits: limits
            ) {
                return boundaryResult
            }
            let participant = participants[participantIndex]
            participantInspectionCount += 1
            let slotUpperBound: Int
            switch participant.slotUpperBound(for: lease) {
            case .upperBound(let activeSlotUpperBound):
                slotUpperBound = activeSlotUpperBound
            case .rejected(let rejection):
                return .rejected(
                    .participantRejected(rejection),
                    participantInspectionCount: participantInspectionCount,
                    scannedItemCount: scannedItemCount
                )
            }
            if membershipOffset >= slotUpperBound {
                participantIndex += 1
                membershipOffset = 0
                if participantInspectionCount >= limits.maximumParticipantInspections {
                    return yieldedCapture(
                        participantIndex: participantIndex,
                        slotCursor: membershipOffset,
                        participantInspectionCount: participantInspectionCount,
                        scannedItemCount: scannedItemCount
                    )
                }
                continue
            }

            let participantCapture = captureParticipantItems(
                ParticipantCaptureContext(
                    participant: participant,
                    slotUpperBound: slotUpperBound,
                    slotCursor: membershipOffset,
                    lease: lease,
                    limits: limits,
                    maximumScannedItems: limits.maximumScannedItems - scannedItemCount,
                    startedAt: startedAt
                )
            )
            guard case .captured(let captured) = participantCapture else {
                guard case .rejected(let rejection, let participantScannedItemCount) = participantCapture
                else { preconditionFailure() }
                return .rejected(
                    rejection,
                    participantInspectionCount: participantInspectionCount,
                    scannedItemCount: scannedItemCount + participantScannedItemCount
                )
            }
            scannedItemCount += captured.scannedItemCount
            if captured.items.isEmpty {
                if captured.exhaustedParticipant {
                    participantIndex += 1
                    membershipOffset = 0
                    if participantIndex < participants.count,
                        participantInspectionCount < limits.maximumParticipantInspections,
                        scannedItemCount < limits.maximumScannedItems,
                        !serviceLimitReached(
                            startedAt: startedAt,
                            limit: limits.maximumSynchronousServiceNanoseconds
                        )
                    {
                        continue
                    }
                } else {
                    membershipOffset = captured.nextSlotCursor
                }
                return yieldedCapture(
                    participantIndex: participantIndex,
                    slotCursor: membershipOffset,
                    participantInspectionCount: participantInspectionCount,
                    scannedItemCount: scannedItemCount
                )
            }
            return finishPageCapture(
                captured: captured,
                participant: participant,
                participantIndex: participantIndex,
                lease: lease,
                participantInspectionCount: participantInspectionCount,
                scannedItemCount: scannedItemCount
            )
        }
        return .exhausted(
            participantInspectionCount: participantInspectionCount,
            scannedItemCount: scannedItemCount
        )
    }

    private func captureParticipantItems(
        _ context: ParticipantCaptureContext
    ) -> ParticipantCaptureResult {
        var items: [CapturedItem] = []
        var pageBytes = 0
        var scannedItemCount = 0
        var nextSlotCursor = context.slotCursor
        captureLoop: while nextSlotCursor < context.slotUpperBound {
            guard items.count < context.limits.maximumItems else { break }
            guard scannedItemCount < context.maximumScannedItems else { break }
            if serviceLimitReached(
                startedAt: context.startedAt,
                limit: context.limits.maximumSynchronousServiceNanoseconds
            ) {
                guard !items.isEmpty || scannedItemCount > 0 else {
                    return .rejected(
                        .synchronousServiceLimitReachedWithoutProgress,
                        scannedItemCount: scannedItemCount
                    )
                }
                break
            }

            scannedItemCount += 1
            let captureResult = context.participant.inspectBaseSlot(
                lease: context.lease,
                slotCursor: nextSlotCursor
            )
            let projectedItem: WorkspaceStateSnapshotPagerTypedItem<Item>
            let expectedItemID: Item.SnapshotItemID
            let copyToken: WorkspaceStateSnapshotBaseCopyToken
            let candidateNextSlotCursor: Int
            switch captureResult {
            case .item(let item, let expectedID, let token, let cursor):
                projectedItem = item
                expectedItemID = expectedID
                copyToken = token
                candidateNextSlotCursor = cursor
            case .skipped(let cursor):
                nextSlotCursor = cursor
                continue
            case .exhausted:
                return .captured(
                    ParticipantCapturePayload(
                        items: items,
                        byteCount: pageBytes,
                        scannedItemCount: scannedItemCount,
                        nextSlotCursor: context.slotUpperBound,
                        exhaustedParticipant: true
                    )
                )
            case .rejected(let rejection):
                return .rejected(.participantRejected(rejection), scannedItemCount: scannedItemCount)
            }
            let item = projectedItem.item
            let itemID = item.snapshotItemID
            if let identityRejection =
                WorkspaceStateSnapshotPagerItemValidator.validateProjectedItemIdentity(
                    item,
                    expectedItemID: expectedItemID,
                    participantID: context.participant.participantID
                )
            {
                return .rejected(
                    identityRejection,
                    scannedItemCount: scannedItemCount
                )
            }
            let itemBytes = projectedItem.estimatedByteCount
            switch validateItemBytes(
                itemBytes,
                itemID: itemID,
                participantID: context.participant.participantID,
                pageByteCount: pageBytes,
                maximumBytes: context.limits.maximumBytes
            ) {
            case .accepted(let nextPageByteCount):
                pageBytes = nextPageByteCount
            case .pageFull:
                break captureLoop
            case .rejected(let rejection):
                return .rejected(
                    rejection,
                    scannedItemCount: scannedItemCount
                )
            }
            items.append(
                CapturedItem(
                    pageItem: WorkspaceStateSnapshotPageItem(
                        item: item,
                        byteCount: itemBytes
                    ),
                    copyToken: copyToken
                )
            )
            nextSlotCursor = candidateNextSlotCursor
        }
        return completedParticipantCapture(
            items: items,
            pageBytes: pageBytes,
            scannedItemCount: scannedItemCount,
            nextSlotCursor: nextSlotCursor,
            slotUpperBound: context.slotUpperBound
        )
    }

    private func completedParticipantCapture(
        items: [CapturedItem],
        pageBytes: Int,
        scannedItemCount: Int,
        nextSlotCursor: Int,
        slotUpperBound: Int
    ) -> ParticipantCaptureResult {
        .captured(
            ParticipantCapturePayload(
                items: items,
                byteCount: pageBytes,
                scannedItemCount: scannedItemCount,
                nextSlotCursor: nextSlotCursor,
                exhaustedParticipant: nextSlotCursor >= slotUpperBound
            )
        )
    }

    private func validateItemBytes(
        _ itemBytes: Int,
        itemID: Item.SnapshotItemID,
        participantID: ParticipantID,
        pageByteCount: Int,
        maximumBytes: Int
    ) -> ItemByteValidationResult {
        guard itemBytes >= 0 else {
            return .rejected(
                .invalidItemByteCount(participantID: participantID, itemID: itemID)
            )
        }
        guard itemBytes <= maximumBytes else {
            return .rejected(
                .itemExceedsByteLimit(
                    participantID: participantID,
                    itemID: itemID,
                    itemBytes: itemBytes,
                    maximumBytes: maximumBytes
                )
            )
        }
        let nextPageBytes = pageByteCount.addingReportingOverflow(itemBytes)
        guard !nextPageBytes.overflow else {
            return .rejected(.itemByteCountOverflow)
        }
        guard nextPageBytes.partialValue <= maximumBytes else {
            return .pageFull
        }
        return .accepted(nextPageByteCount: nextPageBytes.partialValue)
    }

    private func captureBoundaryResult(
        participantIndex: Int,
        slotCursor: Int,
        participantInspectionCount: Int,
        scannedItemCount: Int,
        startedAt: PerformanceMonotonicInstant,
        limits: WorkspaceStateSnapshotPageLimits
    ) -> CaptureResult? {
        if participantInspectionCount >= limits.maximumParticipantInspections {
            return .yielded(
                participantIndex: participantIndex,
                slotCursor: slotCursor,
                participantInspectionCount: participantInspectionCount,
                scannedItemCount: scannedItemCount
            )
        }
        guard
            serviceLimitReached(
                startedAt: startedAt,
                limit: limits.maximumSynchronousServiceNanoseconds
            )
        else { return nil }
        guard participantInspectionCount > 0 else {
            return .rejected(
                .synchronousServiceLimitReachedWithoutProgress,
                participantInspectionCount: participantInspectionCount,
                scannedItemCount: scannedItemCount
            )
        }
        return .yielded(
            participantIndex: participantIndex,
            slotCursor: slotCursor,
            participantInspectionCount: participantInspectionCount,
            scannedItemCount: scannedItemCount
        )
    }

    private func yieldedCapture(
        participantIndex: Int,
        slotCursor: Int,
        participantInspectionCount: Int,
        scannedItemCount: Int
    ) -> CaptureResult {
        .yielded(
            participantIndex: participantIndex,
            slotCursor: slotCursor,
            participantInspectionCount: participantInspectionCount,
            scannedItemCount: scannedItemCount
        )
    }

    private func makePage(
        captured: ParticipantCapturePayload,
        participant: WorkspaceStateSnapshotPagerParticipant<ParticipantID, Item>,
        participantIndex: Int,
        lease: WorkspaceStateSnapshotLease,
        pageID: WorkspaceStateSnapshotPageID
    ) -> WorkspaceStateSnapshotPage<ParticipantID, Item> {
        let pageItems = captured.items.map(\.pageItem)
        let nextPosition =
            !captured.exhaustedParticipant
            ? (participantIndex: participantIndex, membershipOffset: captured.nextSlotCursor)
            : (participantIndex: participantIndex + 1, membershipOffset: 0)
        return WorkspaceStateSnapshotPage(
            pageID: pageID,
            lease: lease,
            participantID: participant.participantID,
            items: pageItems,
            itemCount: pageItems.count,
            byteCount: captured.byteCount,
            nextParticipantIndex: nextPosition.participantIndex,
            nextMembershipOffset: nextPosition.membershipOffset,
            exhaustsLease: nextPosition.participantIndex == participants.count
        )
    }

    private func finishPageCapture(
        captured: ParticipantCapturePayload,
        participant: WorkspaceStateSnapshotPagerParticipant<ParticipantID, Item>,
        participantIndex: Int,
        lease: WorkspaceStateSnapshotLease,
        participantInspectionCount: Int,
        scannedItemCount: Int
    ) -> CaptureResult {
        let pageID = WorkspaceStateSnapshotPageID.make()
        if let rejection = markCapturedItemsCopied(
            captured.items,
            by: participant,
            lease: lease,
            pageID: pageID
        ) {
            return .rejected(
                .participantCommitRejected(rejection),
                participantInspectionCount: participantInspectionCount,
                scannedItemCount: scannedItemCount
            )
        }
        let page = makePage(
            captured: captured,
            participant: participant,
            participantIndex: participantIndex,
            lease: lease,
            pageID: pageID
        )
        return .page(
            page,
            participantInspectionCount: participantInspectionCount,
            scannedItemCount: scannedItemCount
        )
    }

    private func markCapturedItemsCopied(
        _ items: [CapturedItem],
        by participant: WorkspaceStateSnapshotPagerParticipant<ParticipantID, Item>,
        lease: WorkspaceStateSnapshotLease,
        pageID: WorkspaceStateSnapshotPageID
    ) -> WorkspaceStateSnapshotParticipantRejection? {
        for item in items {
            let markResult = participant.markBaseValueCopied(
                lease: lease,
                copyToken: item.copyToken,
                pageID: pageID
            )
            guard markResult == .markedCopied else {
                guard case .rejected(let rejection) = markResult else { preconditionFailure() }
                return rejection
            }
        }
        return nil
    }

    private func serviceLimitReached(
        startedAt: PerformanceMonotonicInstant,
        limit: UInt64
    ) -> Bool {
        let now = serviceClock.now()
        guard now >= startedAt else { return true }
        return now.uptimeNanoseconds - startedAt.uptimeNanoseconds >= limit
    }
}
