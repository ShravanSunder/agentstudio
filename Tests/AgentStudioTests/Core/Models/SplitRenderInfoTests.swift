import XCTest

@testable import AgentStudio

final class SplitRenderInfoTests: XCTestCase {

    // MARK: - No minimized panes

    func test_noMinimized_emptyDictionary() {
        let a = UUID()
        let b = UUID()
        let layout = Layout(
            root: .split(
                Layout.Split(
                    direction: .horizontal, ratio: 0.5,
                    left: .leaf(paneId: a), right: .leaf(paneId: b)
                )))

        let info = SplitRenderInfo.compute(layout: layout, minimizedPaneIds: [])

        XCTAssertTrue(info.splitInfo.isEmpty)
        XCTAssertFalse(info.allMinimized)
    }

    // MARK: - One side fully minimized

    func test_rightFullyMinimized_adjustedRatio() {
        let a = UUID()
        let b = UUID()
        let splitId = UUID()
        let layout = Layout(
            root: .split(
                Layout.Split(
                    id: splitId, direction: .horizontal, ratio: 0.5,
                    left: .leaf(paneId: a), right: .leaf(paneId: b)
                )))

        let info = SplitRenderInfo.compute(layout: layout, minimizedPaneIds: [b])

        XCTAssertFalse(info.allMinimized)
        let splitInfo = info.splitInfo[splitId]!
        XCTAssertFalse(splitInfo.leftFullyMinimized)
        XCTAssertTrue(splitInfo.rightFullyMinimized)
        XCTAssertEqual(splitInfo.rightMinimizedPaneIds, [b])
    }

    func test_leftFullyMinimized_adjustedRatio() {
        let a = UUID()
        let b = UUID()
        let splitId = UUID()
        let layout = Layout(
            root: .split(
                Layout.Split(
                    id: splitId, direction: .horizontal, ratio: 0.5,
                    left: .leaf(paneId: a), right: .leaf(paneId: b)
                )))

        let info = SplitRenderInfo.compute(layout: layout, minimizedPaneIds: [a])

        let splitInfo = info.splitInfo[splitId]!
        XCTAssertTrue(splitInfo.leftFullyMinimized)
        XCTAssertFalse(splitInfo.rightFullyMinimized)
        XCTAssertEqual(splitInfo.leftMinimizedPaneIds, [a])
    }

    // MARK: - Both sides visible, adjusted ratio

    func test_partialMinimize_adjustedRatio() {
        // Split(0.33, A, Split(0.5, B_min, C))
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let innerSplitId = UUID()
        let outerSplitId = UUID()
        let layout = Layout(
            root: .split(
                Layout.Split(
                    id: outerSplitId, direction: .horizontal, ratio: 0.33,
                    left: .leaf(paneId: a),
                    right: .split(
                        Layout.Split(
                            id: innerSplitId, direction: .horizontal, ratio: 0.5,
                            left: .leaf(paneId: b), right: .leaf(paneId: c)
                        ))
                )))

        let info = SplitRenderInfo.compute(layout: layout, minimizedPaneIds: [b])

        // Outer split: both sides have visible panes (A and C)
        // A weight = 0.33, C weight = 0.67 * 0.5 = 0.335
        // Adjusted ratio = 0.33 / (0.33 + 0.335) ≈ 0.496
        let outerInfo = info.splitInfo[outerSplitId]!
        XCTAssertFalse(outerInfo.leftFullyMinimized)
        XCTAssertFalse(outerInfo.rightFullyMinimized)
        XCTAssertEqual(outerInfo.adjustedRatio, 0.496, accuracy: 0.01)

        // Inner split: left (B) is fully minimized, right (C) is visible
        let innerInfo = info.splitInfo[innerSplitId]!
        XCTAssertTrue(innerInfo.leftFullyMinimized)
        XCTAssertFalse(innerInfo.rightFullyMinimized)
        XCTAssertEqual(innerInfo.leftMinimizedPaneIds, [b])
    }

    // MARK: - All minimized

    func test_allMinimized_flagSet() {
        let a = UUID()
        let b = UUID()
        let layout = Layout(
            root: .split(
                Layout.Split(
                    direction: .horizontal, ratio: 0.5,
                    left: .leaf(paneId: a), right: .leaf(paneId: b)
                )))

        let info = SplitRenderInfo.compute(layout: layout, minimizedPaneIds: [a, b])

        XCTAssertTrue(info.allMinimized)
        XCTAssertEqual(info.allMinimizedPaneIds, [a, b])
    }

    // MARK: - Nested fully minimized subtree

    func test_nestedFullyMinimized_collapsesCorrectly() {
        // Split(0.5, A, Split(0.5, B_min, C_min))
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let outerSplitId = UUID()
        let layout = Layout(
            root: .split(
                Layout.Split(
                    id: outerSplitId, direction: .horizontal, ratio: 0.5,
                    left: .leaf(paneId: a),
                    right: .split(
                        Layout.Split(
                            direction: .horizontal, ratio: 0.5,
                            left: .leaf(paneId: b), right: .leaf(paneId: c)
                        ))
                )))

        let info = SplitRenderInfo.compute(layout: layout, minimizedPaneIds: [b, c])

        let outerInfo = info.splitInfo[outerSplitId]!
        XCTAssertFalse(outerInfo.leftFullyMinimized)
        XCTAssertTrue(outerInfo.rightFullyMinimized)
        XCTAssertEqual(outerInfo.rightMinimizedPaneIds, [b, c])
    }

    // MARK: - Empty layout

    func test_emptyLayout_noInfo() {
        let layout = Layout()
        let info = SplitRenderInfo.compute(layout: layout, minimizedPaneIds: [])
        XCTAssertTrue(info.splitInfo.isEmpty)
        XCTAssertFalse(info.allMinimized)
    }

    // MARK: - Single pane (no split)

    func test_singlePane_minimized_allMinimized() {
        let a = UUID()
        let layout = Layout(paneId: a)
        let info = SplitRenderInfo.compute(layout: layout, minimizedPaneIds: [a])
        XCTAssertTrue(info.allMinimized)
        XCTAssertEqual(info.allMinimizedPaneIds, [a])
    }

    func test_singlePane_visible_notAllMinimized() {
        let a = UUID()
        let layout = Layout(paneId: a)
        let info = SplitRenderInfo.compute(layout: layout, minimizedPaneIds: [])
        XCTAssertFalse(info.allMinimized)
    }

    // MARK: - Visible weights stored

    func test_partialMinimize_visibleWeightsStored() {
        // Split(0.33, A, Split(0.5, B_min, C))
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let outerSplitId = UUID()
        let layout = Layout(
            root: .split(
                Layout.Split(
                    id: outerSplitId, direction: .horizontal, ratio: 0.33,
                    left: .leaf(paneId: a),
                    right: .split(
                        Layout.Split(
                            direction: .horizontal, ratio: 0.5,
                            left: .leaf(paneId: b), right: .leaf(paneId: c)
                        ))
                )))

        let info = SplitRenderInfo.compute(layout: layout, minimizedPaneIds: [b])
        let outerInfo = info.splitInfo[outerSplitId]!

        // Left is a single visible leaf → weight 1.0
        XCTAssertEqual(outerInfo.leftVisibleWeight, 1.0)
        // Right is Split(0.5, B_min, C) → 0*0.5 + 1*0.5 = 0.5
        XCTAssertEqual(outerInfo.rightVisibleWeight, 0.5)
    }

    // MARK: - Model ratio reverse conversion

    func test_modelRatio_roundTrip() {
        // Split(0.5, A, Split(0.5, B_min, C))
        // adjustedRatio ≈ 0.667. Converting back should yield 0.5.
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let outerSplitId = UUID()
        let layout = Layout(
            root: .split(
                Layout.Split(
                    id: outerSplitId, direction: .horizontal, ratio: 0.5,
                    left: .leaf(paneId: a),
                    right: .split(
                        Layout.Split(
                            direction: .horizontal, ratio: 0.5,
                            left: .leaf(paneId: b), right: .leaf(paneId: c)
                        ))
                )))

        let info = SplitRenderInfo.compute(layout: layout, minimizedPaneIds: [b])
        let outerInfo = info.splitInfo[outerSplitId]!

        // adjustedRatio should be 0.667 (left gets more space)
        XCTAssertEqual(outerInfo.adjustedRatio, 0.667, accuracy: 0.01)

        // Round-trip: converting adjustedRatio back should give original model ratio
        let recovered = outerInfo.modelRatio(fromRenderRatio: outerInfo.adjustedRatio)
        XCTAssertEqual(recovered, 0.5, accuracy: 0.001)
    }

    func test_modelRatio_equalWeights_identity() {
        // When both sides have equal visible weight, adjustedRatio == modelRatio.
        let splitInfo = SplitRenderInfo.SplitInfo(
            adjustedRatio: 0.5,
            leftFullyMinimized: false,
            rightFullyMinimized: false,
            leftMinimizedPaneIds: [],
            rightMinimizedPaneIds: [],
            leftVisibleWeight: 1.0,
            rightVisibleWeight: 1.0
        )

        XCTAssertEqual(splitInfo.modelRatio(fromRenderRatio: 0.3), 0.3, accuracy: 0.001)
        XCTAssertEqual(splitInfo.modelRatio(fromRenderRatio: 0.7), 0.7, accuracy: 0.001)
    }

    func test_modelRatio_zeroWeight_fallback() {
        // When one weight is zero, reverse conversion falls back to render ratio.
        let splitInfo = SplitRenderInfo.SplitInfo(
            adjustedRatio: 0.5,
            leftFullyMinimized: false,
            rightFullyMinimized: false,
            leftMinimizedPaneIds: [],
            rightMinimizedPaneIds: [],
            leftVisibleWeight: 0.0,
            rightVisibleWeight: 1.0
        )

        XCTAssertEqual(splitInfo.modelRatio(fromRenderRatio: 0.6), 0.6)
    }

    func test_modelRatio_asymmetricWeights_invertsCorrectly() {
        // Left weight 1.0, right weight 0.25
        // Forward: modelRatio=0.4 → adj = (1.0*0.4)/(1.0*0.4 + 0.25*0.6) = 0.4/0.55 ≈ 0.727
        // Reverse: 0.727 should map back to 0.4
        let splitInfo = SplitRenderInfo.SplitInfo(
            adjustedRatio: 0.727,
            leftFullyMinimized: false,
            rightFullyMinimized: false,
            leftMinimizedPaneIds: [],
            rightMinimizedPaneIds: [],
            leftVisibleWeight: 1.0,
            rightVisibleWeight: 0.25
        )

        let recovered = splitInfo.modelRatio(fromRenderRatio: 0.727)
        XCTAssertEqual(recovered, 0.4, accuracy: 0.01)
    }
}
