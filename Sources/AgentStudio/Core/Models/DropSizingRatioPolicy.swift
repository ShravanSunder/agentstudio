import Foundation

enum DropSizingMode: Hashable, Sendable {
    case halveTarget
    case proportional
}

enum DropSizingRatioPolicy {
    static func ratiosAfterInsertion(
        existingRatios: [Double],
        insertionIndex: Int,
        targetPaneIndex: Int?,
        mode: DropSizingMode
    ) -> [Double] {
        if existingRatios.isEmpty { return [1.0] }

        let clampedInsertionIndex = max(0, min(insertionIndex, existingRatios.count))

        switch mode {
        case .halveTarget:
            guard let targetPaneIndex,
                targetPaneIndex >= 0,
                targetPaneIndex < existingRatios.count
            else {
                return ratiosAfterInsertion(
                    existingRatios: existingRatios,
                    insertionIndex: clampedInsertionIndex,
                    targetPaneIndex: nil,
                    mode: .proportional
                )
            }

            var updatedRatios = existingRatios
            let halvedTargetRatio = updatedRatios[targetPaneIndex] / 2.0
            updatedRatios[targetPaneIndex] = halvedTargetRatio
            updatedRatios.insert(halvedTargetRatio, at: clampedInsertionIndex)
            return updatedRatios

        case .proportional:
            let newPaneShare = 1.0 / Double(existingRatios.count + 1)
            let remainingShare = 1.0 - newPaneShare
            let existingRatioSum = existingRatios.reduce(0.0, +)
            let scale = existingRatioSum > 0 ? remainingShare / existingRatioSum : 0
            var updatedRatios = existingRatios.map { $0 * scale }
            updatedRatios.insert(newPaneShare, at: clampedInsertionIndex)
            return updatedRatios
        }
    }

    static func ratiosAfterRemoval(
        existingRatios: [Double],
        removalIndex: Int,
        mode: DropSizingMode
    ) -> [Double] {
        guard removalIndex >= 0, removalIndex < existingRatios.count else {
            return existingRatios
        }

        var updatedRatios = existingRatios
        let removedRatio = updatedRatios.remove(at: removalIndex)

        switch mode {
        case .halveTarget:
            if removalIndex < updatedRatios.count {
                updatedRatios[removalIndex] += removedRatio
            } else if !updatedRatios.isEmpty {
                updatedRatios[updatedRatios.index(before: updatedRatios.endIndex)] += removedRatio
            }
            return updatedRatios

        case .proportional:
            let remainingRatioSum = updatedRatios.reduce(0.0, +)
            guard remainingRatioSum > 0 else { return updatedRatios }

            let scale = (remainingRatioSum + removedRatio) / remainingRatioSum
            return updatedRatios.map { $0 * scale }
        }
    }
}
