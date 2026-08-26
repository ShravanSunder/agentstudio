import AgentStudioCore
import Foundation
import Observation

package enum BridgePaneActivity: String, Codable, Equatable, Sendable {
    case foreground
    case loadedHidden
    case dormant
    case closed
}

/// Canonical native facts used to derive one Bridge pane's activity.
///
/// Application activation, key-window, native focus, browser visibility, and
/// active viewer mode are deliberately absent. They may affect scheduling rank
/// or presentation, but none of them can mint or revoke foreground activity.
package struct BridgePaneActivityFacts: Equatable, Sendable {
    package let residency: SessionResidency
    package let isControllerInstalled: Bool
    package let isInActiveTab: Bool
    package let isInActiveArrangement: Bool
    package let isInExpandedDrawer: Bool
    package let isMinimized: Bool
    package let isZoomExcluded: Bool
    package let isOwningWindowVisible: Bool
    package let isOwningWindowMiniaturized: Bool
    package let isOwningWindowOccluded: Bool
    package let isAuthorityClosed: Bool

    package init(
        residency: SessionResidency,
        isControllerInstalled: Bool,
        isInActiveTab: Bool,
        isInActiveArrangement: Bool,
        isInExpandedDrawer: Bool,
        isMinimized: Bool,
        isZoomExcluded: Bool,
        isOwningWindowVisible: Bool,
        isOwningWindowMiniaturized: Bool,
        isOwningWindowOccluded: Bool,
        isAuthorityClosed: Bool
    ) {
        self.residency = residency
        self.isControllerInstalled = isControllerInstalled
        self.isInActiveTab = isInActiveTab
        self.isInActiveArrangement = isInActiveArrangement
        self.isInExpandedDrawer = isInExpandedDrawer
        self.isMinimized = isMinimized
        self.isZoomExcluded = isZoomExcluded
        self.isOwningWindowVisible = isOwningWindowVisible
        self.isOwningWindowMiniaturized = isOwningWindowMiniaturized
        self.isOwningWindowOccluded = isOwningWindowOccluded
        self.isAuthorityClosed = isAuthorityClosed
    }
}

/// Sole activity mint for one Bridge pane authority lifetime.
///
/// A fresh coordinator begins dormant. Installing a controller permanently
/// establishes that the pane has loaded in this app lifetime, so a later
/// temporary controller absence can only produce loaded-hidden. Closing the
/// authority is terminal; undo/reopen creates a fresh authority and coordinator.
@Observable
@MainActor
package final class BridgePaneActivityCoordinator {
    package private(set) var activity: BridgePaneActivity = .dormant
    private var hasLoadedInAppLifetime = false

    package init() {}

    @discardableResult
    package func update(from facts: BridgePaneActivityFacts) -> BridgePaneActivity {
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

    package func close() {
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

        return isForeground ? .foreground : .loadedHidden
    }
}
