struct RepoExplorerSelectionReconciliation: Equatable, Sendable {
    let initialRowID: RepoExplorerRowID?

    private let targetRowIDByPriorRowID: [RepoExplorerRowID: RepoExplorerRowID]

    init(
        previous: RepoExplorerNavigationIndex,
        current: RepoExplorerNavigationIndex
    ) {
        initialRowID = current.initialSelectionRowID

        let directTranslations = previous.selectableRowIDs.map { priorRowID in
            Self.directTranslation(
                for: priorRowID,
                previous: previous,
                current: current
            )
        }
        let nearestSuccessors = Self.nearestSuccessors(in: directTranslations)
        let nearestPredecessors = Self.nearestPredecessors(in: directTranslations)
        var targetRowIDByPriorRowID: [RepoExplorerRowID: RepoExplorerRowID] = [:]
        targetRowIDByPriorRowID.reserveCapacity(previous.selectableRowIDs.count)

        for (index, priorRowID) in previous.selectableRowIDs.enumerated() {
            let targetRowID =
                directTranslations[index]
                ?? nearestSuccessors[index]
                ?? nearestPredecessors[index]
                ?? current.initialSelectionRowID
            if let targetRowID {
                targetRowIDByPriorRowID[priorRowID] = targetRowID
            }
        }

        self.targetRowIDByPriorRowID = targetRowIDByPriorRowID
    }

    func targetRowID(for priorRowID: RepoExplorerRowID?) -> RepoExplorerRowID? {
        guard let priorRowID else { return initialRowID }
        return targetRowIDByPriorRowID[priorRowID] ?? initialRowID
    }

    private static func directTranslation(
        for priorRowID: RepoExplorerRowID,
        previous: RepoExplorerNavigationIndex,
        current: RepoExplorerNavigationIndex
    ) -> RepoExplorerRowID? {
        if current.containsSelectableRow(priorRowID) {
            return priorRowID
        }
        guard let destinationID = previous.destinationID(for: priorRowID) else {
            return nil
        }
        return current.firstRowID(for: destinationID)
    }

    private static func nearestSuccessors(
        in directTranslations: [RepoExplorerRowID?]
    ) -> [RepoExplorerRowID?] {
        var nearestSuccessors = [RepoExplorerRowID?](
            repeating: nil,
            count: directTranslations.count
        )
        var nearestSuccessor: RepoExplorerRowID?
        for index in directTranslations.indices.reversed() {
            nearestSuccessors[index] = nearestSuccessor
            nearestSuccessor = directTranslations[index] ?? nearestSuccessor
        }
        return nearestSuccessors
    }

    private static func nearestPredecessors(
        in directTranslations: [RepoExplorerRowID?]
    ) -> [RepoExplorerRowID?] {
        var nearestPredecessors = [RepoExplorerRowID?](
            repeating: nil,
            count: directTranslations.count
        )
        var nearestPredecessor: RepoExplorerRowID?
        for index in directTranslations.indices {
            nearestPredecessors[index] = nearestPredecessor
            nearestPredecessor = directTranslations[index] ?? nearestPredecessor
        }
        return nearestPredecessors
    }
}
