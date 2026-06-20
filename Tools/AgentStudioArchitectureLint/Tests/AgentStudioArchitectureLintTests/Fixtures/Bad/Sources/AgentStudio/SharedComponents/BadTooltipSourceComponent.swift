import SwiftUI

struct BadTooltipSourceComponent: View {
    let source: ControlTooltipSource
    let commandIdentifier: IPCCommandIdentifier

    var body: some View {
        Text(String(describing: source))
    }
}
