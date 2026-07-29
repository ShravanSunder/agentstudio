import Foundation

package struct BridgePaneCommandCandidate: Equatable, Sendable {
    package let paneId: UUID
    package let worktreeId: UUID
    package let isBridgePane: Bool
    package let isPaneActive: Bool
    package let isCurrentActivePane: Bool
    package let attendanceOrdinal: UInt64?
    package let tabIndex: Int
    package let paneIndexInTab: Int

    package init(
        paneId: UUID,
        worktreeId: UUID,
        isBridgePane: Bool,
        isPaneActive: Bool,
        isCurrentActivePane: Bool,
        attendanceOrdinal: UInt64?,
        tabIndex: Int,
        paneIndexInTab: Int
    ) {
        self.paneId = paneId
        self.worktreeId = worktreeId
        self.isBridgePane = isBridgePane
        self.isPaneActive = isPaneActive
        self.isCurrentActivePane = isCurrentActivePane
        self.attendanceOrdinal = attendanceOrdinal
        self.tabIndex = tabIndex
        self.paneIndexInTab = paneIndexInTab
    }
}

package enum BridgePaneCommandResolution: Equatable, Sendable {
    case reuse(paneId: UUID)
    case create

    package func contextualLabel(for command: AppCommand) -> String {
        switch command {
        case .showBridgeReview, .showBridgeFiles:
            let action =
                switch self {
                case .create: "Open"
                case .reuse: "Go to"
                }
            return "\(action) \(command.definition.label)"
        default:
            return command.definition.label
        }
    }
}

package struct BridgePaneCommandTarget: Equatable, Sendable {
    package let worktreeId: UUID
    package let resolution: BridgePaneCommandResolution

    package init(
        worktreeId: UUID,
        resolution: BridgePaneCommandResolution
    ) {
        self.worktreeId = worktreeId
        self.resolution = resolution
    }
}

package enum BridgePaneCommandResolver {
    package static func resolve(
        worktreeId: UUID,
        candidates: [BridgePaneCommandCandidate]
    ) -> BridgePaneCommandResolution {
        let eligibleCandidates = candidates.filter {
            $0.worktreeId == worktreeId && $0.isBridgePane && $0.isPaneActive
        }
        guard let selectedCandidate = eligibleCandidates.min(by: isOrderedBefore) else {
            return .create
        }
        return .reuse(paneId: selectedCandidate.paneId)
    }

    private static func isOrderedBefore(
        _ lhs: BridgePaneCommandCandidate,
        _ rhs: BridgePaneCommandCandidate
    ) -> Bool {
        let lhsOrdinal = lhs.attendanceOrdinal ?? 0
        let rhsOrdinal = rhs.attendanceOrdinal ?? 0
        if lhsOrdinal != rhsOrdinal {
            return lhsOrdinal > rhsOrdinal
        }
        if lhs.isCurrentActivePane != rhs.isCurrentActivePane {
            return lhs.isCurrentActivePane
        }
        if lhs.tabIndex != rhs.tabIndex {
            return lhs.tabIndex < rhs.tabIndex
        }
        if lhs.paneIndexInTab != rhs.paneIndexInTab {
            return lhs.paneIndexInTab < rhs.paneIndexInTab
        }
        return lhs.paneId.uuidString < rhs.paneId.uuidString
    }
}
