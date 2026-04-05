import SwiftUI

/// SwiftUI toggle button for the management mode toolbar item.
/// Shows `rectangle.split.2x2` (outline) when inactive,
/// `rectangle.split.2x2.fill` with accent tint when active.
struct ManagementModeToolbarButton: View {
    private var isManagementModeActive: Bool {
        atom(\.managementMode).isActive
    }

    var body: some View {
        Button {
            ManagementModeMonitor.shared.toggle()
        } label: {
            Image(
                systemName: isManagementModeActive
                    ? "rectangle.split.2x2.fill"
                    : "rectangle.split.2x2"
            )
            .font(.system(size: AppStyle.textLg, weight: .medium))
            .foregroundStyle(isManagementModeActive ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
        .help("Toggle Management Mode (\u{2318}E)")
        .frame(width: 36, height: 24)
    }
}
