import AgentStudioInfrastructure
import SwiftUI

extension View {
    package func controlHelp(_ renderValue: ControlTooltipRenderValue) -> some View {
        help(renderValue.text)
    }
}
