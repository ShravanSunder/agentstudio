import SwiftUI

struct SidebarSurfaceTabBarControls: View {
    private var sidebarState: WorkspaceSidebarState {
        atom(\.workspaceSidebarState)
    }

    private var isSidebarOpen: Bool {
        !sidebarState.sidebarCollapsed
    }

    var body: some View {
        HStack(spacing: AppStyles.Shell.Chrome.sidebarSurfaceIconSpacing) {
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
        Button {
            AppCommandDispatcher.shared.dispatch(.watchFolder)
        } label: {
            ChromeToolbarButtonLabel(
                symbolName: "folder.badge.plus",
                isHovered: isHovered
            )
        }
        .buttonStyle(.plain)
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

struct SidebarNavDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(AppStyles.General.Fill.hover))
            .frame(width: 1, height: AppStyles.Shell.Chrome.dividerHeight)
            .padding(.leading, AppStyles.Shell.Chrome.sidebarDividerLeadingPadding)
            .padding(.trailing, AppStyles.Shell.Chrome.sidebarDividerTrailingPadding)
    }
}
