import SwiftUI

struct SidebarSurfaceTabBarControls: View {
    private var sidebarState: WorkspaceSidebarState {
        atom(\.workspaceSidebarState)
    }

    private var isSidebarOpen: Bool {
        !sidebarState.sidebarCollapsed
    }

    var body: some View {
        HStack(spacing: AppStyles.Shell.Chrome.iconClusterSpacing) {
            SidebarSurfaceTabBarButton(
                command: .showWorktreeSidebar,
                symbolName: "square.stack.3d.down.right",
                selectedSymbolName: "square.stack.3d.down.right.fill",
                isSelected: isSidebarOpen && sidebarState.sidebarSurface == .repos
            )

            SidebarSurfaceTabBarButton(
                command: .showInboxNotifications,
                symbolName: "bell",
                selectedSymbolName: "bell.fill",
                isSelected: isSidebarOpen && sidebarState.sidebarSurface == .inbox,
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
                badgeText: badgeCount > 0 ? InboxToolbarUnreadBadgeText.text(for: badgeCount) : nil,
                showsBackground: false
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
                isHovered: isHovered,
                showsBackground: false
            )
        } primaryAction: {
            AppCommandDispatcher.shared.dispatch(.watchFolder)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .frame(
            width: AppStyles.Shell.Chrome.ToolbarButton.size,
            height: AppStyles.Shell.Chrome.ToolbarButton.size
        )
        .background(ChromeToolbarCircleBackground(isHovered: isHovered))
        .contentShape(Circle())
        .onHover { isHovered = $0 }
        .help(commandDefinition.controlToolTip)
    }
}

struct TabBarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(AppStyles.General.Fill.hover))
            .frame(width: 1, height: AppStyles.Shell.Chrome.dividerHeight)
            .padding(.horizontal, AppStyles.Shell.Chrome.dividerHorizontalPadding)
    }
}
