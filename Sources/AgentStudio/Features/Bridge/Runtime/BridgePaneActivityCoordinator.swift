import Foundation
import Observation

enum BridgePaneActivity: String, Equatable, Sendable {
    case foreground
    case loadedHidden
    case dormant
    case closed
}

/// Canonical native facts used to derive one Bridge pane's activity.
///
/// Key-window, native focus, browser visibility, and active viewer mode are
/// deliberately absent. They may affect scheduling rank or presentation, but
/// none of them can mint foreground activity.
struct BridgePaneActivityFacts: Equatable, Sendable {
    let residency: SessionResidency
    let isControllerInstalled: Bool
    let isInActiveTab: Bool
    let isInActiveArrangement: Bool
    let isInExpandedDrawer: Bool
    let isMinimized: Bool
    let isZoomExcluded: Bool
    let isOwningWindowVisible: Bool
    let isOwningWindowMiniaturized: Bool
    let isOwningWindowOccluded: Bool
    let isApplicationActive: Bool
    let isAuthorityClosed: Bool
}

/// Sole activity mint for one Bridge pane authority lifetime.
///
/// A fresh coordinator begins dormant. Installing a controller permanently
/// establishes that the pane has loaded in this app lifetime, so a later
/// temporary controller absence can only produce loaded-hidden. Closing the
/// authority is terminal; undo/reopen creates a fresh authority and coordinator.
@Observable
@MainActor
final class BridgePaneActivityCoordinator {
    private(set) var activity: BridgePaneActivity = .dormant
    private var hasLoadedInAppLifetime = false

    @discardableResult
    func update(from facts: BridgePaneActivityFacts) -> BridgePaneActivity {
        if activity == .closed || facts.isAuthorityClosed {
            activity = .closed
            return activity
        }

        if facts.isControllerInstalled {
            hasLoadedInAppLifetime = true
        }

        activity = Self.deriveActivity(
            from: facts,
            hasLoadedInAppLifetime: hasLoadedInAppLifetime
        )
        return activity
    }

    func close() {
        activity = .closed
    }

    nonisolated private static func deriveActivity(
        from facts: BridgePaneActivityFacts,
        hasLoadedInAppLifetime: Bool
    ) -> BridgePaneActivity {
        guard hasLoadedInAppLifetime else { return .dormant }
        guard facts.isControllerInstalled else { return .loadedHidden }

        let isPaneVisibleInActiveWorkspaceSurface =
            facts.isInActiveTab
            && (facts.isInActiveArrangement || facts.isInExpandedDrawer)
        let isForeground =
            facts.residency.isActive
            && isPaneVisibleInActiveWorkspaceSurface
            && !facts.isMinimized
            && !facts.isZoomExcluded
            && facts.isOwningWindowVisible
            && !facts.isOwningWindowMiniaturized
            && !facts.isOwningWindowOccluded
            && facts.isApplicationActive

        return isForeground ? .foreground : .loadedHidden
    }
}
