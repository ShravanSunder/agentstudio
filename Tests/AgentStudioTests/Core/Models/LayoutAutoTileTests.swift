import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class LayoutAutoTileTests {

    @Test

    func test_autoTiled_empty_producesEmptyLayout() {
        let layout = Layout.autoTiled([])
        #expect(layout.isEmpty)
        #expect(layout.paneIds == [])
    }

    @Test

    func test_autoTiled_singlePane_producesLeaf() {
        let paneId = UUID()
        let layout = Layout.autoTiled([paneId])

        #expect(!(layout.isEmpty))
        #expect(!(layout.isSplit))
        #expect(layout.paneIds == [paneId])
    }

    @Test

    func test_autoTiled_twoPanes_producesSplit() {
        let a = UUID()
        let b = UUID()
        let layout = Layout.autoTiled([a, b])

        #expect(layout.isSplit)
        #expect(layout.paneIds.count == 2)
        #expect(Set(layout.paneIds) == Set([a, b]))
    }

    @Test

    func test_autoTiled_threePanes_allPresent() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let layout = Layout.autoTiled([a, b, c])

        #expect(layout.paneIds.count == 3)
        #expect(Set(layout.paneIds) == Set([a, b, c]))
    }

    @Test

    func test_autoTiled_fourPanes_balanced() {
        let ids = (0..<4).map { _ in UUID() }
        let layout = Layout.autoTiled(ids)

        #expect(layout.paneIds.count == 4)
        #expect(Set(layout.paneIds) == Set(ids))

        // Root should be a split
        guard case .split(let root) = layout.root else {
            Issue.record("Expected root split")
            return
        }
        // First level: horizontal
        #expect(root.direction == .horizontal)

        // Both children should also be splits (2 panes each)
        guard case .split(let left) = root.left,
            case .split(let right) = root.right
        else {
            Issue.record("Expected both children to be splits for 4 panes")
            return
        }
        // Second level: vertical (alternating)
        #expect(left.direction == .vertical)
        #expect(right.direction == .vertical)
    }

    @Test

    func test_autoTiled_manyPanes_containsAll() {
        let ids = (0..<10).map { _ in UUID() }
        let layout = Layout.autoTiled(ids)

        #expect(layout.paneIds.count == 10)
        #expect(Set(layout.paneIds) == Set(ids))
    }

    @Test

    func test_autoTiled_preservesOrder() {
        let ids = (0..<5).map { _ in UUID() }
        let layout = Layout.autoTiled(ids)

        // The left-to-right traversal of the tree should maintain input order
        #expect(layout.paneIds == ids)
    }

    @Test

    func test_autoTiled_alternatesSplitDirection() {
        // With 4+ panes we should see alternating directions
        let ids = (0..<8).map { _ in UUID() }
        let layout = Layout.autoTiled(ids)

        guard case .split(let root) = layout.root else {
            Issue.record("Expected split root")
            return
        }

        // Root: horizontal
        #expect(root.direction == .horizontal)

        // Level 2: vertical
        if case .split(let left) = root.left {
            #expect(left.direction == .vertical)
        }
        if case .split(let right) = root.right {
            #expect(right.direction == .vertical)
        }
    }
}
