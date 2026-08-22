import Foundation

struct RepoExplorerNativePlanPreflight: Equatable, Sendable {
    let lifetimeID: RepoExplorerMaterializationHostLifetimeID
    let demandEpoch: UInt64
    let requestGeneration: UInt64
    let oldRevision: UInt64
    let oldCount: Int
    let oldFingerprint: RepoExplorerMaterializationFingerprint
}

struct RepoExplorerNativeEqualPlan: Equatable, Sendable {
    let preflight: RepoExplorerNativePlanPreflight
    let newRevision: UInt64
    let rowCount: Int
    let membershipFingerprint: RepoExplorerMaterializationFingerprint
}

struct RepoExplorerNativeChangedPlan: Equatable, Sendable {
    let preflight: RepoExplorerNativePlanPreflight
    let proposedRevision: UInt64
    let newCount: Int
    let newFingerprint: RepoExplorerMaterializationFingerprint
    let presentation: RepoExplorerNativePresentationUpdate
}

enum RepoExplorerNativePresentationUpdate: Equatable, Sendable {
    case changedEmptyToEmpty(RepoExplorerRowlessPresentation)
    case emptyToContent(RepoExplorerNativeTableUpdatePlan)
    case contentToEmpty(RepoExplorerRowlessPresentation)
    case contentToContent(RepoExplorerNativeTableUpdatePlan)
}

struct RepoExplorerNativeChangedPlanTemplatePayload: Equatable, Sendable {
    let newCount: Int
    let newFingerprint: RepoExplorerMaterializationFingerprint
    let presentation: RepoExplorerNativePresentationUpdate

    fileprivate init(
        newCount: Int,
        newFingerprint: RepoExplorerMaterializationFingerprint,
        presentation: RepoExplorerNativePresentationUpdate
    ) {
        self.newCount = newCount
        self.newFingerprint = newFingerprint
        self.presentation = presentation
    }
}

enum RepoExplorerNativeTableUpdatePlan: Equatable, Sendable {
    case content(RepoExplorerNativeContentUpdatePlan)
    case membership(RepoExplorerNativeMembershipUpdatePlan)
}

struct RepoExplorerNativeContentUpdatePlan: Equatable, Sendable {
    let rowCount: Int
    let membershipFingerprint: RepoExplorerMaterializationFingerprint
    let reloadRowsInNewSpace: IndexSet
    let heightReloadRowsInNewSpace: IndexSet
}

struct RepoExplorerNativeRowMove: Equatable, Sendable {
    let rowID: RepoExplorerRowID
    let oldIndex: Int
    let newIndex: Int
}

struct RepoExplorerNativeMembershipUpdatePlan: Equatable, Sendable {
    let oldCount: Int
    let newCount: Int
    let oldMembershipFingerprint: RepoExplorerMaterializationFingerprint
    let newMembershipFingerprint: RepoExplorerMaterializationFingerprint
    let removeRowsInOldSpace: IndexSet
    let insertRowsInNewSpace: IndexSet
    let movesFromOldToNewSpace: [RepoExplorerNativeRowMove]
    let reloadRowsInNewSpace: IndexSet
    let heightReloadRowsInNewSpace: IndexSet
}

struct RepoExplorerNativeUpdatePlan: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case equal(RepoExplorerNativeEqualPlan)
        case changed(RepoExplorerNativeChangedPlan)
    }

    enum ValidationError: Error, Equatable {
        case baselineFingerprintMismatch
        case candidateFingerprintMismatch
        case duplicateBaselineRowID
        case duplicateCandidateRowID
        case revisionOverflow
        case malformedMembershipUpdate
        case malformedContentUpdate
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    static func validating(
        baseline: RepoExplorerMaterializationBaseline,
        candidate: RepoExplorerMaterializationPresentation,
        requestGeneration: UInt64
    ) -> Result<Self, ValidationError> {
        guard presentationFingerprintIsValid(baseline.presentation) else {
            return .failure(.baselineFingerprintMismatch)
        }
        guard presentationFingerprintIsValid(candidate) else {
            return .failure(.candidateFingerprintMismatch)
        }
        guard hasUniqueRowIDs(baseline.presentation.contentSnapshot) else {
            return .failure(.duplicateBaselineRowID)
        }
        guard hasUniqueRowIDs(candidate.contentSnapshot) else {
            return .failure(.duplicateCandidateRowID)
        }

        let preflight = RepoExplorerNativePlanPreflight(
            lifetimeID: baseline.lifetimeID,
            demandEpoch: baseline.demandEpoch,
            requestGeneration: requestGeneration,
            oldRevision: baseline.revision,
            oldCount: baseline.rowCount,
            oldFingerprint: baseline.fingerprint
        )
        if baseline.presentation == candidate {
            return .success(
                Self(
                    kind: .equal(
                        RepoExplorerNativeEqualPlan(
                            preflight: preflight,
                            newRevision: baseline.revision,
                            rowCount: baseline.rowCount,
                            membershipFingerprint: baseline.fingerprint
                        )
                    )
                )
            )
        }

        let (proposedRevision, overflow) = baseline.revision.addingReportingOverflow(1)
        guard !overflow else { return .failure(.revisionOverflow) }

        let presentationUpdate: RepoExplorerNativePresentationUpdate
        switch (baseline.presentation, candidate) {
        case (.rowless, .rowless(let target)):
            presentationUpdate = .changedEmptyToEmpty(target)
        case (.rowless, .content(let newSnapshot, _)):
            let tablePlan = makeTableUpdatePlan(
                oldSnapshot: .empty,
                newSnapshot: newSnapshot,
                oldFingerprint: .make(snapshot: .empty),
                newFingerprint: candidate.fingerprint
            )
            guard validate(tablePlan, oldSnapshot: .empty, newSnapshot: newSnapshot) else {
                return .failure(.malformedMembershipUpdate)
            }
            presentationUpdate = .emptyToContent(tablePlan)
        case (.content, .rowless(let target)):
            presentationUpdate = .contentToEmpty(target)
        case (
            .content(let oldSnapshot, let oldFingerprint),
            .content(let newSnapshot, let newFingerprint)
        ):
            let tablePlan = makeTableUpdatePlan(
                oldSnapshot: oldSnapshot,
                newSnapshot: newSnapshot,
                oldFingerprint: oldFingerprint,
                newFingerprint: newFingerprint
            )
            guard validate(tablePlan, oldSnapshot: oldSnapshot, newSnapshot: newSnapshot) else {
                return .failure(
                    oldSnapshot.rows.map(\.id) == newSnapshot.rows.map(\.id)
                        ? .malformedContentUpdate : .malformedMembershipUpdate
                )
            }
            presentationUpdate = .contentToContent(tablePlan)
        }

        return .success(
            Self(
                kind: .changed(
                    RepoExplorerNativeChangedPlan(
                        preflight: preflight,
                        proposedRevision: proposedRevision,
                        newCount: candidate.rowCount,
                        newFingerprint: candidate.fingerprint,
                        presentation: presentationUpdate
                    )
                )
            )
        )
    }

    func preflightMatches(
        baseline: RepoExplorerMaterializationBaseline,
        requestGeneration: UInt64
    ) -> Bool {
        let preflight: RepoExplorerNativePlanPreflight
        switch kind {
        case .equal(let equal): preflight = equal.preflight
        case .changed(let changed): preflight = changed.preflight
        }
        return preflight.lifetimeID == baseline.lifetimeID
            && preflight.demandEpoch == baseline.demandEpoch
            && preflight.requestGeneration == requestGeneration
            && preflight.oldRevision == baseline.revision
            && preflight.oldCount == baseline.rowCount
            && preflight.oldFingerprint == baseline.fingerprint
    }

    func matchesDelivery(
        baseline: RepoExplorerMaterializationBaseline,
        presentation: RepoExplorerMaterializationPresentation,
        requestGeneration: UInt64,
        visibleGeneration: UInt64,
        expectedRevision: UInt64,
        proposedRevision: UInt64
    ) -> Bool {
        guard
            preflightMatches(
                baseline: baseline,
                requestGeneration: requestGeneration
            ),
            visibleGeneration == requestGeneration,
            expectedRevision == baseline.revision
        else {
            return false
        }

        switch kind {
        case .equal(let equal):
            return proposedRevision == equal.newRevision
                && equal.newRevision == baseline.revision
                && equal.rowCount == presentation.rowCount
                && equal.membershipFingerprint == presentation.fingerprint
                && presentation.hasSameVisibleIdentity(as: baseline.presentation)
        case .changed(let changed):
            guard proposedRevision == changed.proposedRevision,
                changed.newCount == presentation.rowCount,
                changed.newFingerprint == presentation.fingerprint
            else {
                return false
            }
            return changedPresentationMatches(
                changed.presentation,
                baseline: baseline.presentation,
                candidate: presentation
            )
        }
    }

    func tableUpdatePlan() -> RepoExplorerNativeTableUpdatePlan? {
        guard case .changed(let changed) = kind else { return nil }
        switch changed.presentation {
        case .emptyToContent(let tablePlan), .contentToContent(let tablePlan):
            return tablePlan
        case .changedEmptyToEmpty, .contentToEmpty:
            return nil
        }
    }

    func sealedChangedTemplatePayload() -> RepoExplorerNativeChangedPlanTemplatePayload? {
        guard case .changed(let changed) = kind else { return nil }
        return RepoExplorerNativeChangedPlanTemplatePayload(
            newCount: changed.newCount,
            newFingerprint: changed.newFingerprint,
            presentation: changed.presentation
        )
    }

    static func instantiating(
        payload: RepoExplorerNativeChangedPlanTemplatePayload,
        baseline: RepoExplorerMaterializationBaseline,
        requestGeneration: UInt64
    ) -> Result<Self, ValidationError> {
        let (proposedRevision, overflow) = baseline.revision.addingReportingOverflow(1)
        guard !overflow else { return .failure(.revisionOverflow) }
        return .success(
            Self(
                kind: .changed(
                    RepoExplorerNativeChangedPlan(
                        preflight: RepoExplorerNativePlanPreflight(
                            lifetimeID: baseline.lifetimeID,
                            demandEpoch: baseline.demandEpoch,
                            requestGeneration: requestGeneration,
                            oldRevision: baseline.revision,
                            oldCount: baseline.rowCount,
                            oldFingerprint: baseline.fingerprint
                        ),
                        proposedRevision: proposedRevision,
                        newCount: payload.newCount,
                        newFingerprint: payload.newFingerprint,
                        presentation: payload.presentation
                    )
                )
            )
        )
    }

    private func changedPresentationMatches(
        _ update: RepoExplorerNativePresentationUpdate,
        baseline: RepoExplorerMaterializationPresentation,
        candidate: RepoExplorerMaterializationPresentation
    ) -> Bool {
        switch (update, baseline, candidate) {
        case (.changedEmptyToEmpty(let target), .rowless, .rowless(let candidateTarget)):
            target == candidateTarget
        case (.emptyToContent(let tablePlan), .rowless, .content):
            tablePlanMatchesCandidate(tablePlan, candidate: candidate)
        case (.contentToEmpty(let target), .content, .rowless(let candidateTarget)):
            target == candidateTarget
        case (.contentToContent(let tablePlan), .content, .content):
            tablePlanMatchesCandidate(tablePlan, candidate: candidate)
        default:
            false
        }
    }

    private func tablePlanMatchesCandidate(
        _ tablePlan: RepoExplorerNativeTableUpdatePlan,
        candidate: RepoExplorerMaterializationPresentation
    ) -> Bool {
        switch tablePlan {
        case .content(let content):
            content.rowCount == candidate.rowCount
                && content.membershipFingerprint == candidate.fingerprint
        case .membership(let membership):
            membership.newCount == candidate.rowCount
                && membership.newMembershipFingerprint == candidate.fingerprint
        }
    }

    private static func presentationFingerprintIsValid(
        _ presentation: RepoExplorerMaterializationPresentation
    ) -> Bool {
        guard case .content(let snapshot, let fingerprint) = presentation else { return true }
        return fingerprint == .make(snapshot: snapshot)
    }

    private static func hasUniqueRowIDs(
        _ snapshot: RepoExplorerMaterializationSnapshot?
    ) -> Bool {
        guard let snapshot else { return true }
        return Set(snapshot.rows.map(\.id)).count == snapshot.rows.count
    }

    private static func makeTableUpdatePlan(
        oldSnapshot: RepoExplorerMaterializationSnapshot,
        newSnapshot: RepoExplorerMaterializationSnapshot,
        oldFingerprint: RepoExplorerMaterializationFingerprint,
        newFingerprint: RepoExplorerMaterializationFingerprint
    ) -> RepoExplorerNativeTableUpdatePlan {
        let oldIDs = oldSnapshot.rows.map(\.id)
        let newIDs = newSnapshot.rows.map(\.id)
        let oldRowsByID = Dictionary(uniqueKeysWithValues: oldSnapshot.rows.map { ($0.id, $0) })

        var reloadRows = IndexSet()
        var heightReloadRows = IndexSet()
        for (newIndex, newRow) in newSnapshot.rows.enumerated() {
            guard let oldRow = oldRowsByID[newRow.id] else { continue }
            if oldRow.contentRevision != newRow.contentRevision {
                reloadRows.insert(newIndex)
            }
            if oldRow.layout != newRow.layout {
                heightReloadRows.insert(newIndex)
            }
        }

        guard oldIDs != newIDs else {
            return .content(
                RepoExplorerNativeContentUpdatePlan(
                    rowCount: newIDs.count,
                    membershipFingerprint: newFingerprint,
                    reloadRowsInNewSpace: reloadRows,
                    heightReloadRowsInNewSpace: heightReloadRows
                )
            )
        }

        let oldIndexByID = Dictionary(uniqueKeysWithValues: oldIDs.enumerated().map { ($1, $0) })
        let newIndexByID = Dictionary(uniqueKeysWithValues: newIDs.enumerated().map { ($1, $0) })
        let commonSubsequence = Set(longestCommonSubsequence(oldIDs, newIDs))
        let removed = IndexSet(oldIDs.indices.filter { newIndexByID[oldIDs[$0]] == nil })
        let inserted = IndexSet(newIDs.indices.filter { oldIndexByID[newIDs[$0]] == nil })
        let moves = oldIDs.compactMap { rowID -> RepoExplorerNativeRowMove? in
            guard let oldIndex = oldIndexByID[rowID],
                let newIndex = newIndexByID[rowID],
                !commonSubsequence.contains(rowID)
            else {
                return nil
            }
            return RepoExplorerNativeRowMove(
                rowID: rowID,
                oldIndex: oldIndex,
                newIndex: newIndex
            )
        }
        .sorted { lhs, rhs in lhs.oldIndex < rhs.oldIndex }

        return .membership(
            RepoExplorerNativeMembershipUpdatePlan(
                oldCount: oldIDs.count,
                newCount: newIDs.count,
                oldMembershipFingerprint: oldFingerprint,
                newMembershipFingerprint: newFingerprint,
                removeRowsInOldSpace: removed,
                insertRowsInNewSpace: inserted,
                movesFromOldToNewSpace: moves,
                reloadRowsInNewSpace: reloadRows,
                heightReloadRowsInNewSpace: heightReloadRows
            )
        )
    }

    private static func longestCommonSubsequence(
        _ oldIDs: [RepoExplorerRowID],
        _ newIDs: [RepoExplorerRowID]
    ) -> [RepoExplorerRowID] {
        var lengths = Array(
            repeating: Array(repeating: 0, count: newIDs.count + 1),
            count: oldIDs.count + 1
        )
        for oldIndex in oldIDs.indices {
            for newIndex in newIDs.indices {
                if oldIDs[oldIndex] == newIDs[newIndex] {
                    lengths[oldIndex + 1][newIndex + 1] = lengths[oldIndex][newIndex] + 1
                } else {
                    lengths[oldIndex + 1][newIndex + 1] = max(
                        lengths[oldIndex][newIndex + 1],
                        lengths[oldIndex + 1][newIndex]
                    )
                }
            }
        }

        var oldIndex = oldIDs.count
        var newIndex = newIDs.count
        var reversed: [RepoExplorerRowID] = []
        while oldIndex > 0, newIndex > 0 {
            if oldIDs[oldIndex - 1] == newIDs[newIndex - 1] {
                reversed.append(oldIDs[oldIndex - 1])
                oldIndex -= 1
                newIndex -= 1
            } else if lengths[oldIndex - 1][newIndex] >= lengths[oldIndex][newIndex - 1] {
                oldIndex -= 1
            } else {
                newIndex -= 1
            }
        }
        return reversed.reversed()
    }

    private static func validate(
        _ tablePlan: RepoExplorerNativeTableUpdatePlan,
        oldSnapshot: RepoExplorerMaterializationSnapshot,
        newSnapshot: RepoExplorerMaterializationSnapshot
    ) -> Bool {
        switch tablePlan {
        case .content(let content):
            return content.rowCount == oldSnapshot.rows.count
                && content.rowCount == newSnapshot.rows.count
                && content.membershipFingerprint == .make(snapshot: newSnapshot)
                && indexes(content.reloadRowsInNewSpace, fitWithin: content.rowCount)
                && indexes(content.heightReloadRowsInNewSpace, fitWithin: content.rowCount)
                && oldSnapshot.rows.map(\.id) == newSnapshot.rows.map(\.id)
        case .membership(let membership):
            return validateMembership(
                membership,
                oldSnapshot: oldSnapshot,
                newSnapshot: newSnapshot
            )
        }
    }

    private static func validateMembership(
        _ plan: RepoExplorerNativeMembershipUpdatePlan,
        oldSnapshot: RepoExplorerMaterializationSnapshot,
        newSnapshot: RepoExplorerMaterializationSnapshot
    ) -> Bool {
        guard plan.oldCount == oldSnapshot.rows.count,
            plan.newCount == newSnapshot.rows.count,
            plan.oldMembershipFingerprint == .make(snapshot: oldSnapshot),
            plan.newMembershipFingerprint == .make(snapshot: newSnapshot),
            indexes(plan.removeRowsInOldSpace, fitWithin: plan.oldCount),
            indexes(plan.insertRowsInNewSpace, fitWithin: plan.newCount),
            indexes(plan.reloadRowsInNewSpace, fitWithin: plan.newCount),
            indexes(plan.heightReloadRowsInNewSpace, fitWithin: plan.newCount)
        else {
            return false
        }

        let movedOldIndexes = Set(plan.movesFromOldToNewSpace.map(\.oldIndex))
        let movedNewIndexes = Set(plan.movesFromOldToNewSpace.map(\.newIndex))
        guard movedOldIndexes.count == plan.movesFromOldToNewSpace.count,
            movedNewIndexes.count == plan.movesFromOldToNewSpace.count,
            movedOldIndexes.allSatisfy({ oldSnapshot.rows.indices.contains($0) }),
            movedNewIndexes.allSatisfy({ newSnapshot.rows.indices.contains($0) }),
            movedOldIndexes.isDisjoint(with: Set(plan.removeRowsInOldSpace)),
            movedNewIndexes.isDisjoint(with: Set(plan.insertRowsInNewSpace)),
            plan.movesFromOldToNewSpace.allSatisfy({ move in
                oldSnapshot.rows[move.oldIndex].id == move.rowID
                    && newSnapshot.rows[move.newIndex].id == move.rowID
            })
        else {
            return false
        }

        let removedIDs = Set(plan.removeRowsInOldSpace.map { oldSnapshot.rows[$0].id })
        let movedIDs = Set(plan.movesFromOldToNewSpace.map(\.rowID))
        let untouchedIDs = oldSnapshot.rows.map(\.id).filter {
            !removedIDs.contains($0) && !movedIDs.contains($0)
        }
        var untouchedIterator = untouchedIDs.makeIterator()
        var reconstructed: [RepoExplorerRowID?] = Array(repeating: nil, count: plan.newCount)
        for index in plan.insertRowsInNewSpace {
            reconstructed[index] = newSnapshot.rows[index].id
        }
        for move in plan.movesFromOldToNewSpace {
            reconstructed[move.newIndex] = move.rowID
        }
        for index in reconstructed.indices where reconstructed[index] == nil {
            reconstructed[index] = untouchedIterator.next()
        }
        return untouchedIterator.next() == nil
            && reconstructed.compactMap { $0 } == newSnapshot.rows.map(\.id)
    }

    private static func indexes(_ indexes: IndexSet, fitWithin count: Int) -> Bool {
        indexes.allSatisfy { 0..<count ~= $0 }
    }
}
