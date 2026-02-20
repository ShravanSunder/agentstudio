import XCTest

@testable import AgentStudio

final class LayoutMinimizeTests: XCTestCase {

    // MARK: - isFullyMinimized

    func test_isFullyMinimized_singleVisibleLeaf_false() {
        let a = UUID()
        let node = Layout.Node.leaf(paneId: a)
        XCTAssertFalse(node.isFullyMinimized(minimizedPaneIds: []))
    }

    func test_isFullyMinimized_singleMinimizedLeaf_true() {
        let a = UUID()
        let node = Layout.Node.leaf(paneId: a)
        XCTAssertTrue(node.isFullyMinimized(minimizedPaneIds: [a]))
    }

    func test_isFullyMinimized_subtreeAllMinimized_true() {
        let a = UUID()
        let b = UUID()
        let node = Layout.Node.split(
            Layout.Split(
                direction: .horizontal, ratio: 0.5,
                left: .leaf(paneId: a), right: .leaf(paneId: b)
            ))
        XCTAssertTrue(node.isFullyMinimized(minimizedPaneIds: [a, b]))
    }

    func test_isFullyMinimized_subtreePartiallyMinimized_false() {
        let a = UUID()
        let b = UUID()
        let node = Layout.Node.split(
            Layout.Split(
                direction: .horizontal, ratio: 0.5,
                left: .leaf(paneId: a), right: .leaf(paneId: b)
            ))
        XCTAssertFalse(node.isFullyMinimized(minimizedPaneIds: [a]))
    }

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
        XCTAssertTrue(node.isFullyMinimized(minimizedPaneIds: [a, b, c]))
    }

    // MARK: - visibleWeight

    func test_visibleWeight_singleVisible_returns1() {
        let a = UUID()
        let node = Layout.Node.leaf(paneId: a)
        XCTAssertEqual(node.visibleWeight(minimizedPaneIds: []), 1.0, accuracy: 0.001)
    }

    func test_visibleWeight_singleMinimized_returns0() {
        let a = UUID()
        let node = Layout.Node.leaf(paneId: a)
        XCTAssertEqual(node.visibleWeight(minimizedPaneIds: [a]), 0.0, accuracy: 0.001)
    }

    func test_visibleWeight_twoPane_oneMinimized() {
        let a = UUID()
        let b = UUID()
        let node = Layout.Node.split(
            Layout.Split(
                direction: .horizontal, ratio: 0.5,
                left: .leaf(paneId: a), right: .leaf(paneId: b)
            ))
        // B minimized: left weight = 0.5 * 1.0 = 0.5, right = 0.5 * 0.0 = 0
        XCTAssertEqual(node.visibleWeight(minimizedPaneIds: [b]), 0.5, accuracy: 0.001)
    }

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
        XCTAssertEqual(node.visibleWeight(minimizedPaneIds: [b]), 0.665, accuracy: 0.01)
    }

    func test_visibleWeight_allMinimized_returns0() {
        let a = UUID()
        let b = UUID()
        let node = Layout.Node.split(
            Layout.Split(
                direction: .horizontal, ratio: 0.5,
                left: .leaf(paneId: a), right: .leaf(paneId: b)
            ))
        XCTAssertEqual(node.visibleWeight(minimizedPaneIds: [a, b]), 0.0, accuracy: 0.001)
    }

    func test_visibleWeight_noneMinimized_returns1() {
        let a = UUID()
        let b = UUID()
        let node = Layout.Node.split(
            Layout.Split(
                direction: .horizontal, ratio: 0.4,
                left: .leaf(paneId: a), right: .leaf(paneId: b)
            ))
        XCTAssertEqual(node.visibleWeight(minimizedPaneIds: []), 1.0, accuracy: 0.001)
    }

    // MARK: - minimizedLeafCount

    func test_minimizedLeafCount_none() {
        let a = UUID()
        let b = UUID()
        let node = Layout.Node.split(
            Layout.Split(
                direction: .horizontal, ratio: 0.5,
                left: .leaf(paneId: a), right: .leaf(paneId: b)
            ))
        XCTAssertEqual(node.minimizedLeafCount(minimizedPaneIds: []), 0)
    }

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
        XCTAssertEqual(node.minimizedLeafCount(minimizedPaneIds: [b, c]), 2)
    }

    // MARK: - orderedMinimizedPaneIds

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
        XCTAssertEqual(ordered, [a, b, c])
    }

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
        XCTAssertEqual(ordered, [b])
    }
}
