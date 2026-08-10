import CoreGraphics
import Foundation

enum TabBarChromeControl: Equatable, Hashable {
    case tabStrip
    case overflowLeft
    case overflowRight
}

enum TabBarChromeControlStyle: Equatable {
    case plainIcon
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
    let isOverflowing: Bool

    var showsTrailingControls: Bool {
        isOverflowing
    }

    var trailingControls: [TabBarChromeControl] {
        guard showsTrailingControls else { return [] }
        return Array(workspaceTabControls.dropFirst())
    }

    var controlStyles: [TabBarChromeControl: TabBarChromeControlStyle] {
        [
            .tabStrip: .tabStrip,
            .overflowLeft: .plainIcon,
            .overflowRight: .plainIcon,
        ]
    }

    var workspaceTabControls: [TabBarChromeControl] {
        var controls: [TabBarChromeControl] = [.tabStrip]
        if isOverflowing {
            controls.append(contentsOf: [.overflowLeft, .overflowRight])
        }
        return controls
    }
}
