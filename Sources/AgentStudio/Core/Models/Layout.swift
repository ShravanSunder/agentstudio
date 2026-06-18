import Foundation

/// Flat pane strip layout shared by pane containers.
/// Every pane is a direct sibling in left-to-right order with a preserved width ratio.
struct Layout: Codable, Hashable, Sendable {
    struct PaneEntry: Codable, Hashable, Sendable {
        let paneId: UUID
        let ratio: Double
    }

    enum SplitDirection: String, Codable, Hashable, Sendable {
        case horizontal
        case vertical
    }

    enum Position: Sendable {
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
        position: Position,
        sizingMode: DropSizingMode
    ) -> Self? {
        guard let targetIndex = panes.firstIndex(where: { $0.paneId == targetPaneId }) else {
            return nil
        }

        let insertIndex: Int
        switch position {
        case .before:
            insertIndex = targetIndex
        case .after:
            insertIndex = targetIndex + 1
        }

        guard
            let sizingMode = insertionSizingMode(
                for: sizingMode,
                insertionIndex: insertIndex,
                paneCount: panes.count,
                preferredTargetPaneIndex: targetIndex
            )
        else {
            return nil
        }

        let updatedRatios = DropSizingRatioPolicy.ratiosAfterInsertion(
            existingRatios: ratios,
            insertionIndex: insertIndex,
            mode: sizingMode
        )
        return inserting(paneId: paneId, atIndex: insertIndex, ratios: updatedRatios)
    }

    func inserting(paneId: UUID, atIndex insertionIndex: Int, ratios: [Double]) -> Self {
        precondition(ratios.count == panes.count + 1, "ratios must include the new pane")

        let clampedIndex = max(0, min(insertionIndex, panes.count))
        var updatedPanes = panes.enumerated().map { index, pane in
            PaneEntry(paneId: pane.paneId, ratio: ratios[index >= clampedIndex ? index + 1 : index])
        }
        updatedPanes.insert(PaneEntry(paneId: paneId, ratio: ratios[clampedIndex]), at: clampedIndex)

        var updatedDividerIds = dividerIds
        updatedDividerIds.insert(UUID(), at: max(clampedIndex - 1, 0))
        return Self(panes: updatedPanes, dividerIds: updatedDividerIds)
    }

    func removing(paneId: UUID, sizingMode: DropSizingMode) -> Self? {
        guard let removedIndex = panes.firstIndex(where: { $0.paneId == paneId }) else {
            return nil
        }
        guard panes.count > 1 else { return nil }

        let updatedRatios = DropSizingRatioPolicy.ratiosAfterRemoval(
            existingRatios: ratios,
            removalIndex: removedIndex,
            mode: sizingMode
        )
        return removing(paneId: paneId, atIndex: removedIndex, ratios: updatedRatios)
    }

    func removing(paneId _: UUID, atIndex removedIndex: Int, ratios: [Double]) -> Self? {
        precondition(ratios.count == panes.count - 1, "ratios must exclude the removed pane")
        guard panes.count > 1 else { return nil }

        let updatedPanes = panes.enumerated().compactMap { index, pane -> PaneEntry? in
            guard index != removedIndex else { return nil }
            let ratioIndex = index > removedIndex ? index - 1 : index
            return PaneEntry(paneId: pane.paneId, ratio: ratios[ratioIndex])
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

    func resizingPanePair(leftPaneId: UUID, rightPaneId: UUID, ratio: Double) -> Self {
        guard
            leftPaneId != rightPaneId,
            let leftIndex = panes.firstIndex(where: { $0.paneId == leftPaneId }),
            let rightIndex = panes.firstIndex(where: { $0.paneId == rightPaneId })
        else { return self }

        let clampedRatio = min(0.9, max(0.1, ratio))
        let pairTotal = panes[leftIndex].ratio + panes[rightIndex].ratio
        guard pairTotal > 0 else { return self }

        var updatedPanes = panes
        updatedPanes[leftIndex] = PaneEntry(
            paneId: panes[leftIndex].paneId,
            ratio: pairTotal * clampedRatio
        )
        updatedPanes[rightIndex] = PaneEntry(
            paneId: panes[rightIndex].paneId,
            ratio: pairTotal * (1.0 - clampedRatio)
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

    func ratioForPanePair(leftPaneId: UUID, rightPaneId: UUID) -> Double? {
        guard
            let leftPane = panes.first(where: { $0.paneId == leftPaneId }),
            let rightPane = panes.first(where: { $0.paneId == rightPaneId })
        else { return nil }
        let total = leftPane.ratio + rightPane.ratio
        guard total > 0 else { return nil }
        return leftPane.ratio / total
    }

    func paneRatio(_ paneId: UUID) -> Double? {
        panes.first { $0.paneId == paneId }?.ratio
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

    func insertionSizingMode(
        for sizingMode: DropSizingMode,
        insertionIndex: Int,
        paneCount: Int,
        preferredTargetPaneIndex: Int?
    ) -> DropInsertionSizingMode? {
        switch sizingMode {
        case .proportional:
            return .proportional
        case .halveTarget:
            if let preferredTargetPaneIndex {
                guard
                    let targetPaneIndex = DropTargetPaneIndex(
                        validating: preferredTargetPaneIndex,
                        paneCount: paneCount
                    )
                else {
                    return nil
                }
                return .halveTarget(paneIndex: targetPaneIndex)
            }
            let targetPaneIndex = max(0, min(max(insertionIndex - 1, 0), paneCount - 1))
            guard
                let targetPaneIndex = DropTargetPaneIndex(
                    validating: targetPaneIndex,
                    paneCount: paneCount
                )
            else {
                return nil
            }
            return .halveTarget(paneIndex: targetPaneIndex)
        }
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

enum FocusDirection: Equatable, Hashable, Sendable {
    case left, right, up, down
}
