import SwiftUI

struct SidebarSurfaceTabBarControls: View {
    private var sidebarState: WorkspaceSidebarState {
        atom(\.workspaceSidebarState)
    }

    var body: some View {
        HStack(spacing: AppStyles.General.Spacing.tight) {
            SidebarSurfaceTabBarButton(
                command: .showWorktreeSidebar,
                symbolName: "square.stack.3d.down.right",
                selectedSymbolName: "square.stack.3d.down.right.fill",
                isSelected: sidebarState.sidebarSurface == .repos
            )

            SidebarSurfaceTabBarButton(
                command: .showInboxNotifications,
                symbolName: "bell",
                selectedSymbolName: "bell.fill",
                isSelected: sidebarState.sidebarSurface == .inbox,
                badgeCount: atom(\.inboxNotification).globalRollUpAlertCount
            )
        }
    }
}

private struct SidebarSurfaceTabBarButton: View {
    let command: AppCommand
    let symbolName: String
    let selectedSymbolName: String
    let isSelected: Bool
    var badgeCount = 0

    @State private var isHovered = false

    private var commandDefinition: AppCommandSpec {
        AppCommandDispatcher.shared.definition(for: command)
    }

    var body: some View {
        Button {
            AppCommandDispatcher.shared.dispatch(command)
        } label: {
            ChromeToolbarButtonLabel(
                symbolName: symbolName,
                selectedSymbolName: selectedSymbolName,
                isSelected: isSelected,
                isHovered: isHovered,
                badgeText: badgeCount > 0 ? InboxToolbarUnreadBadgeText.text(for: badgeCount) : nil
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(commandDefinition.controlToolTip)
    }
}

struct WatchFolderTabBarMenu: View {
    @State private var isHovered = false

    private var commandDefinition: AppCommandSpec {
        AppCommandDispatcher.shared.definition(for: .watchFolder)
    }

    var body: some View {
        Menu {
            Button(commandDefinition.label) {
                AppCommandDispatcher.shared.dispatch(.watchFolder)
            }
        } label: {
            ChromeToolbarButtonLabel(
                symbolName: "folder.badge.plus",
                isHovered: isHovered
            )
        } primaryAction: {
            AppCommandDispatcher.shared.dispatch(.watchFolder)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovered = $0 }
        .help(commandDefinition.controlToolTip)
    }
}

struct TabBarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(AppStyles.General.Fill.hover))
            .frame(width: 1, height: 18)
            .padding(.horizontal, AppStyles.General.Spacing.tight)
    }
}
