import SwiftUI

extension View {
    func controlHelp(_ renderValue: ControlTooltipRenderValue) -> some View {
        help(renderValue.text)
    }
}
