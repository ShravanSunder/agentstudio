import Foundation

struct TerminalRestoreScheduler {
    @MainActor
    static func order(
        _ paneIds: [PaneId],
        resolver: some TerminalRestoreVisibilityResolving
    ) -> [PaneId] {
        paneIds.enumerated().sorted { lhs, rhs in
            let lhsTier = resolver.tier(for: lhs.element)
            let rhsTier = resolver.tier(for: rhs.element)

            if lhsTier != rhsTier {
                return lhsTier < rhsTier
            }

            let lhsIsActive = resolver.isActive(lhs.element)
            let rhsIsActive = resolver.isActive(rhs.element)
            if lhsTier == .p0Visible, lhsIsActive != rhsIsActive {
                return lhsIsActive
            }

            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    @MainActor
    static func shouldStartHiddenRestore(
        policy: BackgroundRestorePolicy,
        hasExistingSession: Bool
    ) -> Bool {
        switch policy {
        case .off:
            return false
        case .existingSessionsOnly:
            return hasExistingSession
        case .allTerminalPanes:
            return true
        }
    }
}

@MainActor
protocol TerminalRestoreVisibilityResolving: VisibilityTierResolver {
    func isActive(_ paneId: PaneId) -> Bool
}
