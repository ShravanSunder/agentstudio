import Foundation
import Testing

@testable import AgentStudioTerminal

/// SR6b (Program Design item 13, choice 13, step 3): R1's own arm/end
/// recording on `TerminalActivityProjector.restorePhaseByPane`. This is the
/// plan's stand-in "recording consumer at the projector's input boundary" —
/// Panes' consumer adds the gating this state drives; these tests prove only
/// the recording contract R1 owns.
@Suite("Terminal activity projector restore phase")
struct TerminalActivityProjectorRestorePhaseTests {
    @Test("arming records the generation for that pane")
    func armingRecordsGeneration() async {
        let projector = TerminalActivityProjector()
        let paneID = UUID()
        let generation = RestoreGeneration(rawValue: 1)

        await projector.armRestorePhase(paneID: paneID, generation: generation)

        #expect(await projector.restorePhaseGenerationsByPane[paneID] == generation)
    }

    @Test("a newer generation overwrites an older arm for the same pane")
    func newerGenerationOverwrites() async {
        let projector = TerminalActivityProjector()
        let paneID = UUID()

        await projector.armRestorePhase(paneID: paneID, generation: RestoreGeneration(rawValue: 1))
        await projector.armRestorePhase(paneID: paneID, generation: RestoreGeneration(rawValue: 2))

        #expect(await projector.restorePhaseGenerationsByPane[paneID] == RestoreGeneration(rawValue: 2))
    }

    @Test("ending with the matching generation clears the pane and reports a match")
    func endingWithMatchingGenerationClears() async {
        let projector = TerminalActivityProjector()
        let paneID = UUID()
        let generation = RestoreGeneration(rawValue: 1)
        await projector.armRestorePhase(paneID: paneID, generation: generation)

        let matched = await projector.endRestorePhase(paneID: paneID, generation: generation)

        #expect(matched)
        #expect(await projector.restorePhaseGenerationsByPane[paneID] == nil)
    }

    @Test("a stale generation is ignored: the pane stays gated, no match reported")
    func staleGenerationIsIgnored() async {
        let projector = TerminalActivityProjector()
        let paneID = UUID()
        await projector.armRestorePhase(paneID: paneID, generation: RestoreGeneration(rawValue: 2))

        let matched = await projector.endRestorePhase(paneID: paneID, generation: RestoreGeneration(rawValue: 1))

        #expect(!matched)
        #expect(await projector.restorePhaseGenerationsByPane[paneID] == RestoreGeneration(rawValue: 2))
    }

    @Test("a duplicate end (already cleared) is a no-op, not a crash or a false match")
    func duplicateEndIsANoOp() async {
        let projector = TerminalActivityProjector()
        let paneID = UUID()
        let generation = RestoreGeneration(rawValue: 1)
        await projector.armRestorePhase(paneID: paneID, generation: generation)
        _ = await projector.endRestorePhase(paneID: paneID, generation: generation)

        let secondMatch = await projector.endRestorePhase(paneID: paneID, generation: generation)

        #expect(!secondMatch)
    }

    @Test("ending an unarmed pane is a no-op")
    func endingAnUnarmedPaneIsANoOp() async {
        let projector = TerminalActivityProjector()
        let paneID = UUID()

        let matched = await projector.endRestorePhase(paneID: paneID, generation: RestoreGeneration(rawValue: 1))

        #expect(!matched)
    }

    @Test("the surface-route ordered control reaches the same recording boundary")
    func orderedControlReachesTheProjector() async {
        let projector = TerminalActivityProjector()
        let surfaceID = UUID()
        let paneID = UUID()
        let generation = RestoreGeneration(rawValue: 7)
        await projector.armRestorePhase(paneID: paneID, generation: generation)

        await projector.applyOrderedControl(
            surfaceID: surfaceID,
            paneID: paneID,
            precedingAggregate: nil,
            control: .restorePhaseEnded(generation)
        )

        #expect(await projector.restorePhaseGenerationsByPane[paneID] == nil)
    }

    @Test("a plain surface close, as fired on replacement, keeps the pane's restore phase")
    func plainSurfaceCloseKeepsTheRestorePhase() async {
        let projector = TerminalActivityProjector()
        let surfaceID = UUID()
        let paneID = UUID()
        let generation = RestoreGeneration(rawValue: 3)
        await projector.armRestorePhase(paneID: paneID, generation: generation)

        await projector.applyOrderedControl(
            surfaceID: surfaceID,
            paneID: paneID,
            precedingAggregate: nil,
            control: .surfaceClosed
        )

        #expect(await projector.restorePhaseGenerationsByPane[paneID] == generation)
    }

    @Test("permanent pane retirement clears the restore phase, unlike a plain surface close")
    func permanentRetirementClearsTheRestorePhase() async {
        let projector = TerminalActivityProjector()
        let paneID = UUID()
        let generation = RestoreGeneration(rawValue: 4)
        await projector.armRestorePhase(paneID: paneID, generation: generation)

        await projector.retirePanePermanently(paneID: paneID)

        #expect(await projector.restorePhaseGenerationsByPane[paneID] == nil)
    }

    @Test("a router stop (reset) clears every armed restore phase, so none outlives the router's lifetime")
    func routerStopClearsEveryArmedRestorePhase() async {
        let projector = TerminalActivityProjector()
        let firstPaneID = UUID()
        let secondPaneID = UUID()
        await projector.armRestorePhase(paneID: firstPaneID, generation: RestoreGeneration(rawValue: 1))
        await projector.armRestorePhase(paneID: secondPaneID, generation: RestoreGeneration(rawValue: 2))

        await projector.reset()

        #expect(await projector.restorePhaseGenerationsByPane.isEmpty)
    }
}
