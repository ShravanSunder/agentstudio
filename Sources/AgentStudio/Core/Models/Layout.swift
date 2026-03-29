import Foundation

/// Flat pane strip layout shared by pane containers.
/// Every pane is a direct sibling in left-to-right order with a preserved width ratio.
struct Layout: Codable, Hashable {
    struct PaneEntry: Codable, Hashable {
        let paneId: UUID
        let ratio: Double
    }

    enum SplitDirection: String, Codable, Hashable {
        case horizontal
        case vertical
    }

    enum Position {
        case before
        case after
    }

    let panes: [PaneEntry]
    let dividerIds: [UUID]

    init() {
        self.panes = []
        self.dividerIds = []
    }

    init(paneId: UUID) {
        self.panes = [.init(paneId: paneId, ratio: 1.0)]
        self.dividerIds = []
    }

    init(panes: [PaneEntry], dividerIds: [UUID]) {
        precondition(
            dividerIds.count == max(panes.count - 1, 0),
            "Layout divider count must equal pane count minus one"
        )
        self.panes = Self.normalized(panes)
        self.dividerIds = dividerIds
    }

    private init(rawPanes: [PaneEntry], dividerIds: [UUID]) {
        self.panes = rawPanes
        self.dividerIds = dividerIds
    }

    static func autoTiled(_ paneIds: [UUID]) -> Self {
        guard !paneIds.isEmpty else { return Self() }
        let equalRatio = 1.0 / Double(paneIds.count)
        return Self(
            rawPanes: paneIds.map { PaneEntry(paneId: $0, ratio: equalRatio) },
            dividerIds: paneIds.dropFirst().map { _ in UUID() }
        )
    }

    var isEmpty: Bool { panes.isEmpty }

    var isSplit: Bool { panes.count > 1 }

    var paneIds: [UUID] { panes.map(\.paneId) }

    var ratios: [Double] { panes.map(\.ratio) }

    func contains(_ paneId: UUID) -> Bool {
        panes.contains { $0.paneId == paneId }
    }

    func inserting(
        paneId: UUID,
        at targetPaneId: UUID,
        direction _: SplitDirection,
        position: Position
    ) -> Self {
        guard let targetIndex = panes.firstIndex(where: { $0.paneId == targetPaneId }) else {
            return self
        }

        let target = panes[targetIndex]
        let splitRatio = target.ratio / 2.0
        let newEntry = PaneEntry(paneId: paneId, ratio: splitRatio)
        let resizedTarget = PaneEntry(paneId: target.paneId, ratio: splitRatio)

        var updatedPanes = panes
        updatedPanes[targetIndex] = resizedTarget

        let insertIndex: Int
        switch position {
        case .before:
            insertIndex = targetIndex
        case .after:
            insertIndex = targetIndex + 1
        }
        updatedPanes.insert(newEntry, at: insertIndex)

        var updatedDividerIds = dividerIds
        updatedDividerIds.insert(UUID(), at: max(insertIndex - 1, 0))
        return Self(panes: updatedPanes, dividerIds: updatedDividerIds)
    }

    func removing(paneId: UUID) -> Self? {
        guard let removedIndex = panes.firstIndex(where: { $0.paneId == paneId }) else {
            return self
        }
        guard panes.count > 1 else { return nil }

        var updatedPanes = panes
        let removedRatio = updatedPanes.remove(at: removedIndex).ratio

        if removedIndex < updatedPanes.count {
            let rightNeighbor = updatedPanes[removedIndex]
            updatedPanes[removedIndex] = PaneEntry(
                paneId: rightNeighbor.paneId,
                ratio: rightNeighbor.ratio + removedRatio
            )
        } else {
            let leftIndex = updatedPanes.index(before: updatedPanes.endIndex)
            let leftNeighbor = updatedPanes[leftIndex]
            updatedPanes[leftIndex] = PaneEntry(
                paneId: leftNeighbor.paneId,
                ratio: leftNeighbor.ratio + removedRatio
            )
        }

        var updatedDividerIds = dividerIds
        if !updatedDividerIds.isEmpty {
            let removedDividerIndex = min(removedIndex, updatedDividerIds.count - 1)
            updatedDividerIds.remove(at: removedDividerIndex)
        }
        return Self(panes: updatedPanes, dividerIds: updatedDividerIds)
    }

    func resizing(splitId: UUID, ratio: Double) -> Self {
        guard let dividerIndex = dividerIds.firstIndex(of: splitId) else { return self }
        let clampedRatio = min(0.9, max(0.1, ratio))
        let adjacentTotal = panes[dividerIndex].ratio + panes[dividerIndex + 1].ratio

        var updatedPanes = panes
        updatedPanes[dividerIndex] = PaneEntry(
            paneId: panes[dividerIndex].paneId,
            ratio: adjacentTotal * clampedRatio
        )
        updatedPanes[dividerIndex + 1] = PaneEntry(
            paneId: panes[dividerIndex + 1].paneId,
            ratio: adjacentTotal * (1.0 - clampedRatio)
        )
        return Self(panes: updatedPanes, dividerIds: dividerIds)
    }

    func equalized() -> Self {
        guard !panes.isEmpty else { return self }
        let equalRatio = 1.0 / Double(panes.count)
        return Self(
            rawPanes: panes.map { PaneEntry(paneId: $0.paneId, ratio: equalRatio) },
            dividerIds: dividerIds
        )
    }

    func resizeTarget(for paneId: UUID, direction: SplitResizeDirection) -> (splitId: UUID, increase: Bool)? {
        guard let paneIndex = panes.firstIndex(where: { $0.paneId == paneId }) else { return nil }
        switch direction {
        case .left:
            guard paneIndex > 0 else { return nil }
            return (dividerIds[paneIndex - 1], false)
        case .right:
            guard paneIndex < dividerIds.count else { return nil }
            return (dividerIds[paneIndex], true)
        case .up, .down:
            return nil
        }
    }

    func ratioForSplit(_ splitId: UUID) -> Double? {
        guard let dividerIndex = dividerIds.firstIndex(of: splitId) else { return nil }
        let leftRatio = panes[dividerIndex].ratio
        let rightRatio = panes[dividerIndex + 1].ratio
        let total = leftRatio + rightRatio
        guard total > 0 else { return nil }
        return leftRatio / total
    }

    func neighbor(of paneId: UUID, direction: FocusDirection) -> UUID? {
        guard let paneIndex = panes.firstIndex(where: { $0.paneId == paneId }) else { return nil }
        switch direction {
        case .left:
            guard paneIndex > 0 else { return nil }
            return panes[paneIndex - 1].paneId
        case .right:
            guard paneIndex < panes.index(before: panes.endIndex) else { return nil }
            return panes[paneIndex + 1].paneId
        case .up, .down:
            return nil
        }
    }

    func next(after paneId: UUID) -> UUID? {
        guard let index = panes.firstIndex(where: { $0.paneId == paneId }) else { return nil }
        let nextIndex = (index + 1) % panes.count
        return panes[nextIndex].paneId
    }

    func previous(before paneId: UUID) -> UUID? {
        guard let index = panes.firstIndex(where: { $0.paneId == paneId }) else { return nil }
        let previousIndex = (index - 1 + panes.count) % panes.count
        return panes[previousIndex].paneId
    }

    private static func normalized(_ panes: [PaneEntry]) -> [PaneEntry] {
        guard !panes.isEmpty else { return [] }
        let total = panes.reduce(0.0) { $0 + $1.ratio }
        guard total > 0 else {
            let equalRatio = 1.0 / Double(panes.count)
            return panes.map { PaneEntry(paneId: $0.paneId, ratio: equalRatio) }
        }
        let precision = 1_000_000_000_000.0
        return panes.map {
            let normalizedRatio = $0.ratio / total
            let roundedRatio = (normalizedRatio * precision).rounded() / precision
            return PaneEntry(paneId: $0.paneId, ratio: roundedRatio)
        }
    }
}

enum FocusDirection: Equatable, Hashable {
    case left, right, up, down
}
