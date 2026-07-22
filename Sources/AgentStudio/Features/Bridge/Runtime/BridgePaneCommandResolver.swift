import Foundation

struct BridgePaneCommandCandidate: Equatable, Sendable {
    let paneId: UUID
    let worktreeId: UUID
    let isBridgePane: Bool
    let isPaneActive: Bool
    let isCurrentActivePane: Bool
    let attendanceOrdinal: UInt64?
    let tabIndex: Int
    let paneIndexInTab: Int
}

enum BridgePaneCommandResolution: Equatable, Sendable {
    case reuse(paneId: UUID)
    case create

    func contextualLabel(for surface: BridgeProductSurface) -> String {
        switch (self, surface) {
        case (.create, .review): "Open Review"
        case (.create, .file): "Open Files"
        case (.reuse, .review): "Go to Review"
        case (.reuse, .file): "Go to Files"
        }
    }
}

struct BridgePaneCommandTarget: Equatable, Sendable {
    let worktreeId: UUID
    let resolution: BridgePaneCommandResolution
}

enum BridgePaneCommandResolver {
    static func resolve(
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
