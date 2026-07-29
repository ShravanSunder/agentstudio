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
        mainPaneTabIdByPaneId: [UUID: UUID],
        zoomEligiblePaneIds: Set<UUID>,
        zoomSourcePaneIdByTabId: [UUID: UUID]
    ) -> ZoomCommandCapability? {
        if let explicitPaneId {
            guard let targetTabId = mainPaneTabIdByPaneId[explicitPaneId] else {
                return nil
            }
            let requiresTabActivation = activeTabId != targetTabId
            let zoomSourcePaneId = zoomSourcePaneIdByTabId[targetTabId]

            if !requiresTabActivation, zoomSourcePaneId == explicitPaneId {
                return ZoomCommandCapability(
                    tabId: targetTabId,
                    sourcePaneId: explicitPaneId,
                    effect: .cancel,
                    requiresTabActivation: false
                )
            }

            guard zoomEligiblePaneIds.contains(explicitPaneId) else {
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
        if let zoomSourcePaneId = zoomSourcePaneIdByTabId[activeTabId] {
            return ZoomCommandCapability(
                tabId: activeTabId,
                sourcePaneId: zoomSourcePaneId,
                effect: .cancel,
                requiresTabActivation: false
            )
        }
        guard
            let activePaneId,
            mainPaneTabIdByPaneId[activePaneId] == activeTabId,
            zoomEligiblePaneIds.contains(activePaneId)
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
