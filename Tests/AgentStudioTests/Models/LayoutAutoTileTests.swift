import XCTest

@testable import AgentStudio

final class LayoutAutoTileTests: XCTestCase {

    func test_autoTiled_empty_producesEmptyLayout() {
        let layout = Layout.autoTiled([])
        XCTAssertTrue(layout.isEmpty)
        XCTAssertEqual(layout.paneIds, [])
    }

    func test_autoTiled_singlePane_producesLeaf() {
        let paneId = UUID()
        let layout = Layout.autoTiled([paneId])

        XCTAssertFalse(layout.isEmpty)
        XCTAssertFalse(layout.isSplit)
        XCTAssertEqual(layout.paneIds, [paneId])
    }

    func test_autoTiled_twoPanes_producesSplit() {
        let a = UUID()
        let b = UUID()
        let layout = Layout.autoTiled([a, b])

        XCTAssertTrue(layout.isSplit)
        XCTAssertEqual(layout.paneIds.count, 2)
        XCTAssertEqual(Set(layout.paneIds), Set([a, b]))
    }

    func test_autoTiled_threePanes_allPresent() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let layout = Layout.autoTiled([a, b, c])

        XCTAssertEqual(layout.paneIds.count, 3)
        XCTAssertEqual(Set(layout.paneIds), Set([a, b, c]))
    }

    func test_autoTiled_fourPanes_balanced() {
        let ids = (0..<4).map { _ in UUID() }
        let layout = Layout.autoTiled(ids)

        XCTAssertEqual(layout.paneIds.count, 4)
        XCTAssertEqual(Set(layout.paneIds), Set(ids))

        // Root should be a split
        guard case .split(let root) = layout.root else {
            XCTFail("Expected root split")
            return
        }
        // First level: horizontal
        XCTAssertEqual(root.direction, .horizontal)

        // Both children should also be splits (2 panes each)
        guard case .split(let left) = root.left,
            case .split(let right) = root.right
        else {
            XCTFail("Expected both children to be splits for 4 panes")
            return
        }
        // Second level: vertical (alternating)
        XCTAssertEqual(left.direction, .vertical)
        XCTAssertEqual(right.direction, .vertical)
    }

    func test_autoTiled_manyPanes_containsAll() {
        let ids = (0..<10).map { _ in UUID() }
        let layout = Layout.autoTiled(ids)

        XCTAssertEqual(layout.paneIds.count, 10)
        XCTAssertEqual(Set(layout.paneIds), Set(ids))
    }

    func test_autoTiled_preservesOrder() {
        let ids = (0..<5).map { _ in UUID() }
        let layout = Layout.autoTiled(ids)

        // The left-to-right traversal of the tree should maintain input order
        XCTAssertEqual(layout.paneIds, ids)
    }

    func test_autoTiled_alternatesSplitDirection() {
        // With 4+ panes we should see alternating directions
        let ids = (0..<8).map { _ in UUID() }
        let layout = Layout.autoTiled(ids)

        guard case .split(let root) = layout.root else {
            XCTFail("Expected split root")
            return
        }

        // Root: horizontal
        XCTAssertEqual(root.direction, .horizontal)

        // Level 2: vertical
        if case .split(let left) = root.left {
            XCTAssertEqual(left.direction, .vertical)
        }
        if case .split(let right) = root.right {
            XCTAssertEqual(right.direction, .vertical)
        }
    }
}
