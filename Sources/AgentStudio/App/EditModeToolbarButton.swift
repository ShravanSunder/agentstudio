import SwiftUI

/// SwiftUI toggle button for the edit mode toolbar item.
/// Shows `rectangle.split.2x2` (outline) when inactive,
/// `rectangle.split.2x2.fill` with accent tint when active.
struct EditModeToolbarButton: View {
    @Bindable private var managementMode = ManagementModeMonitor.shared

    var body: some View {
        Button {
            managementMode.toggle()
        } label: {
            Image(
                systemName: managementMode.isActive
                    ? "rectangle.split.2x2.fill"
                    : "rectangle.split.2x2"
            )
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(managementMode.isActive ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
        .help("Toggle Edit Mode (\u{2318}E)")
        .frame(width: 36, height: 24)
    }
}
