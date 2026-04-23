import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct DropSizingRatioPolicyTests {
    @Test
    func ratiosAfterInsertion_halveTarget_halvesOnlyTargetPane() {
        let result = DropSizingRatioPolicy.ratiosAfterInsertion(
            existingRatios: [0.5, 0.3, 0.2],
            insertionIndex: 2,
            mode: .halveTarget(paneIndex: 1)
        )

        #expect(result.count == 4)
        #expect(abs(result[0] - 0.5) < 0.001)
        #expect(abs(result[1] - 0.15) < 0.001)
        #expect(abs(result[2] - 0.15) < 0.001)
        #expect(abs(result[3] - 0.2) < 0.001)
        #expect(abs(result.reduce(0, +) - 1.0) < 0.001)
    }

    @Test
    func ratiosAfterInsertion_halveTarget_requiresExplicitTargetPaneIndex() {
        let result = DropSizingRatioPolicy.ratiosAfterInsertion(
            existingRatios: [0.6, 0.4],
            insertionIndex: 1,
            mode: .halveTarget(paneIndex: 0)
        )

        #expect(result.count == 3)
        #expect(abs(result[0] - 0.3) < 0.001)
        #expect(abs(result[1] - 0.3) < 0.001)
        #expect(abs(result[2] - 0.4) < 0.001)
        #expect(abs(result.reduce(0, +) - 1.0) < 0.001)
    }

    @Test
    func ratiosAfterInsertion_proportional_preservesExistingProportions() {
        let result = DropSizingRatioPolicy.ratiosAfterInsertion(
            existingRatios: [0.6, 0.4],
            insertionIndex: 1,
            mode: .proportional
        )

        #expect(result.count == 3)
        #expect(abs(result[0] - 0.4) < 0.001)
        #expect(abs(result[1] - 1.0 / 3.0) < 0.001)
        #expect(abs(result[2] - (0.4 * 2.0 / 3.0)) < 0.001)
        #expect(abs(result.reduce(0, +) - 1.0) < 0.001)
    }

    @Test
    func ratiosAfterInsertion_intoEmpty_returnsSingleFullPane() {
        let result = DropSizingRatioPolicy.ratiosAfterInsertion(
            existingRatios: [],
            insertionIndex: 0,
            mode: .proportional
        )

        #expect(result == [1.0])
    }

    @Test
    func ratiosAfterRemoval_proportional_redistributesByProportion() {
        let result = DropSizingRatioPolicy.ratiosAfterRemoval(
            existingRatios: [0.5, 0.25, 0.25],
            removalIndex: 0,
            mode: .proportional
        )

        #expect(result.count == 2)
        #expect(abs(result[0] - 0.5) < 0.001)
        #expect(abs(result[1] - 0.5) < 0.001)
        #expect(abs(result.reduce(0, +) - 1.0) < 0.001)
    }

    @Test
    func ratiosAfterRemoval_halveTarget_usesAdjacentAbsorbFallback() {
        let result = DropSizingRatioPolicy.ratiosAfterRemoval(
            existingRatios: [0.5, 0.3, 0.2],
            removalIndex: 1,
            mode: .halveTarget
        )

        #expect(result.count == 2)
        #expect(abs(result[0] - 0.5) < 0.001)
        #expect(abs(result[1] - 0.5) < 0.001)
        #expect(abs(result.reduce(0, +) - 1.0) < 0.001)
    }

    @Test
    func ratiosAfterRemoval_halveTarget_tailAbsorbsIntoLeftNeighbor() {
        let result = DropSizingRatioPolicy.ratiosAfterRemoval(
            existingRatios: [0.2, 0.3, 0.5],
            removalIndex: 2,
            mode: .halveTarget
        )

        #expect(result == [0.2, 0.8])
    }

    @Test
    func ratiosAfterRemoval_halveTarget_singlePaneBecomesEmpty() {
        let result = DropSizingRatioPolicy.ratiosAfterRemoval(
            existingRatios: [1.0],
            removalIndex: 0,
            mode: .halveTarget
        )

        #expect(result.isEmpty)
    }
}
