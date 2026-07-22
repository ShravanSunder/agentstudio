import Foundation
import Testing

@testable import AgentStudio

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

    @Test("an installed controller with every native visibility fact is foreground")
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

    @Test("loaded hidden state can return to foreground when all facts recover")
    func loadedHiddenCanReturnToForeground() {
        // Arrange
        let coordinator = BridgePaneActivityCoordinator()
        #expect(coordinator.update(from: .foreground) == .foreground)
        #expect(
            coordinator.update(
                from: BridgePaneActivityFacts.foreground.replacing(isApplicationActive: false)
            ) == .loadedHidden
        )

        // Act
        let recoveredActivity = coordinator.update(from: .foreground)

        // Assert
        #expect(recoveredActivity == .foreground)
    }
}

enum BridgePaneActivityFactMutation: String, CaseIterable, CustomTestStringConvertible, Sendable {
    case inactiveResidency
    case controllerUninstalled
    case inactiveTab
    case inactiveArrangementAndDrawer
    case minimized
    case zoomExcluded
    case hiddenWindow
    case miniaturizedWindow
    case occludedWindow
    case inactiveApplication

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
        case .hiddenWindow:
            return facts.replacing(isOwningWindowVisible: false)
        case .miniaturizedWindow:
            return facts.replacing(isOwningWindowMiniaturized: true)
        case .occludedWindow:
            return facts.replacing(isOwningWindowOccluded: true)
        case .inactiveApplication:
            return facts.replacing(isApplicationActive: false)
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
        isOwningWindowVisible: true,
        isOwningWindowMiniaturized: false,
        isOwningWindowOccluded: false,
        isApplicationActive: true,
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
        isOwningWindowVisible: Bool? = nil,
        isOwningWindowMiniaturized: Bool? = nil,
        isOwningWindowOccluded: Bool? = nil,
        isApplicationActive: Bool? = nil,
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
            isOwningWindowVisible: isOwningWindowVisible ?? self.isOwningWindowVisible,
            isOwningWindowMiniaturized: isOwningWindowMiniaturized ?? self.isOwningWindowMiniaturized,
            isOwningWindowOccluded: isOwningWindowOccluded ?? self.isOwningWindowOccluded,
            isApplicationActive: isApplicationActive ?? self.isApplicationActive,
            isAuthorityClosed: isAuthorityClosed ?? self.isAuthorityClosed
        )
    }
}
