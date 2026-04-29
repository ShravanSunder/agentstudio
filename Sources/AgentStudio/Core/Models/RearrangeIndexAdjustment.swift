import Foundation

enum RearrangeIndexAdjustment {
    static func adjustedInsertionIndex<Row: Equatable>(
        sourceRow: Row,
        sourceIndex: Int,
        targetRow: Row,
        originalInsertionIndex: Int
    ) -> Int {
        guard sourceRow == targetRow else { return originalInsertionIndex }

        return sourceIndex < originalInsertionIndex
            ? originalInsertionIndex - 1
            : originalInsertionIndex
    }
}
