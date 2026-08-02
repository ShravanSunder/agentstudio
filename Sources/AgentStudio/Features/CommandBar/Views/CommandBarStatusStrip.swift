import AgentStudioCore
import AgentStudioInfrastructure
import SwiftUI

// MARK: - CommandBarStatusStrip

/// Top row of the command bar showing optional management state and current pane context.
struct CommandBarStatusStrip: View {
    let mode: CommandBarAppMode
    let focusedPane: WorkspaceFocusedPane?

    init(
        mode: CommandBarAppMode,
        focusedPane: WorkspaceFocusedPane?
    ) {
        self.mode = mode
        self.focusedPane = focusedPane
    }

    var body: some View {
        HStack {
            if let icon = mode.statusStripIcon, let label = mode.statusStripLabel {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: AppStyles.General.Typography.textXs, weight: .medium))
                    Text(label)
                        .font(.system(size: AppStyles.General.Typography.textXs, weight: .medium))
                }
                .foregroundStyle(Color.accentColor)
            }

            Spacer()

            if let focusedPane {
                HStack(spacing: 4) {
                    Image(systemName: focusedPane.commandBarStatusIcon)
                        .font(.system(size: AppStyles.General.Typography.textXs, weight: .medium))
                    Text(focusedPane.commandBarStatusLabel)
                        .font(.system(size: AppStyles.General.Typography.textXs, weight: .medium))
                }
                .foregroundStyle(.primary.opacity(AppStyles.CommandBar.Rows.statusContextOpacity))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
    }
}

extension WorkspaceFocusedPane {
    var commandBarStatusLabel: String {
        switch contentType {
        case .terminal:
            return "Terminal"
        case .webview:
            return "Webview"
        case .bridge:
            return "Bridge"
        case .codeViewer:
            return "Code Viewer"
        case .unsupported:
            return "Unsupported"
        }
    }

    var commandBarStatusIcon: String {
        switch contentType {
        case .terminal:
            return "terminal"
        case .webview:
            return "globe"
        case .bridge:
            return "rectangle.split.2x1"
        case .codeViewer:
            return "doc.text"
        case .unsupported:
            return "questionmark.square"
        }
    }
}
