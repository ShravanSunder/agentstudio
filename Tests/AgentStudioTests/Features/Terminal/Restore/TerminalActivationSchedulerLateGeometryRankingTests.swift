import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioTerminal

/// R3 remediation (PR #330): a member admitted from `waitingForGeometry`
/// after a visibility snapshot was already applied must be ranked by that
/// snapshot, not fall back to its static descriptor priority. Split into its
/// own file — `TerminalActivationSchedulerTests` is already at the
/// file-length lint budget — but reuses that suite's
/// `RevisionAwareTerminalActivationAdmissionPort` fake, which is internal to
/// this test target.
@MainActor
@Suite("Terminal activation scheduler late geometry ranking")
struct LateGeometryRankingTests {
    @Test("a member admitted after a snapshot was applied is ranked by that snapshot")
    func aMemberAdmittedAfterASnapshotWasAppliedIsRankedByThatSnapshot() async throws {
        // Arrange: `laterOrdinalMember` has the lower ordinal (it appears
        // first in the cohort), so a tie on rank would admit it before
        // `promotedMember`. Both are `.hidden` and never installed eligible,
        // so they stay `waitingForGeometry` while `vehicle` drives the drain.
        let generation = try makeLateGeometryRankingTestGeneration()
        let laterOrdinalMember = makeLateGeometryRankingTestDescriptor(priority: .hidden)
        let promotedMember = makeLateGeometryRankingTestDescriptor(priority: .hidden)
        let vehicle = makeLateGeometryRankingTestDescriptor(priority: .activeVisible)
        let entries = [laterOrdinalMember, promotedMember, vehicle]
        let port = RevisionAwareTerminalActivationAdmissionPort(generation: generation, descriptors: entries)
        let scheduler = TerminalActivationScheduler(
            cohort: TerminalActivationCohort(generation: generation, input: TerminalActivationInput(entries: entries)),
            admissionPort: port
        )
        _ = await scheduler.installGeometryEligibility([vehicle.paneID])

        // Apply a snapshot naming `promotedMember` as a visible main sibling
        // while both members are still `waitingForGeometry`. Recording it
        // before `activate()` starts forces `vehicle`'s first proposal to
        // carry a stale revision, so the scheduler reconciles via
        // `applyVisibilitySnapshot` — the exact path that must now remember
        // this snapshot for members admitted later.
        port.recordCurrentVisibleQueuedTerminals(
            TerminalVisibleQueuedTerminals(
                generation: generation,
                activeMainPaneIDs: [],
                visibleMainSiblingPaneIDs: [promotedMember.paneID],
                activeDrawerPaneIDs: [],
                visibleDrawerSiblingPaneIDs: []
            )
        )
        let settlement = await scheduler.activate()
        guard case .ready = settlement.outcomesByPaneID[vehicle.paneID] else {
            Issue.record("expected the vehicle member to reach ready")
            return
        }
        #expect(settlement.outcomesByPaneID[promotedMember.paneID] == .waitingForGeometry)
        #expect(settlement.outcomesByPaneID[laterOrdinalMember.paneID] == .waitingForGeometry)

        // Act: admit both members from `waitingForGeometry` after the
        // scheduler has already settled and after the snapshot above was
        // already applied.
        let acceptedPaneIDs = await scheduler.acceptLaterGeometry(
            for: [promotedMember.paneID, laterOrdinalMember.paneID]
        )
        #expect(acceptedPaneIDs == [promotedMember.paneID, laterOrdinalMember.paneID])
        await port.waitUntilStartedCount(3)

        // Assert: `promotedMember` is admitted before `laterOrdinalMember`
        // despite its lower ordinal — the already-applied snapshot's
        // promoted-sibling tier outranks the static `.hidden` background
        // tier both would otherwise share.
        #expect(
            port.admissions.map(\.descriptor.paneID)
                == [vehicle.paneID, promotedMember.paneID, laterOrdinalMember.paneID]
        )
    }
}

@MainActor
private func makeLateGeometryRankingTestGeneration() throws -> WorkspaceContentMountGeneration {
    WorkspaceContentMountGeneration()
}

private func makeLateGeometryRankingTestDescriptor(
    priority: TerminalActivationVisibilityPriority
) -> TerminalActivationDescriptor {
    let pane = Pane(
        id: UUIDv7.generate(),
        content: .terminal(
            TerminalState(
                provider: .zmx,
                lifetime: .persistent,
                zmxSessionID: .generateUUIDv7()
            )
        ),
        metadata: PaneMetadata(
            launchDirectory: URL(filePath: "/tmp/terminal-activation-late-geometry-ranking"),
            title: "Late geometry ranking test"
        )
    )
    return TerminalActivationDescriptor(
        pane: pane,
        visibilityPriority: priority,
        hostPlacement: .tab(tabID: UUIDv7.generate())
    )
}
