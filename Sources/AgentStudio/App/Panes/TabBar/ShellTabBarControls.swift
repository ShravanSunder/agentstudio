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
            Image(systemName: isSelected ? selectedSymbolName : symbolName)
                .font(.system(size: AppStyles.General.Icon.compact, weight: .medium))
                .foregroundStyle(
                    isSelected
                        ? Color.accentColor
                        : (isHovered ? .primary : .secondary)
                )
                .frame(width: AppStyles.General.Button.toolbar, height: AppStyles.General.Button.toolbar)
                .background(
                    Circle()
                        .fill(
                            isSelected
                                ? Color.accentColor.opacity(AppStyles.General.Fill.active)
                                : Color.white.opacity(
                                    isHovered ? AppStyles.General.Fill.pressed : AppStyles.General.Fill.muted)
                        )
                )
                .overlay(alignment: .topTrailing) {
                    if badgeCount > 0 {
                        UnreadCountBadge(text: InboxToolbarUnreadBadgeText.text(for: badgeCount))
                            .offset(x: 6, y: -5)
                    }
                }
                .contentShape(Circle())
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
            Image(systemName: "folder.badge.plus")
                .font(.system(size: AppStyles.General.Icon.compact, weight: .medium))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: AppStyles.General.Button.toolbar, height: AppStyles.General.Button.toolbar)
                .background(
                    Circle()
                        .fill(
                            Color.white.opacity(
                                isHovered
                                    ? AppStyles.General.Fill.pressed
                                    : AppStyles.General.Fill.muted
                            )
                        )
                )
                .contentShape(Circle())
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
