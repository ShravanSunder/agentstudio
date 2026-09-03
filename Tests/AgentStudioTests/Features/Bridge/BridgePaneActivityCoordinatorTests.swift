import AgentStudioCore
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge pane activity coordinator")
@MainActor
struct BridgePaneActivityCoordinatorTests {
    @Test(
        "every independent foreground fact demotes a loaded pane",
        arguments: BridgePaneActivityFactMutation.allForegroundDemotions
    )
    func everyIndependentForegroundFactDemotesLoadedPane(
        mutation: BridgePaneActivityFactMutation
    ) {
        // Arrange
        let coordinator = BridgePaneActivityCoordinator()
        #expect(coordinator.update(from: .foreground) == .foreground)

        // Act
        let activity = coordinator.update(from: mutation.apply(to: .foreground))

        // Assert
        #expect(activity == .loadedHidden)
    }

    @Test("an installed controller with every pane activity fact is foreground")
    func installedVisibleControllerIsForeground() {
        // Arrange
        let coordinator = BridgePaneActivityCoordinator()

        // Act
        let activity = coordinator.update(from: .foreground)

        // Assert
        #expect(activity == .foreground)
    }

    @Test("an expanded drawer can supply the active surface visibility fact")
    func expandedDrawerCanSupplyActiveSurfaceVisibility() {
        // Arrange
        let coordinator = BridgePaneActivityCoordinator()
        let drawerFacts = BridgePaneActivityFacts.foreground.replacing(
            isInActiveArrangement: false,
            isInExpandedDrawer: true
        )

        // Act
        let activity = coordinator.update(from: drawerFacts)

        // Assert
        #expect(activity == .foreground)
    }

    @Test("collapsing the only visible drawer hides a loaded pane")
    func collapsedDrawerHidesLoadedPane() {
        // Arrange
        let coordinator = BridgePaneActivityCoordinator()
        let expandedDrawerFacts = BridgePaneActivityFacts.foreground.replacing(
            isInActiveArrangement: false,
            isInExpandedDrawer: true
        )
        #expect(coordinator.update(from: expandedDrawerFacts) == .foreground)

        // Act
        let activity = coordinator.update(
            from: expandedDrawerFacts.replacing(isInExpandedDrawer: false)
        )

        // Assert
        #expect(activity == .loadedHidden)
    }

    @Test("key or focus is not required to mint foreground")
    func keyOrFocusIsNotRequiredForForeground() {
        // Arrange
        let coordinator = BridgePaneActivityCoordinator()

        // Act
        let activity = coordinator.update(from: .foreground)

        // Assert
        #expect(activity == .foreground)
    }

    @Test("a never-loaded pane without a controller is dormant")
    func neverLoadedPaneWithoutControllerIsDormant() {
        // Arrange
        let coordinator = BridgePaneActivityCoordinator()

        // Act
        let activity = coordinator.update(
            from: BridgePaneActivityFacts.foreground.replacing(isControllerInstalled: false)
        )

        // Assert
        #expect(activity == .dormant)
    }

    @Test("a loaded pane never demotes to dormant when its controller is temporarily absent")
    func loadedPaneNeverDemotesToDormant() {
        // Arrange
        let coordinator = BridgePaneActivityCoordinator()
        #expect(coordinator.update(from: .foreground) == .foreground)

        // Act
        let activity = coordinator.update(
            from: BridgePaneActivityFacts.foreground.replacing(isControllerInstalled: false)
        )

        // Assert
        #expect(activity == .loadedHidden)
    }

    @Test("closed authority is terminal for one coordinator lifetime")
    func closedAuthorityIsTerminal() {
        // Arrange
        let coordinator = BridgePaneActivityCoordinator()
        #expect(coordinator.update(from: .foreground) == .foreground)

        // Act
        let closedActivity = coordinator.update(
            from: BridgePaneActivityFacts.foreground.replacing(isAuthorityClosed: true)
        )
        let attemptedReopenActivity = coordinator.update(from: .foreground)

        // Assert
        #expect(closedActivity == .closed)
        #expect(attemptedReopenActivity == .closed)
    }

}

enum BridgePaneActivityFactMutation: String, CaseIterable, CustomTestStringConvertible, Sendable {
    case inactiveResidency
    case controllerUninstalled
    case inactiveTab
    case inactiveArrangementAndDrawer
    case minimized
    case zoomExcluded

    static let allForegroundDemotions = Array(allCases)

    var testDescription: String { rawValue }

    func apply(to facts: BridgePaneActivityFacts) -> BridgePaneActivityFacts {
        switch self {
        case .inactiveResidency:
            return facts.replacing(residency: .backgrounded)
        case .controllerUninstalled:
            return facts.replacing(isControllerInstalled: false)
        case .inactiveTab:
            return facts.replacing(isInActiveTab: false)
        case .inactiveArrangementAndDrawer:
            return facts.replacing(isInActiveArrangement: false, isInExpandedDrawer: false)
        case .minimized:
            return facts.replacing(isMinimized: true)
        case .zoomExcluded:
            return facts.replacing(isZoomExcluded: true)
        }
    }
}

extension BridgePaneActivityFacts {
    fileprivate static let foreground = Self(
        residency: .active,
        isControllerInstalled: true,
        isInActiveTab: true,
        isInActiveArrangement: true,
        isInExpandedDrawer: false,
        isMinimized: false,
        isZoomExcluded: false,
        isAuthorityClosed: false
    )

    fileprivate func replacing(
        residency: SessionResidency? = nil,
        isControllerInstalled: Bool? = nil,
        isInActiveTab: Bool? = nil,
        isInActiveArrangement: Bool? = nil,
        isInExpandedDrawer: Bool? = nil,
        isMinimized: Bool? = nil,
        isZoomExcluded: Bool? = nil,
        isAuthorityClosed: Bool? = nil
    ) -> Self {
        Self(
            residency: residency ?? self.residency,
            isControllerInstalled: isControllerInstalled ?? self.isControllerInstalled,
            isInActiveTab: isInActiveTab ?? self.isInActiveTab,
            isInActiveArrangement: isInActiveArrangement ?? self.isInActiveArrangement,
            isInExpandedDrawer: isInExpandedDrawer ?? self.isInExpandedDrawer,
            isMinimized: isMinimized ?? self.isMinimized,
            isZoomExcluded: isZoomExcluded ?? self.isZoomExcluded,
            isAuthorityClosed: isAuthorityClosed ?? self.isAuthorityClosed
        )
    }
}
