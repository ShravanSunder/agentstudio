import SwiftUI

struct DrawerIconBar: View {
    let tooltipValue: ControlTooltipRenderValue

    var body: some View {
        ToolbarActionButton(presentation: presentation, octiconLoader: loader, action: action)
            .controlHelp(tooltipValue)

        FloatingHoverTooltipPresenter(
            activeTarget: "add",
            anchorFrames: [:],
            availableWidth: 100,
            tooltipValue: { _ in tooltipValue }
        )
    }
}
