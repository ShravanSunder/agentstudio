import SwiftUI

struct ManagementOrdinalShortcutHint: View {
    let ordinal: Int

    var body: some View {
        Text("\(ordinal)")
            .font(.system(size: AppStyles.Shell.ManagementLayer.actionIconSize, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(AppStyles.Shell.ManagementLayer.iconOpacity(isHovered: false)))
            .frame(
                width: AppStyles.Shell.ManagementLayer.actionSize,
                height: AppStyles.Shell.ManagementLayer.actionSize
            )
            .background(
                Circle()
                    .fill(
                        Color.black.opacity(
                            AppStyles.Shell.ManagementLayer.backgroundOpacity(isHovered: false)
                        )
                    )
            )
            .contentShape(Circle())
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
