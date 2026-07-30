import Foundation

package enum ZoomCommandEffect: Equatable, Sendable {
    case enter
    case cancel
    case retarget
    case resume
}

package struct ZoomCommandCapability: Equatable, Sendable {
    package let tabId: UUID
    package let sourcePaneId: UUID
    package let effect: ZoomCommandEffect
    package let requiresTabActivation: Bool
}

package struct ZoomCommandCandidate: Equatable, Sendable {
    package let paneId: UUID
    package let tabId: UUID
    package let isEligible: Bool

    package init(
        paneId: UUID,
        tabId: UUID,
        isEligible: Bool
    ) {
        self.paneId = paneId
        self.tabId = tabId
        self.isEligible = isEligible
    }
}

package enum ZoomCommandCapabilityPolicy {
    package static func isPaneContentEligible(_ content: PaneContent) -> Bool {
        switch content {
        case .terminal:
            return true
        case .webview, .bridgePanel, .codeViewer, .unsupported:
            return false
        }
    }

    package static func resolve(
        activeTabId: UUID?,
        activePaneId: UUID?,
        explicitPaneId: UUID?,
        candidate: ZoomCommandCandidate?,
        zoomSourcePaneId: UUID?
    ) -> ZoomCommandCapability? {
        if let explicitPaneId {
            guard
                let candidate,
                candidate.paneId == explicitPaneId
            else {
                return nil
            }
            let targetTabId = candidate.tabId
            let requiresTabActivation = activeTabId != targetTabId

            if !requiresTabActivation, zoomSourcePaneId == explicitPaneId {
                return ZoomCommandCapability(
                    tabId: targetTabId,
                    sourcePaneId: explicitPaneId,
                    effect: .cancel,
                    requiresTabActivation: false
                )
            }

            guard candidate.isEligible else {
                return nil
            }

            if requiresTabActivation {
                let effect: ZoomCommandEffect
                if zoomSourcePaneId == explicitPaneId {
                    effect = .resume
                } else if zoomSourcePaneId != nil {
                    effect = .retarget
                } else {
                    effect = .enter
                }
                return ZoomCommandCapability(
                    tabId: targetTabId,
                    sourcePaneId: explicitPaneId,
                    effect: effect,
                    requiresTabActivation: true
                )
            }

            let effect: ZoomCommandEffect
            if zoomSourcePaneId != nil {
                effect = .retarget
            } else {
                effect = .enter
            }
            return ZoomCommandCapability(
                tabId: targetTabId,
                sourcePaneId: explicitPaneId,
                effect: effect,
                requiresTabActivation: false
            )
        }

        guard let activeTabId else {
            return nil
        }
        if let zoomSourcePaneId {
            return ZoomCommandCapability(
                tabId: activeTabId,
                sourcePaneId: zoomSourcePaneId,
                effect: .cancel,
                requiresTabActivation: false
            )
        }
        guard
            let activePaneId,
            let candidate,
            candidate.paneId == activePaneId,
            candidate.tabId == activeTabId,
            candidate.isEligible
        else {
            return nil
        }
        return ZoomCommandCapability(
            tabId: activeTabId,
            sourcePaneId: activePaneId,
            effect: .enter,
            requiresTabActivation: false
        )
    }
}
