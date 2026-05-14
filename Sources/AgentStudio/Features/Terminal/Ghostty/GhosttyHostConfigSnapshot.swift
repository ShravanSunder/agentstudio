import AppKit
import Foundation
import GhosttyKit

enum GhosttyScrollbarPolicy: Equatable {
    case system
    case never
}

struct GhosttyHostConfigSnapshot: Equatable {
    let scrollbarPolicy: GhosttyScrollbarPolicy
    let backgroundColor: NSColor

    init(scrollbarPolicy: GhosttyScrollbarPolicy, backgroundColor: NSColor) {
        self.scrollbarPolicy = scrollbarPolicy
        self.backgroundColor = backgroundColor
    }

    init(configHandle: ghostty_config_t?) {
        guard let configHandle else {
            self.scrollbarPolicy = .system
            self.backgroundColor = .windowBackgroundColor
            return
        }

        var scrollbarValue: UnsafePointer<Int8>?
        let scrollbarKey = "scrollbar"
        if ghostty_config_get(
            configHandle,
            &scrollbarValue,
            scrollbarKey,
            UInt(scrollbarKey.lengthOfBytes(using: .utf8))
        ), let scrollbarValue {
            self.scrollbarPolicy = String(cString: scrollbarValue) == "never" ? .never : .system
        } else {
            self.scrollbarPolicy = .system
        }

        var backgroundValue = ghostty_config_color_s()
        let backgroundKey = "background"
        if ghostty_config_get(
            configHandle,
            &backgroundValue,
            backgroundKey,
            UInt(backgroundKey.lengthOfBytes(using: .utf8))
        ) {
            self.backgroundColor = NSColor(
                calibratedRed: CGFloat(backgroundValue.r) / 255.0,
                green: CGFloat(backgroundValue.g) / 255.0,
                blue: CGFloat(backgroundValue.b) / 255.0,
                alpha: 1
            )
        } else {
            self.backgroundColor = .windowBackgroundColor
        }
    }
}
