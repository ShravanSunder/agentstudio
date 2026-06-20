import AppKit

extension NSButton {
    func applyControlTooltip(_ renderValue: ControlTooltipRenderValue) {
        toolTip = renderValue.text
    }
}

extension NSToolbarItem {
    func applyControlTooltip(_ renderValue: ControlTooltipRenderValue) {
        toolTip = renderValue.text
    }
}
