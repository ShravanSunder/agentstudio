import AgentStudioInfrastructure
import AppKit
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
@Suite("Repo Explorer table materializer", .serialized)
struct RepoExplorerTableMaterializerTests {
    @Test("viewport coalesces the latest visible set and clears on detach")
    func viewportCoalescesAndClears() async throws {
        let firstWorktreeID = UUIDv7.generate()
        let secondWorktreeID = UUIDv7.generate()
        let snapshot = materializerSnapshot(
            ["A", "B", "C", "D"],
            worktreeIDs: [firstWorktreeID, secondWorktreeID, nil, nil]
        )
        let recorder = VisibleWorktreeSetRecorder()
        let materializer = RepoExplorerTableMaterializer(
            onVisibleWorktreeIDsChange: recorder.record
        )
        let window = makeMaterializerWindow(materializer)
        defer {
            materializer.detach()
            window.close()
        }

        materializer.apply(
            try tableCandidate(
                baseline: nativePlanRowlessBaseline(.noRepositories, revision: 0),
                snapshot: snapshot,
                requestGeneration: 1
            )
        ) { _ in }
        materializer.scroll(to: .group(groupID: "A"), offset: 0)
        materializer.scroll(to: .group(groupID: "B"), offset: 0)
        await materializer.drainViewportPublication()

        #expect(recorder.values.last == [secondWorktreeID])
        let callCountAfterLatestViewport = recorder.values.count
        materializer.scroll(to: .group(groupID: "B"), offset: 0)
        await materializer.drainViewportPublication()
        #expect(recorder.values.count == callCountAfterLatestViewport)

        materializer.detach()
        #expect(recorder.values.last?.isEmpty == true)
    }

    @Test("demand suspension invalidates queued viewport work and reentry republishes current rows")
    func demandLifecycleInvalidatesAndRepublishesViewport() async throws {
        let worktreeID = UUIDv7.generate()
        let snapshot = materializerSnapshot(
            ["A", "B", "C", "D"],
            worktreeIDs: [worktreeID, nil, nil, nil]
        )
        let recorder = VisibleWorktreeSetRecorder()
        let materializer = RepoExplorerTableMaterializer(
            onVisibleWorktreeIDsChange: recorder.record
        )
        let window = makeMaterializerWindow(materializer)
        defer {
            materializer.detach()
            window.close()
        }
        materializer.apply(
            try tableCandidate(
                baseline: nativePlanRowlessBaseline(.noRepositories, revision: 0),
                snapshot: snapshot,
                requestGeneration: 1
            )
        ) { _ in }
        materializer.scroll(to: .group(groupID: "A"), offset: 0)

        materializer.suspendDemand()
        await materializer.drainViewportPublication()
        #expect(recorder.values.isEmpty)

        materializer.resumeDemand(visibleGeneration: 1)
        await materializer.drainViewportPublication()
        #expect(recorder.values.last == [worktreeID])

        materializer.suspendDemand()
        let publicationCountAfterClear = recorder.values.count
        #expect(recorder.values.last?.isEmpty == true)
        materializer.suspendDemand()
        #expect(recorder.values.count == publicationCountAfterClear)

        materializer.resumeDemand(visibleGeneration: 999)
        await materializer.drainViewportPublication()
        #expect(recorder.values.count == publicationCountAfterClear)
        materializer.resumeDemand(visibleGeneration: 1)
        await materializer.drainViewportPublication()
        #expect(recorder.values.last == [worktreeID])
    }

    @Test("width measurement is limited to represented wrapping rows")
    func widthMeasurementIsVisibleOnly() throws {
        let snapshot = wrappingMaterializerSnapshot(["A", "B", "C", "D"])
        let measurementRecorder = VisibleHeightMeasurementRecorder()
        let materializer = RepoExplorerTableMaterializer(
            onVisibleWorktreeIDsChange: { _ in },
            measureVisibleRowHeight: measurementRecorder.measure
        )
        let window = makeMaterializerWindow(materializer)
        defer {
            materializer.detach()
            window.close()
        }
        materializer.apply(
            try tableCandidate(
                baseline: nativePlanRowlessBaseline(.noRepositories, revision: 0),
                snapshot: snapshot,
                requestGeneration: 1
            )
        ) { _ in }

        let offscreenHeight = materializer.resolvedHeight(forRowAt: 3)
        #expect(measurementRecorder.callCount == 0)
        materializer.scroll(to: .group(groupID: "B"), offset: 0)
        let visibleHeight = materializer.resolvedHeight(forRowAt: 1)

        #expect(measurementRecorder.callCount == 1)
        #expect(visibleHeight > offscreenHeight)
    }

    @Test("membership apply uses the sole applier and preserves a surviving row anchor")
    func membershipApplyPreservesSurvivingAnchor() throws {
        let initialSnapshot = nativePlanSnapshot(["A", "B", "C", "D", "E", "F"])
        let nextSnapshot = nativePlanSnapshot(["F", "A", "B", "C", "D", "E"])
        let materializer = RepoExplorerTableMaterializer(onVisibleWorktreeIDsChange: { _ in })
        let window = makeMaterializerWindow(materializer)
        defer {
            materializer.detach()
            window.close()
        }

        let initialCandidate = try tableCandidate(
            baseline: nativePlanRowlessBaseline(.noRepositories, revision: 0),
            snapshot: initialSnapshot,
            requestGeneration: 1
        )
        var disposition: RepoExplorerMaterializationChildDisposition?
        materializer.apply(initialCandidate) { disposition = $0 }
        #expect(disposition == .accepted)

        materializer.scroll(to: .group(groupID: "C"), offset: 3)
        let nextCandidate = try tableCandidate(
            baseline: nativePlanBaseline(
                snapshot: initialSnapshot,
                revision: 1,
                visibleGeneration: 1
            ),
            snapshot: nextSnapshot,
            requestGeneration: 2
        )
        disposition = nil
        materializer.apply(nextCandidate) { disposition = $0 }

        #expect(disposition == .accepted)
        #expect(materializer.numberOfRows == nextSnapshot.rows.count)
        #expect(materializer.currentTopVisibleAnchor?.rowID == .group(groupID: "C"))
        #expect(materializer.currentTopVisibleAnchor?.offset == 3)
        #expect(materializer.nativeTransactionApplyCount == 2)
    }

    @Test("removed row anchor restores its worker-derived successor")
    func removedAnchorUsesPlanFallback() throws {
        let initialSnapshot = nativePlanSnapshot(["A", "B", "C", "D", "E", "F"])
        let nextSnapshot = nativePlanSnapshot(["A", "B", "E", "F"])
        let materializer = RepoExplorerTableMaterializer(onVisibleWorktreeIDsChange: { _ in })
        let window = makeMaterializerWindow(materializer)
        defer {
            materializer.detach()
            window.close()
        }

        materializer.apply(
            try tableCandidate(
                baseline: nativePlanRowlessBaseline(.noRepositories, revision: 0),
                snapshot: initialSnapshot,
                requestGeneration: 1
            )
        ) { _ in }
        materializer.scroll(to: .group(groupID: "C"), offset: 2)
        var disposition: RepoExplorerMaterializationChildDisposition?
        materializer.apply(
            try tableCandidate(
                baseline: nativePlanBaseline(
                    snapshot: initialSnapshot,
                    revision: 1,
                    visibleGeneration: 1
                ),
                snapshot: nextSnapshot,
                requestGeneration: 2
            )
        ) { disposition = $0 }

        #expect(disposition == .accepted)
        #expect(materializer.currentTopVisibleAnchor?.rowID == .group(groupID: "E"))
        #expect(materializer.currentTopVisibleAnchor?.offset == 2)
    }

    private func makeMaterializerWindow(_ materializer: RepoExplorerTableMaterializer) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 36),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = materializer.view
        window.layoutIfNeeded()
        return window
    }

    private func tableCandidate(
        baseline: RepoExplorerMaterializationBaseline,
        snapshot: RepoExplorerMaterializationSnapshot,
        requestGeneration: UInt64
    ) throws -> RepoExplorerMaterializationContentCandidate {
        let presentation = nativePlanContent(snapshot)
        let plan = try RepoExplorerNativeUpdatePlan.validating(
            baseline: baseline,
            candidate: presentation,
            requestGeneration: requestGeneration
        ).get()
        let tablePlan = try #require(plan.tableUpdatePlan())
        return RepoExplorerMaterializationContentCandidate(
            candidateID: RepoExplorerMaterializationCandidateID(rawValue: requestGeneration),
            requestGeneration: requestGeneration,
            visibleGeneration: requestGeneration,
            snapshot: snapshot,
            tableUpdatePlan: tablePlan
        )
    }

    private func materializerSnapshot(
        _ identities: [String],
        worktreeIDs: [UUID?]
    ) -> RepoExplorerMaterializationSnapshot {
        let source = nativePlanSnapshot(identities)
        return RepoExplorerMaterializationSnapshot(
            rows: zip(source.rows, worktreeIDs).map { row, worktreeID in
                RepoExplorerMaterializedRow(
                    id: row.id,
                    contentRevision: row.contentRevision,
                    layout: row.layout,
                    representedRepoID: nil,
                    representedWorktreeID: worktreeID
                )
            }
        )
    }

    private func wrappingMaterializerSnapshot(
        _ identities: [String]
    ) -> RepoExplorerMaterializationSnapshot {
        let source = nativePlanSnapshot(identities)
        return RepoExplorerMaterializationSnapshot(
            rows: source.rows.map { row in
                RepoExplorerMaterializedRow(
                    id: row.id,
                    contentRevision: row.contentRevision,
                    layout: RepoExplorerRowLayout(
                        rowClass: row.layout.rowClass,
                        metrics: row.layout.metrics,
                        requiresVisibleWidthMeasurement: true
                    ),
                    representedRepoID: nil,
                    representedWorktreeID: nil
                )
            }
        )
    }
}

@MainActor
private final class VisibleWorktreeSetRecorder {
    private(set) var values: [Set<UUID>] = []

    func record(_ value: Set<UUID>) {
        values.append(value)
    }
}

@MainActor
private final class VisibleHeightMeasurementRecorder {
    private(set) var callCount = 0

    func measure(_ row: RepoExplorerMaterializedRow, availableWidth: CGFloat) -> CGFloat {
        callCount += 1
        return row.layout.metrics.fallbackHeight + max(1, availableWidth / 100)
    }
}
