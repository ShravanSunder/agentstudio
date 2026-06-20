import SwiftUI

struct DrawerIconBar: View {
    let tooltipText: String

    var body: some View {
        Button("Add") {}
            .help(tooltipText)

        FloatingHoverTooltipPresenter(
            activeTarget: "add",
            anchorFrames: [:],
            availableWidth: 100,
            tooltipText: { _ in "Add drawer pane" }
        )
    }
}
