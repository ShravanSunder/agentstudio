import SwiftUI

struct BadTooltipSourceComponent: View {
    let actionSpec: ActionSpec
    let source: ControlTooltipSource
    let commandIdentifier: IPCCommandIdentifier
    let localAction: LocalActionSpec

    var body: some View {
        Text(String(describing: source))
    }
}
