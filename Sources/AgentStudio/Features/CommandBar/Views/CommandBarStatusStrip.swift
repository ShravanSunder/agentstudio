import SwiftUI

// MARK: - CommandBarStatusStrip

/// Top row of the command bar showing mode and current pane context.
struct CommandBarStatusStrip: View {
    let mode: CommandBarAppMode
    let context: WorkspaceFocus

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: mode.icon)
                    .font(.system(size: AppStyle.textXs, weight: .medium))
                Text(mode.label)
                    .font(.system(size: AppStyle.textXs, weight: .medium))
            }
            .foregroundStyle(mode.isAccented ? Color.accentColor : .primary.opacity(0.35))

            Spacer()

            if let icon = context.icon, let label = context.label {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: AppStyle.textXs, weight: .medium))
                    Text(label)
                        .font(.system(size: AppStyle.textXs, weight: .medium))
                }
                .foregroundStyle(.primary.opacity(0.35))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
    }
}
