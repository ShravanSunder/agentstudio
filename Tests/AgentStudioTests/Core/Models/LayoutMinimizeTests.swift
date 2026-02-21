import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class LayoutMinimizeTests {

    private func expectApproximately(_ actual: Double, equals expected: Double, tolerance: Double) {
        let difference = abs(actual - expected)
        #expect(
            difference <= tolerance,
            "Expected \(actual) to be within \(tolerance) of \(expected) (difference: \(difference))")
    }

    // MARK: - isFullyMinimized

    @Test

    func test_isFullyMinimized_singleVisibleLeaf_false() {
        let a = UUID()
        let node = Layout.Node.leaf(paneId: a)
        #expect(!(node.isFullyMinimized(minimizedPaneIds: [])))
    }

    @Test

    func test_isFullyMinimized_singleMinimizedLeaf_true() {
        let a = UUID()
        let node = Layout.Node.leaf(paneId: a)
        #expect(node.isFullyMinimized(minimizedPaneIds: [a]))
    }

    @Test

    func test_isFullyMinimized_subtreeAllMinimized_true() {
        let a = UUID()
        let b = UUID()
        let node = Layout.Node.split(
            Layout.Split(
                direction: .horizontal, ratio: 0.5,
                left: .leaf(paneId: a), right: .leaf(paneId: b)
            ))
        #expect(node.isFullyMinimized(minimizedPaneIds: [a, b]))
    }

    @Test

    func test_isFullyMinimized_subtreePartiallyMinimized_false() {
        let a = UUID()
        let b = UUID()
        let node = Layout.Node.split(
            Layout.Split(
                direction: .horizontal, ratio: 0.5,
                left: .leaf(paneId: a), right: .leaf(paneId: b)
            ))
        #expect(!(node.isFullyMinimized(minimizedPaneIds: [a])))
    }

    @Test

    func test_isFullyMinimized_deepNested_allMinimized() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let node = Layout.Node.split(
            Layout.Split(
                direction: .horizontal, ratio: 0.5,
                left: .leaf(paneId: a),
                right: .split(
                    Layout.Split(
                        direction: .vertical, ratio: 0.5,
                        left: .leaf(paneId: b), right: .leaf(paneId: c)
                    ))
            ))
        #expect(node.isFullyMinimized(minimizedPaneIds: [a, b, c]))
    }

    // MARK: - visibleWeight

    @Test

    func test_visibleWeight_singleVisible_returns1() {
        let a = UUID()
        let node = Layout.Node.leaf(paneId: a)
        expectApproximately(node.visibleWeight(minimizedPaneIds: []), equals: 1.0, tolerance: 0.001)
    }

    @Test

    func test_visibleWeight_singleMinimized_returns0() {
        let a = UUID()
        let node = Layout.Node.leaf(paneId: a)
        expectApproximately(node.visibleWeight(minimizedPaneIds: [a]), equals: 0.0, tolerance: 0.001)
    }

    @Test

    func test_visibleWeight_twoPane_oneMinimized() {
        let a = UUID()
        let b = UUID()
        let node = Layout.Node.split(
            Layout.Split(
                direction: .horizontal, ratio: 0.5,
                left: .leaf(paneId: a), right: .leaf(paneId: b)
            ))
        // B minimized: left weight = 0.5 * 1.0 = 0.5, right = 0.5 * 0.0 = 0
        expectApproximately(node.visibleWeight(minimizedPaneIds: [b]), equals: 0.5, tolerance: 0.001)
    }

    @Test

    func test_visibleWeight_threePane_oneMinimized() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let node = Layout.Node.split(
            Layout.Split(
                direction: .horizontal, ratio: 0.33,
                left: .leaf(paneId: a),
                right: .split(
                    Layout.Split(
                        direction: .horizontal, ratio: 0.5,
                        left: .leaf(paneId: b), right: .leaf(paneId: c)
                    ))
            ))
        // B minimized: A=0.33, C=0.67*0.5=0.335, total visible=0.665
        expectApproximately(node.visibleWeight(minimizedPaneIds: [b]), equals: 0.665, tolerance: 0.01)
    }

    @Test

    func test_visibleWeight_allMinimized_returns0() {
        let a = UUID()
        let b = UUID()
        let node = Layout.Node.split(
            Layout.Split(
                direction: .horizontal, ratio: 0.5,
                left: .leaf(paneId: a), right: .leaf(paneId: b)
            ))
        expectApproximately(node.visibleWeight(minimizedPaneIds: [a, b]), equals: 0.0, tolerance: 0.001)
    }

    @Test

    func test_visibleWeight_noneMinimized_returns1() {
        let a = UUID()
        let b = UUID()
        let node = Layout.Node.split(
            Layout.Split(
                direction: .horizontal, ratio: 0.4,
                left: .leaf(paneId: a), right: .leaf(paneId: b)
            ))
        expectApproximately(node.visibleWeight(minimizedPaneIds: []), equals: 1.0, tolerance: 0.001)
    }

    // MARK: - minimizedLeafCount

    @Test

    func test_minimizedLeafCount_none() {
        let a = UUID()
        let b = UUID()
        let node = Layout.Node.split(
            Layout.Split(
                direction: .horizontal, ratio: 0.5,
                left: .leaf(paneId: a), right: .leaf(paneId: b)
            ))
        #expect(node.minimizedLeafCount(minimizedPaneIds: []) == 0)
    }

    @Test

    func test_minimizedLeafCount_nested() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let node = Layout.Node.split(
            Layout.Split(
                direction: .horizontal, ratio: 0.5,
                left: .leaf(paneId: a),
                right: .split(
                    Layout.Split(
                        direction: .horizontal, ratio: 0.5,
                        left: .leaf(paneId: b), right: .leaf(paneId: c)
                    ))
            ))
        #expect(node.minimizedLeafCount(minimizedPaneIds: [b, c]) == 2)
    }

    // MARK: - orderedMinimizedPaneIds

    @Test

    func test_orderedMinimizedPaneIds_returnsInTreeOrder() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let node = Layout.Node.split(
            Layout.Split(
                direction: .horizontal, ratio: 0.5,
                left: .leaf(paneId: a),
                right: .split(
                    Layout.Split(
                        direction: .horizontal, ratio: 0.5,
                        left: .leaf(paneId: b), right: .leaf(paneId: c)
                    ))
            ))
        let ordered = node.orderedMinimizedPaneIds(minimizedPaneIds: [a, b, c])
        #expect(ordered == [a, b, c])
    }

    @Test

    func test_orderedMinimizedPaneIds_partialMinimize() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let node = Layout.Node.split(
            Layout.Split(
                direction: .horizontal, ratio: 0.5,
                left: .leaf(paneId: a),
                right: .split(
                    Layout.Split(
                        direction: .horizontal, ratio: 0.5,
                        left: .leaf(paneId: b), right: .leaf(paneId: c)
                    ))
            ))
        let ordered = node.orderedMinimizedPaneIds(minimizedPaneIds: [b])
        #expect(ordered == [b])
    }
}
