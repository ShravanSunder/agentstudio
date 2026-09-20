import AgentStudioInfrastructure
import Foundation

enum RepoExplorerNavigationDestinationID: Hashable, Sendable {
    case worktree(UUID)
    case pane(UUID)
}

struct RepoExplorerNavigationFingerprint: Equatable, Sendable {
    let rawValue: UInt64

    static let empty = Self(rawValue: 0)
}

struct RepoExplorerNavigationIndex: Equatable, Sendable {
    private struct RowClassification {
        let isSelectable: Bool
        let isGroup: Bool
        let destinationID: RepoExplorerNavigationDestinationID?
        let parentGroupID: String?
    }

    private struct FingerprintInput {
        let selectableRowIDs: [RepoExplorerRowID]
        let initialSelectionRowID: RepoExplorerRowID?
        let numberedDestinationRowIDs: [RepoExplorerRowID]
        let parentRowIDByChildRowID: [RepoExplorerRowID: RepoExplorerRowID]
        let firstChildRowIDByGroupRowID: [RepoExplorerRowID: RepoExplorerRowID]
        let digitByRowID: [RepoExplorerRowID: Int]
        let destinationIDByRowID: [RepoExplorerRowID: RepoExplorerNavigationDestinationID]
    }

    let selectableRowIDs: [RepoExplorerRowID]
    let initialSelectionRowID: RepoExplorerRowID?
    let numberedDestinationRowIDs: [RepoExplorerRowID]
    let fingerprint: RepoExplorerNavigationFingerprint

    private let selectablePositionByRowID: [RepoExplorerRowID: Int]
    private let parentRowIDByChildRowID: [RepoExplorerRowID: RepoExplorerRowID]
    private let firstChildRowIDByGroupRowID: [RepoExplorerRowID: RepoExplorerRowID]
    private let digitByRowID: [RepoExplorerRowID: Int]
    private let destinationIDByRowID: [RepoExplorerRowID: RepoExplorerNavigationDestinationID]
    private let rowIDsByDestinationID: [RepoExplorerNavigationDestinationID: [RepoExplorerRowID]]

    init(rows: [RepoExplorerMaterializedRow]) {
        let expandedGroupRowIDByGroupID = Dictionary(
            uniqueKeysWithValues: rows.compactMap { row -> (String, RepoExplorerRowID)? in
                guard case .groupHeader(let group) = row.presentation, group.isExpanded else {
                    return nil
                }
                return (group.groupID, row.id)
            }
        )
        var selectableRowIDs: [RepoExplorerRowID] = []
        var selectablePositionByRowID: [RepoExplorerRowID: Int] = [:]
        var parentRowIDByChildRowID: [RepoExplorerRowID: RepoExplorerRowID] = [:]
        var firstChildRowIDByGroupRowID: [RepoExplorerRowID: RepoExplorerRowID] = [:]
        var destinationIDByRowID: [RepoExplorerRowID: RepoExplorerNavigationDestinationID] = [:]
        var rowIDsByDestinationID: [RepoExplorerNavigationDestinationID: [RepoExplorerRowID]] = [:]
        var firstGroupRowID: RepoExplorerRowID?
        var firstDestinationRowID: RepoExplorerRowID?

        selectableRowIDs.reserveCapacity(rows.count)
        selectablePositionByRowID.reserveCapacity(rows.count)
        destinationIDByRowID.reserveCapacity(rows.count)

        for row in rows {
            let classification = Self.classify(row.presentation)
            guard classification.isSelectable else { continue }

            selectablePositionByRowID[row.id] = selectableRowIDs.count
            selectableRowIDs.append(row.id)

            if classification.isGroup {
                firstGroupRowID = firstGroupRowID ?? row.id
            }
            if let destinationID = classification.destinationID {
                firstDestinationRowID = firstDestinationRowID ?? row.id
                destinationIDByRowID[row.id] = destinationID
                rowIDsByDestinationID[destinationID, default: []].append(row.id)
            }
            if let groupID = classification.parentGroupID,
                let groupRowID = expandedGroupRowIDByGroupID[groupID]
            {
                parentRowIDByChildRowID[row.id] = groupRowID
                firstChildRowIDByGroupRowID[groupRowID] =
                    firstChildRowIDByGroupRowID[groupRowID] ?? row.id
            }
        }

        let orderedNumberedDestinationRowIDs = Array(
            selectableRowIDs.lazy
                .filter { destinationIDByRowID[$0] != nil }
                .prefix(AppPolicies.SidebarNavigation.maximumNumberedDestinations)
        )
        var digitByRowID: [RepoExplorerRowID: Int] = [:]
        digitByRowID.reserveCapacity(orderedNumberedDestinationRowIDs.count)
        for (index, rowID) in orderedNumberedDestinationRowIDs.enumerated() {
            digitByRowID[rowID] = index + 1
        }

        let initialSelectionRowID = firstDestinationRowID ?? firstGroupRowID
        self.selectableRowIDs = selectableRowIDs
        self.initialSelectionRowID = initialSelectionRowID
        self.numberedDestinationRowIDs = orderedNumberedDestinationRowIDs
        fingerprint = Self.makeFingerprint(
            FingerprintInput(
                selectableRowIDs: selectableRowIDs,
                initialSelectionRowID: initialSelectionRowID,
                numberedDestinationRowIDs: orderedNumberedDestinationRowIDs,
                parentRowIDByChildRowID: parentRowIDByChildRowID,
                firstChildRowIDByGroupRowID: firstChildRowIDByGroupRowID,
                digitByRowID: digitByRowID,
                destinationIDByRowID: destinationIDByRowID
            )
        )
        self.selectablePositionByRowID = selectablePositionByRowID
        self.parentRowIDByChildRowID = parentRowIDByChildRowID
        self.firstChildRowIDByGroupRowID = firstChildRowIDByGroupRowID
        self.digitByRowID = digitByRowID
        self.destinationIDByRowID = destinationIDByRowID
        self.rowIDsByDestinationID = rowIDsByDestinationID
    }

    func containsSelectableRow(_ rowID: RepoExplorerRowID) -> Bool {
        selectablePositionByRowID[rowID] != nil
    }

    func previousSelectableRowID(before rowID: RepoExplorerRowID) -> RepoExplorerRowID? {
        guard let position = selectablePositionByRowID[rowID], position > 0 else { return nil }
        return selectableRowIDs[position - 1]
    }

    func nextSelectableRowID(after rowID: RepoExplorerRowID) -> RepoExplorerRowID? {
        guard let position = selectablePositionByRowID[rowID], position + 1 < selectableRowIDs.count else {
            return nil
        }
        return selectableRowIDs[position + 1]
    }

    func previousNumberedDestinationRowID(before rowID: RepoExplorerRowID) -> RepoExplorerRowID? {
        guard let position = selectablePositionByRowID[rowID] else { return nil }
        return numberedDestinationRowIDs.last {
            guard let candidatePosition = selectablePositionByRowID[$0] else { return false }
            return candidatePosition < position
        }
    }

    func nextNumberedDestinationRowID(after rowID: RepoExplorerRowID) -> RepoExplorerRowID? {
        guard let position = selectablePositionByRowID[rowID] else { return nil }
        return numberedDestinationRowIDs.first {
            guard let candidatePosition = selectablePositionByRowID[$0] else { return false }
            return candidatePosition > position
        }
    }

    func parentRowID(for rowID: RepoExplorerRowID) -> RepoExplorerRowID? {
        parentRowIDByChildRowID[rowID]
    }

    func firstChildRowID(for rowID: RepoExplorerRowID) -> RepoExplorerRowID? {
        firstChildRowIDByGroupRowID[rowID]
    }

    func rowID(forDigit digit: Int) -> RepoExplorerRowID? {
        guard digit > 0 else { return nil }
        guard numberedDestinationRowIDs.indices.contains(digit - 1) else { return nil }
        return numberedDestinationRowIDs[digit - 1]
    }

    func digit(for rowID: RepoExplorerRowID) -> Int? {
        digitByRowID[rowID]
    }

    func destinationID(for rowID: RepoExplorerRowID) -> RepoExplorerNavigationDestinationID? {
        destinationIDByRowID[rowID]
    }

    func firstRowID(for destinationID: RepoExplorerNavigationDestinationID) -> RepoExplorerRowID? {
        rowIDsByDestinationID[destinationID]?.first
    }

    private static func makeFingerprint(
        _ input: FingerprintInput
    ) -> RepoExplorerNavigationFingerprint {
        guard !input.selectableRowIDs.isEmpty else { return .empty }

        var hasher = Hasher()
        hasher.combine(input.selectableRowIDs.count)
        hasher.combine(input.initialSelectionRowID)
        hasher.combine(input.numberedDestinationRowIDs.count)
        for rowID in input.selectableRowIDs {
            hasher.combine(rowID)
            hasher.combine(input.destinationIDByRowID[rowID])
            hasher.combine(input.parentRowIDByChildRowID[rowID])
            hasher.combine(input.firstChildRowIDByGroupRowID[rowID])
            hasher.combine(input.digitByRowID[rowID])
        }
        for rowID in input.numberedDestinationRowIDs {
            hasher.combine(rowID)
        }
        return RepoExplorerNavigationFingerprint(
            rawValue: UInt64(bitPattern: Int64(hasher.finalize()))
        )
    }

    private static func classify(
        _ presentation: RepoExplorerMaterializedRowPresentation
    ) -> RowClassification {
        switch presentation {
        case .groupHeader:
            return RowClassification(
                isSelectable: true,
                isGroup: true,
                destinationID: nil,
                parentGroupID: nil
            )
        case .worktree(let worktree):
            return RowClassification(
                isSelectable: true,
                isGroup: false,
                destinationID: .worktree(worktree.worktree.id),
                parentGroupID: worktree.groupID
            )
        case .pane(let pane):
            return RowClassification(
                isSelectable: true,
                isGroup: false,
                destinationID: .pane(pane.destination.paneId),
                parentGroupID: pane.groupId
            )
        case .unassociatedPane(let pane):
            return RowClassification(
                isSelectable: true,
                isGroup: false,
                destinationID: .pane(pane.destination.paneId),
                parentGroupID: nil
            )
        case .activitySubgroup, .sectionHeader, .loadingSectionHeader, .loadingRepository,
            .topologyFault, .unresolved:
            return RowClassification(
                isSelectable: false,
                isGroup: false,
                destinationID: nil,
                parentGroupID: nil
            )
        }
    }
}
