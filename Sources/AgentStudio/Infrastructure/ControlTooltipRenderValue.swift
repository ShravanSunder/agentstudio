import Foundation

package struct ControlTooltipRenderValue: Equatable, Sendable {
    package let text: String
    package let shortcutDisplayText: ShortcutDisplayText?

    package init(text: String, shortcutDisplayText: ShortcutDisplayText?) {
        self.text = text
        self.shortcutDisplayText = shortcutDisplayText
    }
}
