import SwiftUI

struct DrawerIconBar: View {
    let tooltipText: String

    var body: some View {
        SwiftUI.Button(action: action) { Text("Pin") }
        Button.init(action: action) { Text("Pin") }
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
