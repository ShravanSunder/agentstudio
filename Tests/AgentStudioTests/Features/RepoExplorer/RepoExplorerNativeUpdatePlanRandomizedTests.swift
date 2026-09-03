import Testing

@testable import AgentStudioRepoExplorer

private struct NativePlanSeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

@Suite("Repo Explorer native update plan randomized")
struct RepoExplorerNativeUpdatePlanRandomizedTests {
    @Test("seeded randomized plans reconstruct the exact candidate independently")
    func randomizedPlansMatchIndependentOracle() throws {
        var generator = NativePlanSeededGenerator(state: 0xA63E_2026)
        for iteration in 0..<150 {
            let oldCount = Int.random(in: 0...24, using: &generator)
            let oldIDs = (0..<oldCount).map { "old-\($0)" }
            var surviving = oldIDs.filter { _ in Bool.random(using: &generator) }
            surviving.shuffle(using: &generator)
            let insertCount = Int.random(in: 0...8, using: &generator)
            var newIDs = surviving + (0..<insertCount).map { "new-\(iteration)-\($0)" }
            newIDs.shuffle(using: &generator)

            let oldSnapshot = nativePlanSnapshot(oldIDs)
            let newSnapshot = nativePlanSnapshot(newIDs)
            let baseline = nativePlanBaseline(snapshot: oldSnapshot, revision: UInt64(iteration))
            let plan = try RepoExplorerNativeUpdatePlan.validating(
                baseline: baseline,
                candidate: nativePlanContent(newSnapshot),
                requestGeneration: UInt64(iteration + 1)
            ).get()

            #expect(
                nativePlanOracleIDs(plan: plan, oldSnapshot: oldSnapshot, candidate: newSnapshot)
                    == newSnapshot.rows.map(\.id)
            )
            #expect(
                nativePlanAnchorFallbacks(plan: plan)
                    == nativePlanAnchorFallbackOracle(
                        oldIDs: oldSnapshot.rows.map(\.id),
                        newIDs: newSnapshot.rows.map(\.id)
                    )
            )
        }
    }

    @Test(
        "real-size and doubled-offscreen plans reconstruct exactly",
        arguments: [150, 180, 360]
    )
    func largePlansMatchIndependentOracle(rowCount: Int) throws {
        let oldIDs = (0..<rowCount).map { "row-\($0)" }
        let retained = Array(oldIDs.dropFirst(rowCount / 5).reversed())
        let inserted = (0..<(rowCount / 5)).map { "inserted-\($0)" }
        let newIDs = retained + inserted
        let oldSnapshot = nativePlanSnapshot(oldIDs)
        let newSnapshot = nativePlanSnapshot(newIDs)
        let baseline = nativePlanBaseline(snapshot: oldSnapshot, revision: 5)
        let plan = try RepoExplorerNativeUpdatePlan.validating(
            baseline: baseline,
            candidate: nativePlanContent(newSnapshot),
            requestGeneration: 6
        ).get()

        #expect(
            nativePlanOracleIDs(plan: plan, oldSnapshot: oldSnapshot, candidate: newSnapshot)
                == newSnapshot.rows.map(\.id)
        )
    }

    @Test("seeded template pairs reconstruct exact forward and reverse candidates")
    func randomizedTemplatePairsMatchIndependentOracle() throws {
        var generator = NativePlanSeededGenerator(state: 0x5EA1_2026)
        for iteration in 0..<100 {
            let oldCount = Int.random(in: 0...24, using: &generator)
            let oldIDs = (0..<oldCount).map { "old-\($0)" }
            var surviving = oldIDs.filter { _ in Bool.random(using: &generator) }
            surviving.shuffle(using: &generator)
            let insertCount = Int.random(in: 1...8, using: &generator)
            var newIDs = surviving + (0..<insertCount).map { "new-\(iteration)-\($0)" }
            newIDs.shuffle(using: &generator)

            let oldSnapshot = nativePlanSnapshot(oldIDs)
            let newSnapshot = nativePlanSnapshot(newIDs)
            let source = nativePlanContent(oldSnapshot)
            let target = nativePlanContent(newSnapshot)
            let templates = try RepoExplorerProjectionWorker.sealNativeUpdatePlanTemplates(
                source: source,
                target: target
            ).get()
            let sourceBaseline = nativePlanBaseline(
                snapshot: oldSnapshot,
                revision: UInt64(iteration),
                visibleGeneration: UInt64(iteration)
            )
            let forward = try templates.forward.instantiate(
                baseline: sourceBaseline,
                candidateID: RepoExplorerMaterializationCandidateID(rawValue: UInt64(iteration + 1)),
                requestGeneration: UInt64(iteration + 1),
                visibleGeneration: UInt64(iteration + 1)
            ).get()
            #expect(
                nativePlanOracleIDs(
                    plan: forward.nativeUpdatePlan,
                    oldSnapshot: oldSnapshot,
                    candidate: newSnapshot
                ) == newSnapshot.rows.map(\.id)
            )
            #expect(
                nativePlanAnchorFallbacks(plan: forward.nativeUpdatePlan)
                    == nativePlanAnchorFallbackOracle(
                        oldIDs: oldSnapshot.rows.map(\.id),
                        newIDs: newSnapshot.rows.map(\.id)
                    )
            )

            let targetBaseline = RepoExplorerMaterializationBaseline(
                lifetimeID: forward.lifetimeID,
                demandEpoch: forward.demandEpoch,
                revision: forward.proposedRevision,
                visibleGeneration: forward.visibleGeneration,
                presentation: forward.presentation
            )
            let reverse = try templates.reverse.instantiate(
                baseline: targetBaseline,
                candidateID: RepoExplorerMaterializationCandidateID(rawValue: UInt64(iteration + 101)),
                requestGeneration: UInt64(iteration + 101),
                visibleGeneration: UInt64(iteration + 101)
            ).get()
            #expect(
                nativePlanOracleIDs(
                    plan: reverse.nativeUpdatePlan,
                    oldSnapshot: newSnapshot,
                    candidate: oldSnapshot
                ) == oldSnapshot.rows.map(\.id)
            )
            #expect(
                nativePlanAnchorFallbacks(plan: reverse.nativeUpdatePlan)
                    == nativePlanAnchorFallbackOracle(
                        oldIDs: newSnapshot.rows.map(\.id),
                        newIDs: oldSnapshot.rows.map(\.id)
                    )
            )
        }
    }
}

private func nativePlanAnchorFallbacks(
    plan: RepoExplorerNativeUpdatePlan
) -> [RepoExplorerNativeRemovedRowAnchorFallback] {
    guard case .changed(let changed) = plan.kind,
        case .contentToContent(.membership(let membership)) = changed.presentation
    else {
        return []
    }
    return membership.anchorFallbacks.entries
}

private func nativePlanAnchorFallbackOracle(
    oldIDs: [RepoExplorerRowID],
    newIDs: [RepoExplorerRowID]
) -> [RepoExplorerNativeRemovedRowAnchorFallback] {
    let survivingIDs = Set(newIDs)
    return oldIDs.indices.compactMap { removedIndex in
        let removedRowID = oldIDs[removedIndex]
        guard !survivingIDs.contains(removedRowID) else { return nil }
        let successor = oldIDs[oldIDs.index(after: removedIndex)...]
            .first(where: survivingIDs.contains)
        let predecessor = oldIDs[..<removedIndex]
            .last(where: survivingIDs.contains)
        return RepoExplorerNativeRemovedRowAnchorFallback(
            removedRowID: removedRowID,
            targetRowID: successor ?? predecessor
        )
    }
}

func nativePlanOracleIDs(
    plan: RepoExplorerNativeUpdatePlan,
    oldSnapshot: RepoExplorerMaterializationSnapshot,
    candidate: RepoExplorerMaterializationSnapshot
) -> [RepoExplorerRowID] {
    guard case .changed(let changed) = plan.kind else { return oldSnapshot.rows.map(\.id) }
    let tablePlan: RepoExplorerNativeTableUpdatePlan
    switch changed.presentation {
    case .emptyToContent(let plan), .contentToContent(let plan):
        tablePlan = plan
    case .changedEmptyToEmpty, .contentToEmpty:
        return []
    }
    guard case .membership(let membership) = tablePlan else {
        return oldSnapshot.rows.map(\.id)
    }

    let removedIDs = Set(membership.removeRowsInOldSpace.map { oldSnapshot.rows[$0].id })
    let movedIDs = Set(membership.movesFromOldToNewSpace.map(\.rowID))
    let untouched = oldSnapshot.rows.map(\.id).filter {
        !removedIDs.contains($0) && !movedIDs.contains($0)
    }
    var untouchedIterator = untouched.makeIterator()
    var final: [RepoExplorerRowID?] = Array(repeating: nil, count: membership.newCount)
    for index in membership.insertRowsInNewSpace {
        final[index] = candidate.rows[index].id
    }
    for move in membership.movesFromOldToNewSpace {
        final[move.newIndex] = move.rowID
    }
    for index in final.indices where final[index] == nil {
        final[index] = untouchedIterator.next()
    }
    return final.compactMap { $0 }
}
