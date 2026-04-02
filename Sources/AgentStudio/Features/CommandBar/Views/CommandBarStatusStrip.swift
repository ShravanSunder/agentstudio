import SwiftUI

// MARK: - CommandBarStatusStrip

/// Top row of the command bar showing mode and current pane context.
struct CommandBarStatusStrip: View {
    let mode: CommandBarAppMode
    let context: CommandBarAppContext

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

            HStack(spacing: 4) {
                Image(systemName: context.icon)
                    .font(.system(size: AppStyle.textXs, weight: .medium))
                Text(context.label)
                    .font(.system(size: AppStyle.textXs, weight: .medium))
            }
            .foregroundStyle(.primary.opacity(0.35))
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
    }
}
