import SwiftUI

struct DrawerIconBar: View {
    let tooltipValue: ControlTooltipRenderValue

    var body: some View {
        Button("Add") {}
            .controlHelp(tooltipValue)

        FloatingHoverTooltipPresenter(
            activeTarget: "add",
            anchorFrames: [:],
            availableWidth: 100,
            tooltipValue: { _ in tooltipValue }
        )
    }
}
