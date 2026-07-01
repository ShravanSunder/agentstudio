import CoreGraphics
import Foundation

enum TabBarChromeControl: Equatable, Hashable {
    case sidebarSurfaces
    case divider
    case watchFolder
    case managementLayer
    case arrangement
    case newTab
    case tabStrip
    case overflowLeft
    case overflowRight
    case overflowMenu
}

enum TabBarChromeControlStyle: Equatable {
    case divider
    case plainIcon
    case toolbarButton
    case tabStrip
}

enum TabBarOverflowScrollDirection: Equatable {
    case left
    case right
}

enum TabBarOverflowScrollTargetResolver {
    static func targetTabId(
        direction: TabBarOverflowScrollDirection,
        orderedTabIds: [UUID],
        tabFrames: [UUID: CGRect],
        visibleFrame: CGRect
    ) -> UUID? {
        guard visibleFrame.width > 0 else { return nil }

        switch direction {
        case .right:
            return orderedTabIds.first { tabId in
                guard let frame = tabFrames[tabId] else { return false }
                return frame.maxX > visibleFrame.maxX
            }
        case .left:
            return orderedTabIds.last { tabId in
                guard let frame = tabFrames[tabId] else { return false }
                return frame.minX < visibleFrame.minX
            }
        }
    }
}

struct TabBarChromeLayoutPlan: Equatable {
    let hasNewTab: Bool
    let isOverflowing: Bool

    var showsTrailingControls: Bool {
        isOverflowing
    }

    var leadingControls: [TabBarChromeControl] {
        var controls: [TabBarChromeControl] = []
        for control in controlOrder {
            guard control != .tabStrip else { break }
            controls.append(control)
        }
        return controls
    }

    var trailingControls: [TabBarChromeControl] {
        guard showsTrailingControls else { return [] }
        guard let tabStripIndex = controlOrder.firstIndex(of: .tabStrip) else { return [] }
        return Array(controlOrder.dropFirst(tabStripIndex + 1))
    }

    var controlStyles: [TabBarChromeControl: TabBarChromeControlStyle] {
        [
            .sidebarSurfaces: .plainIcon,
            .divider: .divider,
            .watchFolder: .toolbarButton,
            .managementLayer: .toolbarButton,
            .arrangement: .toolbarButton,
            .newTab: .toolbarButton,
            .tabStrip: .tabStrip,
            .overflowLeft: .plainIcon,
            .overflowRight: .plainIcon,
            .overflowMenu: .plainIcon,
        ]
    }

    var controlOrder: [TabBarChromeControl] {
        var controls: [TabBarChromeControl] = [
            .sidebarSurfaces,
            .divider,
            .watchFolder,
            .divider,
            .managementLayer,
            .arrangement,
            .divider,
        ]
        if hasNewTab {
            controls.append(.newTab)
        }
        controls.append(.tabStrip)
        if showsTrailingControls {
            controls.append(contentsOf: [.divider, .overflowLeft, .overflowRight, .overflowMenu])
        }
        return controls
    }
}
