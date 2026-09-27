final class GoodAssignOnlyAtom {
    private(set) var rows: [Int] = []

    func replaceRows(_ newRows: [Int]) {
        guard rows != newRows else { return }
        rows = newRows
    }
}

struct GoodRowsDerived {
    let rows: [Int]

    var orderedRows: [Int] {
        rows.sorted()
    }
}

nonisolated func goodRowIndex(rows: [Int]) -> [Int] {
    rows.sorted()
}
