import SwiftUI

/// SwiftUI toggle button for the management layer toolbar item.
/// Shows `rectangle.split.2x2` (outline) when inactive,
/// `rectangle.split.2x2.fill` with accent tint when active.
struct ManagementLayerToolbarButton: View {
    private var isManagementLayerActive: Bool {
        atom(\.managementLayer).isActive
    }

    var body: some View {
        Button {
            atom(\.managementLayer).toggle()
        } label: {
            Image(
                systemName: isManagementLayerActive
                    ? "rectangle.split.2x2.fill"
                    : "rectangle.split.2x2"
            )
            .font(.system(size: AppStyle.textLg, weight: .medium))
            .foregroundStyle(isManagementLayerActive ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
        .help(CommandDispatcher.shared.definition(for: .toggleManagementLayer).controlToolTip)
        .frame(width: 36, height: 24)
    }
}
