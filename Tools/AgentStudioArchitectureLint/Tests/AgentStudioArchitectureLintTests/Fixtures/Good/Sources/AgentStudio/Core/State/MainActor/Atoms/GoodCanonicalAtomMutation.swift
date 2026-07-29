final class GoodCanonicalAtomMutation {
    private(set) var count = 0
    private var pendingCount = 0
    let identity = "canonical"
    package private(set) lazy var derivedReader = GoodPaneDerived()

    var displayedCount: Int {
        count
    }

    func replaceCount(with replacement: Int) {
        count = replacement
    }
}

struct GoodAtomSnapshot {
    var count: Int
}

struct GoodPaneGraph {
    var paneIDs: [Int]
}

struct GoodPaneCursor {
    var paneIndex: Int
}

final class GoodPaneDerived {
    var cachedPaneIDs: [Int] = []
}
